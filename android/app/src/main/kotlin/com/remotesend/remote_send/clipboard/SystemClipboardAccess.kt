package com.remotesend.remote_send.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.os.Binder
import android.os.IBinder
import android.os.IInterface
import android.os.Parcel
import android.os.PersistableBundle
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.UUID
import org.json.JSONObject

/** Runs only inside the explicitly authorized shell helper, never the app process. */
internal class SystemClipboardAccess(private val userId: Int, onChanged: () -> Unit) {
    private val clipboard: Any
    private val listener: Any
    private val read: Call
    private val description: Call
    private val write: Call
    private val add: Call
    private val remove: Call
    private var registered = false
    private var lastWrite: String? = null
    val api: String get() = read.shape.name

    init {
        val manager = Class.forName("android.os.ServiceManager")
        val binder = manager.getMethod("getService", String::class.java)
            .invoke(null, "clipboard") as? IBinder ?: error("clipboard_unavailable")
        val stub = Class.forName("android.content.IClipboard\$Stub")
        clipboard = stub.getMethod("asInterface", IBinder::class.java).invoke(null, binder)
            ?: error("clipboard_unavailable")
        val apiClass = Class.forName("android.content.IClipboard")
        val listenerClass = Class.forName("android.content.IOnPrimaryClipChangedListener")
        read = resolve(apiClass, "getPrimaryClip")
        description = resolve(apiClass, "getPrimaryClipDescription")
        write = resolve(apiClass, "setPrimaryClip", ClipData::class.java.name)
        add = resolve(apiClass, "addPrimaryClipChangedListener", listenerClass.name)
        remove = resolve(apiClass, "removePrimaryClipChangedListener", listenerClass.name)
        val callback = object : Binder() {
            override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
                if (code == IBinder.INTERFACE_TRANSACTION) {
                    reply?.writeString(LISTENER_DESCRIPTOR)
                    return true
                }
                if (code == IBinder.FIRST_CALL_TRANSACTION) {
                    data.enforceInterface(LISTENER_DESCRIPTOR)
                    onChanged()
                    return true
                }
                return super.onTransact(code, data, reply, flags)
            }
        }
        listener = Proxy.newProxyInstance(listenerClass.classLoader, arrayOf(listenerClass)) { proxy, method, args ->
            when (method.name) {
                "asBinder" -> callback
                "equals" -> proxy === args?.get(0)
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "RemoteSendClipboardListener"
                else -> null
            }
        }
        callback.attachInterface(listener as IInterface, LISTENER_DESCRIPTOR)
    }

    private data class Call(val method: Method, val shape: ClipboardApiShape)

    private fun resolve(apiClass: Class<*>, name: String, prefix: String? = null): Call {
        val calls = apiClass.methods.filter { it.name == name }.mapNotNull { method ->
            val types = method.parameterTypes.map { it.name }
            if (prefix != null && types.firstOrNull() != prefix) return@mapNotNull null
            val shape = ClipboardApiShape.find(if (prefix == null) types else types.drop(1))
                ?: return@mapNotNull null
            // Validate multi-user support before registering any listener.
            shape.arguments(userId)
            Call(method, shape)
        }
        return calls.singleOrNull() ?: throw UnsupportedOperationException("unsupported_clipboard_api")
    }

    private fun invoke(call: Call, vararg prefix: Any): Any? =
        call.method.invoke(clipboard, *(prefix.toList() + call.shape.arguments(userId)).toTypedArray())

    fun register() {
        invoke(add, listener)
        registered = true
    }

    fun close() {
        if (registered) {
            registered = false
            try { invoke(remove, listener) } catch (_: Exception) { /* process exit also drops binder */ }
        }
        lastWrite = null
    }

    fun snapshot(includeText: Boolean): JSONObject {
        val desc = invoke(description) as? ClipDescription ?: return meta("unavailable")
        val sensitive = desc.extras?.getBoolean(SENSITIVE, false) == true
        val plain = desc.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)
        if (!ClipboardBridgeProtocol.mayRead(sensitive, plain)) {
            return meta(if (sensitive) "sensitive" else "non_text")
        }
        val clip = invoke(read) as? ClipData ?: return meta("unavailable")
        // Recheck the actual clip: it may have changed after reading its description.
        if (clip.description.extras?.getBoolean(SENSITIVE, false) == true) return meta("sensitive")
        if (clip.itemCount != 1 || !clip.description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)) {
            return meta("non_text")
        }
        // Never coerce URI, Intent or HTML content into text (may read external files).
        val text = clip.getItemAt(0).text?.toString()
        val kind = ClipboardBridgeProtocol.textKind(text)
        val internal = lastWrite != null && clip.description.extras?.getString(ORIGIN) == lastWrite
        return meta(kind).apply {
            put("internal", internal)
            if (text != null) put("bytes", ClipboardBridgeProtocol.textBytes(text))
            if (includeText && kind == "text") put("text", text)
        }
    }

    fun writeText(text: String): JSONObject {
        require(ClipboardBridgeProtocol.textKind(text) == "text")
        val token = UUID.randomUUID().toString()
        val clip = ClipData.newPlainText("RemoteSend clipboard test", text)
        clip.description.extras = PersistableBundle().apply { putString(ORIGIN, token) }
        // Set before writing: notifications can arrive before the Binder call returns.
        val previous = lastWrite
        lastWrite = token
        try { invoke(write, clip) } catch (error: Exception) { lastWrite = previous; throw error }
        return snapshot(includeText = true)
    }

    private fun meta(kind: String) = JSONObject().put("kind", kind).put("internal", false)

    companion object {
        private const val LISTENER_DESCRIPTOR = "android.content.IOnPrimaryClipChangedListener"
        private const val SENSITIVE = "android.content.extra.IS_SENSITIVE"
        private const val ORIGIN = "com.remotesend.remote_send.clipboard.origin"
    }
}
