package com.remotesend.remote_send.clipboard

import android.app.KeyguardManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

internal object ClipboardSyncStatusBus {
    var status: Map<String, Any> = mapOf("phase" to "stopped", "sent" to 0, "received" to 0, "peers" to 0)
        private set
    val sinks = mutableSetOf<EventChannel.EventSink>()
    fun publish(value: Map<String, Any>) {
        status = value
        sinks.toList().forEach { it.success(value) }
    }
}

internal class ClipboardSyncChannel(context: Context, messenger: BinaryMessenger, private val background: Boolean = false) {
    private val app = context.applicationContext
    private val methods = MethodChannel(messenger, "remote_send/clipboard_sync")
    private val events = EventChannel(messenger, "remote_send/clipboard_sync_events")
    private var sink: EventChannel.EventSink? = null
    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events; ClipboardSyncStatusBus.sinks.add(events); events.success(ClipboardSyncStatusBus.status)
            }
            override fun onCancel(arguments: Any?) { sink?.let { ClipboardSyncStatusBus.sinks.remove(it) }; sink = null }
        })
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "load" -> result.success(ClipboardSyncVault.load(app))
                    "save" -> { ClipboardSyncVault.save(app, call.argument<String>("value")!!); result.success(null) }
                    "start" -> { check(!background); ClipboardSyncService.start(app); result.success(null) }
                    "stop" -> { ClipboardSyncService.stop(app); result.success(null) }
                    "abort" -> {
                        check(background)
                        try { ClipboardSyncVault.disable(app) } finally {
                            app.stopService(android.content.Intent(app, ClipboardSyncService::class.java))
                        }
                        result.success(null)
                    }
                    "status" -> result.success(ClipboardSyncStatusBus.status)
                    "lockEpoch" -> result.success(ClipboardSyncService.lockEpoch)
                    "locked" -> result.success((app.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceLocked)
                    "report" -> {
                        check(background)
                        val phase = call.argument<String>("phase")!!
                        require(phase in setOf("connecting", "running", "waiting", "paused", "reconnecting", "error", "stopped"))
                        val value = mutableMapOf<String, Any>("phase" to phase)
                        for (name in listOf("sent", "received", "peers")) value[name] = (call.argument<Number>(name)?.toInt() ?: 0).coerceAtLeast(0)
                        call.argument<String>("error")?.let { value["error"] = if (it in setOf("clipboard_unavailable", "clipboard_read", "clipboard_write", "connection_lost", "startup_failed")) it else "sync_failed" }
                        ClipboardSyncStatusBus.publish(value)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("platform_failed", "Encrypted settings or background service operation failed", null) }
        }
    }
    fun dispose() {
        sink?.let { ClipboardSyncStatusBus.sinks.remove(it) }; sink = null
        events.setStreamHandler(null); methods.setMethodCallHandler(null)
    }
}
