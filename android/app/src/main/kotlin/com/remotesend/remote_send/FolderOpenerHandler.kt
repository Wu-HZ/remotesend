package com.remotesend.remote_send

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/** Selects an installed ACTION_VIEW handler for the same content URI used by
 * the existing Android open-with flow. An explicit component skips the OS
 * resolver even on devices where its "Always" button is broken.
 */
internal class FolderOpenerHandler(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "remote_send/folder_opener")

    init {
        channel.setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (path.isNullOrBlank() || !File(path).isAbsolute) {
                result.error("invalid_path", "Invalid folder path", null)
                return@setMethodCallHandler
            }
            val uri = try {
                FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.fileprovider",
                    File(path),
                )
            } catch (_: IllegalArgumentException) {
                result.error("invalid_path", "Folder cannot be shared", null)
                return@setMethodCallHandler
            }
            // Android resolves content:// VIEW intents using the provider MIME
            // type. Query with that same type, or MT Manager's */* handler may
            // disappear from the list even though it appears in the OS chooser.
            val mimeType = activity.contentResolver.getType(uri) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeType)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            when (call.method) {
                "available" -> {
                    val packageManager = activity.packageManager
                    val choices = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                        .filter { it.activityInfo.packageName != activity.packageName && it.activityInfo.exported }
                        .distinctBy { it.activityInfo.packageName }
                        .sortedBy { it.loadLabel(packageManager).toString().lowercase() }
                        .map { handler ->
                            mapOf(
                                "component" to ComponentName(
                                    handler.activityInfo.packageName,
                                    handler.activityInfo.name,
                                ).flattenToString(),
                                "label" to (handler.loadLabel(packageManager).toString()
                                    .takeIf { it.isNotBlank() } ?: handler.activityInfo.packageName),
                                "icon" to applicationIconPng(handler.activityInfo.packageName),
                            )
                        }
                    result.success(choices)
                }
                "open" -> {
                    val component = ComponentName.unflattenFromString(
                        call.argument<String>("component").orEmpty(),
                    )
                    if (component == null || component.packageName == activity.packageName) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    intent.component = component
                    try {
                        activity.startActivity(intent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Encode a small copy of the real application icon. AdaptiveIconDrawable
    // cannot be sent through a MethodChannel, but PNG bytes can. A broken or
    // missing icon should not hide an otherwise usable application.
    private fun applicationIconPng(packageName: String): ByteArray? {
        val drawable = try {
            activity.packageManager.getApplicationIcon(packageName).mutate()
        } catch (_: Exception) {
            return null
        }
        val size = (48 * activity.resources.displayMetrics.density).toInt().coerceIn(48, 96)
        var bitmap: Bitmap? = null
        return try {
            bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(Canvas(bitmap))
            ByteArrayOutputStream().use { output ->
                if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                    output.toByteArray()
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        } finally {
            bitmap?.recycle()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
