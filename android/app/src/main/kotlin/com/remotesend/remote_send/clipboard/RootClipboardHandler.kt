package com.remotesend.remote_send.clipboard

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedWriter
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import org.json.JSONObject

/** Explicit, page-scoped experiment. No boot receiver, daemon install or network access. */
internal class RootClipboardHandler(context: Context, messenger: BinaryMessenger, private val syncOwner: Boolean = false) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newCachedThreadPool()
    private val commands = Executors.newSingleThreadExecutor()
    private val methods = MethodChannel(messenger, "remote_send/root_clipboard")
    private val events = EventChannel(messenger, "remote_send/root_clipboard_events")
    private var sink: EventChannel.EventSink? = null
    private var process: Process? = null
    private var writer: BufferedWriter? = null
    @Volatile private var generation = 0
    private var requestId = 0L
    private var starting: MethodChannel.Result? = null
    private var startTimeout: Runnable? = null
    private var ready: Map<String, Any>? = null
    private var disposed = false
    private var ownsBridge = false
    private data class Pending(val result: MethodChannel.Result, val timeout: Runnable)
    private val pending = mutableMapOf<Long, Pending>()

    init {
        methods.setMethodCallHandler(::onMethod)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null; stop("stopped") }
        })
    }

    private fun onMethod(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("stopped", "Bridge is stopped", null); return }
        when (call.method) {
            "start" -> start(result)
            "stop" -> { stop("stopped"); result.success(null) }
            "read" -> request("read", null, result)
            "write" -> {
                val text = call.argument<Any?>("text") as? String
                if (text == null || ClipboardBridgeProtocol.textKind(text) != "text") {
                    result.error("invalid_request", "Expected nonempty text up to 32 KiB", null)
                } else request("write", text, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(result: MethodChannel.Result) {
        ready?.let { result.success(it); return }
        if (starting != null) { result.error("busy", "Authorization is in progress", null); return }
        val owner = if (syncOwner) "sync" else "diagnostics"
        if (!ClipboardBridgeOwnership.acquire(owner)) { result.error("busy", "Another clipboard bridge is active", null); return }
        ownsBridge = true
        val current = ++generation
        starting = result
        startTimeout = Runnable { if (current == generation) stop("startup_timeout") }.also {
            main.postDelayed(it, 60_000)
        }
        worker.execute {
            try {
                val child = ProcessBuilder(ClipboardBridgeProtocol.launchArguments(
                    app.applicationInfo.sourceDir, app.applicationInfo.uid
                )).start()
                val out = BufferedWriter(OutputStreamWriter(child.outputStream, StandardCharsets.UTF_8))
                main.post {
                    if (disposed || current != generation) {
                        destroy(child, out)
                    } else {
                        process = child
                        writer = out
                        worker.execute { readOutput(child, current) }
                        worker.execute {
                            // Root-manager diagnostics are never echoed or logged (may be unsafe).
                            try { child.errorStream.use { stream ->
                                val buffer = ByteArray(1024)
                                while (stream.read(buffer) != -1) { /* discard bounded chunks */ }
                            } } catch (_: Exception) { }
                        }
                    }
                }
            } catch (_: Exception) {
                main.post { if (current == generation) stop("root_unavailable") }
            }
        }
    }

    private fun readOutput(child: Process, current: Int) {
        try {
            child.inputStream.bufferedReader(StandardCharsets.UTF_8).use { input ->
                while (true) {
                    val line = ClipboardBridgeProtocol.readLine(input) ?: break
                    val message = JSONObject(line)
                    main.post {
                        if (!disposed && current == generation) {
                            try { handle(message) } catch (_: Exception) { stop("invalid_response") }
                        }
                    }
                }
            }
        } catch (_: Exception) {
            main.post { if (current == generation) stop("invalid_response") }
        } finally {
            main.post { if (current == generation) stop(if (ready == null) "root_unavailable" else "disconnected") }
        }
    }

    private fun handle(message: JSONObject) {
        when (message.optString("event")) {
            "ready" -> {
                check(message.getInt("version") == ClipboardBridgeProtocol.VERSION)
                check(message.getInt("uid") == ClipboardBridgeProtocol.SHELL_UID)
                check(message.getInt("userId") == app.applicationInfo.uid / 100000)
                val info = mapOf<String, Any>(
                    "session" to generation,
                    "sdk" to message.getInt("sdk"), "uid" to message.getInt("uid"),
                    "userId" to message.getInt("userId"), "api" to message.getString("api")
                )
                ready = info
                startTimeout?.let(main::removeCallbacks); startTimeout = null
                starting?.success(info); starting = null
            }
            "clipboard" -> {
                check(ready != null)
                // Events contain metadata only; never buffer clipboard bodies in Flutter's event queue.
                sink?.success(mapOf("event" to "clipboard", "session" to generation,
                    "snapshot" to snapshot(message.getJSONObject("snapshot"), false)))
            }
            "error" -> {
                val code = safeCode(message.optString("code"))
                if (ready == null) stop(code)
                else sink?.success(mapOf("event" to "error", "session" to generation, "code" to code))
            }
            else -> {
                val id = message.getLong("id")
                val call = pending.remove(id) ?: return
                main.removeCallbacks(call.timeout)
                if (message.has("error")) call.result.error(safeCode(message.getString("error")), "Clipboard operation failed", null)
                else {
                    try { call.result.success(snapshot(message.getJSONObject("snapshot"), true)) }
                    catch (_: Exception) {
                        call.result.error("invalid_response", "Invalid bridge response", null)
                        stop("invalid_response")
                    }
                }
            }
        }
    }

    private fun snapshot(value: JSONObject, includeText: Boolean): Map<String, Any> {
        val kind = value.getString("kind")
        check(kind in setOf("text", "empty", "non_text", "sensitive", "too_large", "unavailable"))
        val result = mutableMapOf<String, Any>("kind" to kind, "internal" to value.getBoolean("internal"))
        if (value.has("bytes")) result["bytes"] = value.getInt("bytes").also { check(it >= 0) }
        if (includeText && value.has("text")) {
            val text = value.getString("text")
            check(kind == "text" && ClipboardBridgeProtocol.textKind(text) == "text")
            result["text"] = text
        }
        return result
    }

    private fun request(op: String, text: String?, result: MethodChannel.Result) {
        val out = writer
        if (ready == null || out == null) { result.error("not_connected", "Start the bridge first", null); return }
        if (pending.size >= 8) { result.error("busy", "Too many pending operations", null); return }
        val id = ++requestId
        val current = generation
        val timeout = Runnable { if (current == generation) stop("request_timeout") }
        pending[id] = Pending(result, timeout)
        main.postDelayed(timeout, 5_000)
        val command = JSONObject().put("id", id).put("op", op).apply { if (text != null) put("text", text) }
        commands.execute {
            try {
                synchronized(out) {
                    if (current == generation) { out.write(command.toString()); out.newLine(); out.flush() }
                }
            } catch (_: Exception) {
                main.post { if (current == generation) stop("disconnected") }
            }
        }
    }

    private fun stop(code: String) {
        val previous = generation
        ++generation
        if (ownsBridge) {
            ownsBridge = false
            ClipboardBridgeOwnership.release(if (syncOwner) "sync" else "diagnostics")
        }
        startTimeout?.let(main::removeCallbacks); startTimeout = null
        starting?.error(code, "Root clipboard bridge stopped", null); starting = null
        for (call in pending.values) {
            main.removeCallbacks(call.timeout)
            call.result.error(code, "Root clipboard bridge stopped", null)
        }
        pending.clear()
        val child = process
        val out = writer
        process = null; writer = null; ready = null
        if (child != null) destroy(child, out)
        sink?.success(mapOf("event" to "stopped", "session" to previous, "code" to code))
    }

    private fun destroy(child: Process, out: BufferedWriter?) {
        // A launch can finish after dispose(), when the executor is already shut down.
        Thread({
            // EOF makes the helper unregister its listener and exit, even if su is only a parent.
            try { out?.close() } catch (_: Exception) { }
            child.destroy()
            try { child.inputStream.close(); child.errorStream.close() } catch (_: Exception) { }
        }, "clipboard-cleanup").apply { isDaemon = true; start() }
    }

    private fun safeCode(code: String): String = if (code in setOf(
        "permission_denied", "wrong_identity", "unsupported_api", "invalid_request", "bridge_failed"
    )) code else "bridge_failed"

    fun dispose() {
        if (disposed) return
        disposed = true
        sink = null
        stop("stopped")
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        // Existing readers finish after their process pipes are closed.
        commands.shutdown()
        worker.shutdown()
    }
}
