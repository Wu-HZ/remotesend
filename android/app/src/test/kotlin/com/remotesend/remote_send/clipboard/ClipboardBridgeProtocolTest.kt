package com.remotesend.remote_send.clipboard

import java.io.IOException
import java.io.StringReader
import org.junit.Assert.*
import org.junit.Test

class ClipboardBridgeProtocolTest {
    @Test fun launchUsesShellIdentityAndQuotesOnlyApkPath() {
        val args = ClipboardBridgeProtocol.launchArguments("/data/app/a'b/base.apk", 1010123)
        assertEquals(listOf("su", "2000", "-c"), args.take(3))
        assertTrue(args.last().contains("CLASSPATH='/data/app/a'\\''b/base.apk' exec"))
        assertTrue(args.last().endsWith("RootClipboardDaemon 10"))
        assertFalse(args.last().contains("setenforce"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun launchRejectsInjectedNewline() {
        ClipboardBridgeProtocol.launchArguments("/data/app/a\nwhoami", 10123)
    }

    @Test fun framesPreserveWhitespaceAndAreSeparatedByNewlineOnly() {
        val input = StringReader("  frame  \nnext\n")
        assertEquals("  frame  ", ClipboardBridgeProtocol.readLine(input))
        assertEquals("next", ClipboardBridgeProtocol.readLine(input))
        assertNull(ClipboardBridgeProtocol.readLine(input))
    }

    @Test(expected = IOException::class)
    fun partialFrameIsNotAccepted() {
        ClipboardBridgeProtocol.readLine(StringReader("partial"))
    }

    @Test(expected = IOException::class)
    fun oversizedFrameIsRejected() {
        ClipboardBridgeProtocol.readLine(StringReader("x".repeat(ClipboardBridgeProtocol.MAX_LINE_CHARS + 1) + "\n"))
    }

    @Test fun textLimitsUseUtf8BytesAndDoNotTrim() {
        assertEquals("non_text", ClipboardBridgeProtocol.textKind(null))
        assertEquals("empty", ClipboardBridgeProtocol.textKind(""))
        assertEquals("text", ClipboardBridgeProtocol.textKind("  \n  "))
        assertEquals(6, ClipboardBridgeProtocol.textBytes("你好"))
        assertEquals("text", ClipboardBridgeProtocol.textKind("x".repeat(32768)))
        assertEquals("too_large", ClipboardBridgeProtocol.textKind("x".repeat(32769)))
        assertEquals("too_large", ClipboardBridgeProtocol.textKind("你".repeat(11000)))
    }

    @Test fun sensitiveAndNonTextClipsAreNotRead() {
        assertFalse(ClipboardBridgeProtocol.mayRead(true, true))
        assertFalse(ClipboardBridgeProtocol.mayRead(false, false))
        assertFalse(ClipboardBridgeProtocol.mayRead(true, false))
        assertTrue(ClipboardBridgeProtocol.mayRead(false, true))
    }

    @Test fun knownApiShapesHaveExplicitUserAndDefaultDevice() {
        assertEquals(listOf("com.android.shell"), ClipboardApiShape.PACKAGE_ONLY.arguments(0))
        assertEquals(listOf("com.android.shell", 10), ClipboardApiShape.USER.arguments(10))
        assertEquals(listOf("com.android.shell", null, 10), ClipboardApiShape.ATTRIBUTION_USER.arguments(10))
        assertEquals(listOf("com.android.shell", null, 10, 0), ClipboardApiShape.ATTRIBUTION_USER_DEVICE.arguments(10))
        for (shape in ClipboardApiShape.entries) assertEquals(shape, ClipboardApiShape.find(shape.types))
        assertNull(ClipboardApiShape.find(listOf("java.lang.String", "long")))
        assertNull(ClipboardApiShape.find(listOf("android.content.AttributionSource")))
    }

    @Test(expected = IllegalArgumentException::class)
    fun legacyApiNeverSilentlyReadsAnotherUsersClipboard() {
        ClipboardApiShape.PACKAGE_ONLY.arguments(10)
    }

    @Test fun diagnosticAndSyncServicesCannotOwnTwoRootHelpersAtOnce() {
        assertTrue(ClipboardBridgeOwnership.acquire("diagnostics"))
        assertFalse(ClipboardBridgeOwnership.acquire("sync"))
        ClipboardBridgeOwnership.release("diagnostics")
        assertTrue(ClipboardBridgeOwnership.acquire("sync"))
        assertFalse(ClipboardBridgeOwnership.acquire("diagnostics"))
        ClipboardBridgeOwnership.release("sync")
        assertTrue(ClipboardBridgeOwnership.acquire("diagnostics"))
        ClipboardBridgeOwnership.release("diagnostics")
    }
}
