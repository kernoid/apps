// SPDX-License-Identifier: MIT
package dev.kernoid.kernoid

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.io.FileNotFoundException
import org.json.JSONObject

/**
 * The provider's one session with the core, shared by every thread of the process: opened with the kept login on the
 * first request, closed after a minute without one. While it is open the core renews the login in the background;
 * each renewal comes back with the next answer and is kept at once ([ProviderLogin]). Closing asks once more first,
 * so that no renewal is lost with the session – Android may end an idle process at any time, and a login whose
 * renewal was never kept has ended at the server.
 */
object ProviderSession {
    private const val TAG = "kernoid-documents"
    private const val IDLE_MS = 60_000L

    private val lock = Object()
    private var session: Long? = null
    private var busy = 0
    private lateinit var context: Context

    /** A thread of the provider's own: closing idle sessions, uploading what was written on close. */
    val worker: Handler by lazy { Handler(HandlerThread(TAG).apply { start() }.looper) }

    private val closeIdle = Runnable { close(context) }

    /** Whether a login is kept for the provider. */
    fun signedIn(context: Context) = ProviderLogin.load(context) != null

    /**
     * Asks the core [op] with [request] in the session, opening it when needed. When the core says the login ended,
     * the session is opened once more with the kept login; if that fails too, the login is forgotten and the roots go.
     */
    fun ask(context: Context, op: String, request: JSONObject = JSONObject()): JSONObject {
        this.context = context.applicationContext
        ProviderCore.ready(context)
        for (attempt in 0..1) {
            val id =
                try {
                    open(context)
                } catch (error: CoreException) {
                    error.kept?.let { ProviderLogin.save(context, it) }
                    if (error.unauthorized) end(context)
                    throw error
                }
            try {
                return keep(context, ProviderCore.ask(op, JSONObject(request.toString()).put("session", id)))
            } catch (error: CoreException) {
                error.kept?.let { ProviderLogin.save(context, it) }
                if (!error.unauthorized) throw error
                drop(id)
                if (attempt == 1) {
                    end(context)
                    throw error
                }
            } finally {
                release()
            }
        }
        throw IllegalStateException("unreachable")
    }

    /**
     * Closes the session, keeping a renewal it may have had. The app calls it before it gives the provider another
     * login or takes it away.
     */
    fun close(context: Context) {
        synchronized(lock) {
            if (busy > 0) return schedule()
            val id = session ?: return
            try {
                keep(context, ProviderCore.ask("stores", JSONObject().put("session", id)))
            } catch (error: CoreException) {
                error.kept?.let { ProviderLogin.save(context, it) }
                Log.w(TAG, "a last renewal could not be asked for: ${error.message}")
            }
            try {
                ProviderCore.ask("close", JSONObject().put("session", id))
            } catch (_: CoreException) {}
            session = null
            worker.removeCallbacks(closeIdle)
        }
    }

    /** The open session, or a new one with the kept login; counted as busy until [release]. */
    private fun open(context: Context): Long =
        synchronized(lock) {
            val id =
                session
                    ?: run {
                        val kept =
                            ProviderLogin.load(context) ?: throw FileNotFoundException("not signed in to kernoid")
                        val opened = keep(context, ProviderCore.ask("open", JSONObject().put("kept", kept)))
                        opened.getLong("session").also { session = it }
                    }
            busy++
            worker.removeCallbacks(closeIdle)
            id
        }

    private fun release() {
        synchronized(lock) {
            busy--
            if (busy == 0) schedule()
        }
    }

    private fun schedule() {
        worker.removeCallbacks(closeIdle)
        worker.postDelayed(closeIdle, IDLE_MS)
    }

    private fun drop(id: Long) {
        synchronized(lock) {
            if (session == id) session = null
        }
        try {
            ProviderCore.ask("close", JSONObject().put("session", id))
        } catch (_: CoreException) {}
    }

    /** The login ended at the server: forgotten, and the roots go from the Files app. */
    private fun end(context: Context) {
        Log.w(TAG, "the provider's login ended")
        ProviderLogin.clear(context)
        KernoidDocumentsProvider.rootsChanged(context)
    }

    private fun keep(context: Context, answer: JSONObject): JSONObject {
        answer.text("kept")?.let { ProviderLogin.save(context, it) }
        return answer
    }
}
