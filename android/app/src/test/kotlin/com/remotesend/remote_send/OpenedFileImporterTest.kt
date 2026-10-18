package com.remotesend.remote_send

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

class OpenedFileImporterTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun acceptsOnlyViewFilesNotSharesOrWebLinks() {
        assertTrue(OpenedFileImporter.accepts("android.intent.action.VIEW", "content"))
        assertTrue(OpenedFileImporter.accepts("android.intent.action.VIEW", "file"))
        for (scheme in listOf("http", "https", "ftp", "javascript", null)) {
            assertFalse(OpenedFileImporter.accepts("android.intent.action.VIEW", scheme))
        }
        assertFalse(OpenedFileImporter.accepts("android.intent.action.SEND", "content"))
        assertFalse(OpenedFileImporter.accepts(null, "content"))
    }

    @Test
    fun fileNamesCannotEscapeThePrivateStagingDirectory() {
        assertEquals("report.txt", OpenedFileImporter.safeName("../../report.txt"))
        assertEquals("report.txt", OpenedFileImporter.safeName("C:\\temp\\report.txt"))
        assertEquals("报告 1.pdf", OpenedFileImporter.safeName("报告 1.pdf"))
        assertEquals("_hello_.txt", OpenedFileImporter.safeName("\u0000hello\n.txt"))
        for (name in listOf(null, "", " ", ".", "..", "../")) {
            assertEquals("opened_file", OpenedFileImporter.safeName(name))
        }
    }

    @Test
    fun copiesBytesWithoutChangingTheSource() {
        val source = temporary.newFile("source.bin")
        val bytes = byteArrayOf(0, 1, 2, 127, -1, 42)
        source.writeBytes(bytes)
        val root = File(temporary.root, "imports")
        val staged = OpenedFileImporter.copy(root, "文件.bin") { source.inputStream() }
        assertEquals("文件.bin", staged.name)
        assertEquals(root.canonicalFile, staged.parentFile!!.parentFile!!.canonicalFile)
        assertArrayEquals(bytes, staged.readBytes())
        assertArrayEquals(bytes, source.readBytes())
    }

    @Test
    fun sameNameFilesGetIndependentCopies() {
        val root = File(temporary.root, "imports")
        val first = OpenedFileImporter.copy(root, "report.txt") { ByteArrayInputStream("one".toByteArray()) }
        val second = OpenedFileImporter.copy(root, "report.txt") { ByteArrayInputStream("two".toByteArray()) }
        assertNotEquals(first.path, second.path)
        assertEquals("one", first.readText())
        assertEquals("two", second.readText())
    }

    @Test
    fun emptyFilesAreValidImports() {
        val staged = OpenedFileImporter.copy(File(temporary.root, "imports"), "empty.txt") {
            ByteArrayInputStream(byteArrayOf())
        }
        assertTrue(staged.exists())
        assertEquals(0L, staged.length())
    }

    @Test
    fun failedReadClosesStreamAndRemovesOnlyThePartialImport() {
        val root = File(temporary.root, "imports")
        val previous = OpenedFileImporter.copy(root, "good.txt") { ByteArrayInputStream(byteArrayOf(1)) }
        var closed = false
        try {
            OpenedFileImporter.copy(root, "bad.txt") {
                object : InputStream() {
                    private var reads = 0
                    override fun read(): Int {
                        if (++reads > 3) throw IOException("Provider stopped reading")
                        return 42
                    }
                    override fun close() { closed = true }
                }
            }
            fail("Expected failed import")
        } catch (_: IOException) {
            assertTrue(closed)
            assertTrue(previous.exists())
            assertEquals(1, root.listFiles()!!.size)
        }
    }

    @Test
    fun expiredUriGrantDoesNotLeaveAPartialFile() {
        val root = File(temporary.root, "imports")
        try {
            OpenedFileImporter.copy(root, "denied.txt") { throw SecurityException("Grant expired") }
            fail("Expected missing permission")
        } catch (_: SecurityException) {
            assertEquals(0, root.listFiles()!!.size)
        }
    }
}
