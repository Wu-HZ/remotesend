package com.remotesend.remote_send

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID

/** Copies a granted URI stream into private staging before its grant expires. */
internal object OpenedFileImporter {
    fun accepts(action: String?, scheme: String?): Boolean =
        action == "android.intent.action.VIEW" && scheme in setOf("content", "file")

    fun safeName(displayName: String?): String {
        val leaf = displayName.orEmpty().replace('\\', '/').substringAfterLast('/')
        val name = leaf.replace(Regex("[\\p{Cntrl}]"), "_").trim()
        return if (name.isEmpty() || name == "." || name == "..") "opened_file" else name
    }

    fun copy(root: File, displayName: String?, open: () -> InputStream): File {
        val directory = File(root, UUID.randomUUID().toString())
        if (!directory.mkdirs()) throw IOException("Cannot create import staging directory")
        val target = File(directory, safeName(displayName))
        try {
            open().use { input -> target.outputStream().use { output -> input.copyTo(output) } }
            return target
        } catch (error: Exception) {
            directory.deleteRecursively()
            throw error
        }
    }
}
