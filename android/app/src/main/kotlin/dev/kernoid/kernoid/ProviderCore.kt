// SPDX-License-Identifier: MIT
package dev.kernoid.kernoid

import android.content.Context
import java.io.IOException
import org.json.JSONObject

/**
 * An answer of the core that is an error; [unauthorized] when the login has ended. [kept] is a renewed login that
 * came with it: the one before is used up, so it is kept all the same.
 */
class CoreException(message: String, val unauthorized: Boolean, val kept: String?) : IOException(message)

/**
 * The Rust core of the file shells (`rust/src/provider.rs`) in the app's own library, `libkernoid_bridge.so`: a JSON
 * request in, a JSON answer out (`{"ok": …}` or `{"error": {"message", "unauthorized"}}`), through JNI
 * (`rust/src/provider/jni.rs`).
 */
object ProviderCore {
    @Volatile private var loaded = false

    /**
     * Loads the library and hands the JVM to rustls-platform-verifier, which checks kernoid's certificate against
     * Android's trust store. Once per process, before the first connection – the provider's and the app's.
     */
    fun ready(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            System.loadLibrary("kernoid_bridge")
            init(context.applicationContext)
            loaded = true
        }
    }

    @JvmStatic private external fun init(context: Context)

    @JvmStatic private external fun call(request: String): String

    /** Asks the core [op] with [request]; the answer's `ok` – a renewed login in it as `kept` – or a [CoreException]. */
    fun ask(op: String, request: JSONObject = JSONObject()): JSONObject {
        check(loaded) { "ProviderCore.ready was not called" }
        val answer = JSONObject(call(JSONObject(request.toString()).put("op", op).toString()))
        answer.optJSONObject("error")?.let { error ->
            throw CoreException(error.optString("message"), error.optBoolean("unauthorized"), error.text("kept"))
        }
        return answer.getJSONObject("ok")
    }
}

/** A string, or null for one missing or `null` – org.json's `optString` gives `"null"` for the latter. */
fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key)
