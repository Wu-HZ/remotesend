package com.remotesend.remote_send

import android.content.Intent
import com.remotesend.remote_send.clipboard.RootClipboardHandler
import com.remotesend.remote_send.clipboard.ClipboardSyncChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var openedFiles: OpenedFileHandler? = null
    private var rootClipboard: RootClipboardHandler? = null
    private var clipboardSync: ClipboardSyncChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        openedFiles = OpenedFileHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        openedFiles?.receive(intent)
        rootClipboard = RootClipboardHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        clipboardSync = ClipboardSyncChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openedFiles?.receive(intent)
    }

    override fun onDestroy() {
        clipboardSync?.dispose()
        clipboardSync = null
        rootClipboard?.dispose()
        rootClipboard = null
        openedFiles?.dispose()
        openedFiles = null
        super.onDestroy()
    }
}
