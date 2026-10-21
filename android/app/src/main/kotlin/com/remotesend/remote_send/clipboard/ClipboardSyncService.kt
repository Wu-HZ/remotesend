package com.remotesend.remote_send.clipboard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.content.Intent
import android.os.Build
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.pathprovider.PathProviderPlugin
import org.json.JSONObject

/** Owns a headless isolate and root pipes independently of Activity/navigation lifetime. */
class ClipboardSyncService : Service() {
    private var engine: FlutterEngine? = null
    private var root: RootClipboardHandler? = null
    private var channel: ClipboardSyncChannel? = null
    private val lockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { lockEpoch++ }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        running = true
        val filter = IntentFilter().apply { addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_USER_PRESENT) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(lockReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(lockReceiver, filter)
        ClipboardSyncStatusBus.publish(mapOf("phase" to "connecting"))
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            CHANNEL, "Clipboard synchronization", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0, Intent(this, ClipboardSyncService::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let { PendingIntent.getActivity(this, 1, it,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val notification = builder.setSmallIcon(android.R.drawable.stat_notify_sync).setContentTitle("RemoteSend")
            .setContentText("Clipboard sync · 剪贴板同步").setOngoing(true).setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop / 停止", stop).build()).build()
        startForeground(4107, notification)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { stop(this); return START_NOT_STICKY }
        if (engine != null) return START_STICKY
        try {
            val config = ClipboardSyncVault.load(this)?.let(::JSONObject)
            check(config?.optBoolean("enabled") == true)
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this); loader.ensureInitializationComplete(this, null)
            // Register only path_provider plus the two explicit channels: the
            // background isolate needs app-private storage for the local history.
            // UI/share/camera plugins are intentionally not attached headlessly.
            val next = FlutterEngine(this, null, false)
            next.plugins.add(PathProviderPlugin())
            engine = next
            root = RootClipboardHandler(this, next.dartExecutor.binaryMessenger, syncOwner = true)
            channel = ClipboardSyncChannel(this, next.dartExecutor.binaryMessenger, background = true)
            next.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "clipboardSyncBackgroundMain"))
        } catch (_: Exception) {
            try { ClipboardSyncVault.disable(this) } catch (_: Exception) { }
            ClipboardSyncStatusBus.publish(mapOf("phase" to "error", "error" to "startup_failed"))
            stopSelf()
        }
        return START_STICKY
    }
    override fun onDestroy() {
        running = false
        try { unregisterReceiver(lockReceiver) } catch (_: Exception) { }
        // Cancel root requests before killing Dart; no late platform write survives its owner.
        root?.dispose(); root = null
        channel?.dispose(); channel = null
        engine?.destroy(); engine = null
        if (ClipboardSyncStatusBus.status["phase"] != "error") ClipboardSyncStatusBus.publish(mapOf("phase" to "stopped"))
        super.onDestroy()
    }
    companion object {
        private const val CHANNEL = "remotesend_clipboard_sync"
        private const val STOP = "remotesend.clipboard.STOP"
        @Volatile var lockEpoch = 0L
            private set
        @Volatile var running = false
            private set
        fun start(context: Context) {
            if (running) {
                check(ClipboardSyncStatusBus.status["phase"] != "error") { "Service is shutting down" }
                return
            }
            try {
                val intent = Intent(context, ClipboardSyncService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (error: Exception) { ClipboardSyncVault.disable(context); throw error }
        }
        fun stop(context: Context) {
            var failed = false
            try { ClipboardSyncVault.disable(context) } catch (_: Exception) { failed = true }
            context.stopService(Intent(context, ClipboardSyncService::class.java))
            ClipboardSyncStatusBus.publish(if (failed) mapOf("phase" to "error", "error" to "sync_failed") else mapOf("phase" to "stopped"))
        }
    }
}
