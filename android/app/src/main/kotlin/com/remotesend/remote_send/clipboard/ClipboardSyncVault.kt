package com.remotesend.remote_send.clipboard

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** App-UID keystore encryption; excluded from regular config export and Android backup. */
internal object ClipboardSyncVault {
    private const val ALIAS = "remotesend.clipboard.sync.v1"
    private fun file(context: Context) = AtomicFile(File(context.noBackupFilesDir, "clipboard-sync.vault"))
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized fun load(context: Context): String? {
        val file = file(context)
        if (!file.baseFile.exists()) return null
        require(file.baseFile.length() <= 300000)
        val data = file.readFully()
        require(data.size >= 29 && data[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(1, 13)))
        return String(cipher.doFinal(data.copyOfRange(13, data.size)), Charsets.UTF_8)
    }
    @Synchronized fun save(context: Context, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        require(bytes.size <= 262144 && JSONObject(value).getInt("version") in 1..2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val data = byteArrayOf(1) + cipher.iv + cipher.doFinal(bytes)
        val file = file(context); val output = file.startWrite()
        try { output.write(data); file.finishWrite(output) }
        catch (error: Exception) { file.failWrite(output); throw error }
    }
    @Synchronized fun disable(context: Context) {
        load(context)?.let { save(context, JSONObject(it).put("enabled", false).toString()) }
    }
}
