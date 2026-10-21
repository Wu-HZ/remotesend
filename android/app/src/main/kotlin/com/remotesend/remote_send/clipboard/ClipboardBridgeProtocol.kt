package com.remotesend.remote_send.clipboard

import java.io.Reader
import java.io.IOException
import java.nio.charset.StandardCharsets

/** No clipboard text is ever interpolated into this command. */
internal object ClipboardBridgeProtocol {
    const val VERSION = 1
    const val MAX_TEXT_BYTES = 32 * 1024
    const val MAX_LINE_CHARS = 256 * 1024
    const val SHELL_UID = 2000
    const val PACKAGE = "com.android.shell"

    fun launchArguments(apk: String, appUid: Int): List<String> {
        require(apk.startsWith("/") && !apk.contains('\n') && !apk.contains('\u0000'))
        require(appUid >= 10000)
        val quoted = "'" + apk.replace("'", "'\\''") + "'"
        val command = "CLASSPATH=$quoted exec /system/bin/app_process /system/bin " +
            "--nice-name=remotesend-clipboard " +
            "com.remotesend.remote_send.clipboard.RootClipboardDaemon ${appUid / 100000}"
        // Root managers authorize the app, then launch the helper as shell, not root.
        return listOf("su", SHELL_UID.toString(), "-c", command)
    }

    fun readLine(reader: Reader): String? {
        val line = StringBuilder()
        while (true) {
            val value = reader.read()
            if (value == -1) {
                if (line.isEmpty()) return null
                throw IOException("Incomplete bridge frame")
            }
            if (value == '\n'.code) return line.toString()
            if (line.length >= MAX_LINE_CHARS) throw IOException("Bridge frame too large")
            line.append(value.toChar())
        }
    }

    fun textBytes(text: String): Int = text.toByteArray(StandardCharsets.UTF_8).size

    fun textKind(text: String?): String = when {
        text == null -> "non_text"
        text.isEmpty() -> "empty"
        textBytes(text) > MAX_TEXT_BYTES -> "too_large"
        else -> "text"
    }

    fun mayRead(sensitive: Boolean, plainText: Boolean): Boolean = !sensitive && plainText
}

/** Only known AOSP suffixes are accepted; unknown OEM APIs fail closed. */
internal enum class ClipboardApiShape(val types: List<String>) {
    PACKAGE_ONLY(listOf("java.lang.String")),
    USER(listOf("java.lang.String", "int")),
    ATTRIBUTION_USER(listOf("java.lang.String", "java.lang.String", "int")),
    ATTRIBUTION_USER_DEVICE(listOf("java.lang.String", "java.lang.String", "int", "int"));

    fun arguments(userId: Int): List<Any?> {
        require(userId >= 0)
        if (this == PACKAGE_ONLY) require(userId == 0)
        return when (this) {
            PACKAGE_ONLY -> listOf(ClipboardBridgeProtocol.PACKAGE)
            USER -> listOf(ClipboardBridgeProtocol.PACKAGE, userId)
            ATTRIBUTION_USER -> listOf(ClipboardBridgeProtocol.PACKAGE, null, userId)
            ATTRIBUTION_USER_DEVICE -> listOf(ClipboardBridgeProtocol.PACKAGE, null, userId, 0)
        }
    }

    companion object {
        fun find(types: List<String>): ClipboardApiShape? = entries.firstOrNull { it.types == types }
    }
}
