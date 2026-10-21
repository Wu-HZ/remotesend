package com.remotesend.remote_send.clipboard

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import java.io.BufferedWriter
import java.io.OutputStreamWriter
import java.lang.reflect.InvocationTargetException
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.system.exitProcess
import org.json.JSONObject

/** APK entry point for app_process. Private stdin/stdout pipes are the only IPC. */
object RootClipboardDaemon {
    @JvmStatic
    fun main(args: Array<String>) {
        val output = BufferedWriter(OutputStreamWriter(System.out, StandardCharsets.UTF_8))
        fun send(value: JSONObject) {
            synchronized(output) { output.write(value.toString()); output.newLine(); output.flush() }
        }
        // Never log exception messages or stack traces: they may contain clipboard text.
        Thread.setDefaultUncaughtExceptionHandler { _, _ -> exitProcess(1) }
        var access: SystemClipboardAccess? = null
        try {
            if (Process.myUid() != ClipboardBridgeProtocol.SHELL_UID) {
                send(JSONObject().put("event", "error").put("code", "wrong_identity"))
                exitProcess(1)
            }
            val userId = args.single().toInt().also { require(it >= 0) }
            @Suppress("DEPRECATION")
            Looper.prepareMainLooper()
            val handler = Handler(Looper.myLooper()!!)
            // Watch stdin BEFORE calling system Binder: even a hung registration/read must
            // not leave a privileged helper behind when its owner cancels or dies.
            Thread({
                try {
                    val input = System.`in`.bufferedReader(StandardCharsets.UTF_8)
                    while (true) {
                        val line = ClipboardBridgeProtocol.readLine(input) ?: break
                        val command = JSONObject(line)
                        handler.post {
                            val id = command.optLong("id", -1)
                            try {
                                val clipboard = access ?: error("not_ready")
                                val snapshot = when (command.getString("op")) {
                                    "read" -> clipboard.snapshot(includeText = true)
                                    "write" -> clipboard.writeText(command.getString("text"))
                                    else -> throw IllegalArgumentException("invalid_command")
                                }
                                send(JSONObject().put("id", id).put("snapshot", snapshot))
                            } catch (error: Exception) {
                                send(JSONObject().put("id", id).put("error", errorCode(error)))
                            }
                        }
                    }
                } catch (_: Exception) {
                    // Invalid input is fatal; never echo its text or a parser exception.
                } finally {
                    Thread({
                        try { Thread.sleep(1_000) } catch (_: InterruptedException) { }
                        // Binder may be stuck on the main thread. Process death unregisters
                        // callbacks even if graceful cleanup cannot finish.
                        exitProcess(0)
                    }, "clipboard-exit-watchdog").apply { isDaemon = true; start() }
                    handler.post { access?.close(); exitProcess(0) }
                }
            }, "clipboard-commands").apply { isDaemon = true; start() }
            val scheduled = AtomicBoolean(false)
            val clipboard = SystemClipboardAccess(userId) {
                if (scheduled.compareAndSet(false, true)) {
                    handler.postDelayed({
                        scheduled.set(false)
                        try {
                            send(JSONObject().put("event", "clipboard")
                                .put("snapshot", access!!.snapshot(includeText = false)))
                        } catch (error: Exception) {
                            send(JSONObject().put("event", "error").put("code", errorCode(error)))
                        }
                    }, 100)
                }
            }
            access = clipboard
            clipboard.register()
            send(JSONObject().put("event", "ready")
                .put("version", ClipboardBridgeProtocol.VERSION)
                .put("uid", Process.myUid()).put("sdk", Build.VERSION.SDK_INT)
                .put("userId", userId).put("api", clipboard.api))
            Looper.loop()
        } catch (error: Exception) {
            try { send(JSONObject().put("event", "error").put("code", errorCode(error))) }
            catch (_: Exception) { /* client is gone */ }
        } finally {
            access?.close()
        }
        exitProcess(1)
    }

    private fun errorCode(error: Throwable): String {
        val cause = if (error is InvocationTargetException) error.targetException else error
        return when (cause) {
            is SecurityException -> "permission_denied"
            is UnsupportedOperationException, is ReflectiveOperationException -> "unsupported_api"
            is IllegalArgumentException -> "invalid_request"
            else -> "bridge_failed"
        }
    }
}
