package com.remotesend.remote_send.clipboard

/** Only one app-process client may own the system listener and root child. */
internal object ClipboardBridgeOwnership {
    private var owner: String? = null
    @Synchronized fun acquire(value: String): Boolean {
        if (owner != null && owner != value) return false
        owner = value
        return true
    }
    @Synchronized fun release(value: String) { if (owner == value) owner = null }
}
