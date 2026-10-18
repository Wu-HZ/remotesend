package com.remotesend.remote_send

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var openedFiles: OpenedFileHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        openedFiles = OpenedFileHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        openedFiles?.receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openedFiles?.receive(intent)
    }

    override fun onDestroy() {
        openedFiles?.dispose()
        openedFiles = null
        super.onDestroy()
    }
}
