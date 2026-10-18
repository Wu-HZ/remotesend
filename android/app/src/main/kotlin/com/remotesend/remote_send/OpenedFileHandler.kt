package com.remotesend.remote_send

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileNotFoundException
import java.util.ArrayDeque
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

/** ACTION_VIEW is deliberately separate from share_handler's SEND intents. */
internal class OpenedFileHandler(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val channel = EventChannel(messenger, "remote_send/opened_files")
    private val pending = ArrayDeque<Map<String, String>>()
    private var sink: EventChannel.EventSink? = null
    private var disposed = false

    init {
        channel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
                flush()
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    fun receive(intent: Intent) {
        val uri = intent.data ?: intent.clipData?.let {
            if (it.itemCount > 0) it.getItemAt(0).uri else null
        } ?: return
        if (!OpenedFileImporter.accepts(intent.action, uri.scheme?.lowercase(Locale.ROOT))) return
        val id = UUID.randomUUID().toString()
        worker.execute {
            val event = try {
                // Activity grants already apply to this app's UID. Copy now so
                // pending uploads do not depend on keeping the source URI grant.
                val staged = OpenedFileImporter.copy(
                    File(app.cacheDir, "opened_files"), displayName(uri)
                ) {
                    app.contentResolver.openInputStream(uri)
                        ?: throw FileNotFoundException("No readable stream for opened file")
                }
                mapOf("id" to id, "path" to staged.absolutePath)
            } catch (_: SecurityException) {
                mapOf("id" to id, "error" to "permission_denied")
            } catch (_: FileNotFoundException) {
                mapOf("id" to id, "error" to "unavailable")
            } catch (_: Exception) {
                mapOf("id" to id, "error" to "failed")
            }
            main.post {
                if (!disposed) {
                    pending.addLast(event)
                    flush()
                }
            }
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            try {
                app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { cursor ->
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0 && cursor.moveToFirst() && !cursor.isNull(index)) {
                            return cursor.getString(index)
                        }
                    }
            } catch (error: SecurityException) {
                throw error
            } catch (_: Exception) {
                // Some providers support streams but not metadata queries.
            }
        }
        return uri.lastPathSegment
    }

    private fun flush() {
        val events = sink ?: return
        while (pending.isNotEmpty()) events.success(pending.removeFirst())
    }

    fun dispose() {
        disposed = true
        sink = null
        channel.setStreamHandler(null)
        worker.shutdown()
    }
}
