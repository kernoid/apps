// SPDX-License-Identifier: MIT
package dev.kernoid.kernoid

import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

/**
 * kernoid's stores in Android's Files app and every document picker (Storage Access Framework, docs/plan.md, 5): one
 * root per store – own files, drives, what others shared. What it shows and does is asked of the Rust core
 * ([ProviderSession], [ProviderCore]) with a login of its own that the app hands over in its account page.
 *
 * Document ids are `<store>:<node>`; a store's top is `<store>:`. Content is fetched into the cache when opened and,
 * when written, uploaded as the file is closed. Items in vaults are listed but locked: no content, no changes (OPEN:
 * the account's key in the provider, plan section 6).
 */
class KernoidDocumentsProvider : DocumentsProvider() {
    companion object {
        const val AUTHORITY = "dev.kernoid.kernoid.documents"
        private const val TAG = "kernoid-documents"

        /** Tells the Files app that the roots changed – signed in, signed out. */
        fun rootsChanged(context: Context) {
            context.contentResolver.notifyChange(DocumentsContract.buildRootsUri(AUTHORITY), null)
        }

        private val ROOT_COLUMNS =
            arrayOf(
                Root.COLUMN_ROOT_ID,
                Root.COLUMN_DOCUMENT_ID,
                Root.COLUMN_TITLE,
                Root.COLUMN_SUMMARY,
                Root.COLUMN_FLAGS,
                Root.COLUMN_ICON,
            )
        private val DOCUMENT_COLUMNS =
            arrayOf(
                Document.COLUMN_DOCUMENT_ID,
                Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE,
                Document.COLUMN_SIZE,
                Document.COLUMN_LAST_MODIFIED,
                Document.COLUMN_FLAGS,
                Document.COLUMN_SUMMARY,
            )
    }

    /** The stores' names, by id – for their tops, which are no items of their own. */
    private val storeNames = ConcurrentHashMap<String, String>()

    override fun onCreate() = true

    private fun ask(op: String, request: JSONObject = JSONObject()): JSONObject =
        ProviderSession.ask(requireContext(), op, request)

    /** A document id taken apart: the store and the node, empty for the store's top. */
    private fun split(documentId: String): Pair<String, String> {
        val colon = documentId.indexOf(':')
        if (colon <= 0) throw FileNotFoundException("no such document: $documentId")
        return documentId.substring(0, colon) to documentId.substring(colon + 1)
    }

    /** A request about [store], with [node] as `key` – left out (the top) when empty. */
    private fun request(store: String, key: String? = null, node: String = ""): JSONObject =
        JSONObject().put("store", store).apply { if (key != null && node.isNotEmpty()) put(key, node) }

    /** The core's errors as Android expects them from a DocumentsProvider. */
    private inline fun <T> guard(block: () -> T): T =
        try {
            block()
        } catch (error: FileNotFoundException) {
            throw error
        } catch (error: IOException) {
            throw FileNotFoundException(error.message)
        }

    private fun notifyChildren(store: String, parent: String?) {
        requireContext()
            .contentResolver
            .notifyChange(DocumentsContract.buildChildDocumentsUri(AUTHORITY, "$store:${parent.orEmpty()}"), null)
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cursor = MatrixCursor(projection ?: ROOT_COLUMNS)
        val context = requireContext()
        cursor.setNotificationUri(context.contentResolver, DocumentsContract.buildRootsUri(AUTHORITY))
        if (!ProviderSession.signedIn(context)) return cursor
        val stores =
            try {
                ask("stores").getJSONArray("stores")
            } catch (error: IOException) {
                Log.w(TAG, "the stores could not be listed: ${error.message}")
                return cursor
            }
        for (i in 0 until stores.length()) {
            val store = stores.getJSONObject(i)
            val id = store.getString("id")
            val name = store.text("name") ?: id
            storeNames[id] = name
            cursor
                .newRow()
                .add(Root.COLUMN_ROOT_ID, id)
                .add(Root.COLUMN_DOCUMENT_ID, "$id:")
                .add(Root.COLUMN_TITLE, name)
                .add(Root.COLUMN_SUMMARY, "kernoid")
                .add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_IS_CHILD)
                .add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
        }
        return cursor
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor = guard {
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        val (store, node) = split(documentId)
        if (node.isEmpty()) {
            if (!storeNames.containsKey(store)) queryRoots(null).close()
            cursor
                .newRow()
                .add(Document.COLUMN_DOCUMENT_ID, documentId)
                .add(Document.COLUMN_DISPLAY_NAME, storeNames[store] ?: store)
                .add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
                .add(Document.COLUMN_FLAGS, Document.FLAG_DIR_SUPPORTS_CREATE)
        } else {
            row(cursor, store, ask("item", request(store, "id", node)).getJSONObject("item"))
        }
        cursor
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor = guard {
        val cursor = MatrixCursor(projection ?: DOCUMENT_COLUMNS)
        val (store, node) = split(parentDocumentId)
        val items = ask("list", request(store, "parent", node)).getJSONArray("items")
        for (i in 0 until items.length()) row(cursor, store, items.getJSONObject(i))
        cursor.setNotificationUri(
            requireContext().contentResolver,
            DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocumentId),
        )
        cursor
    }

    /** An item of the core as a row: its rights decide what the Files app offers; one in a vault is locked. */
    private fun row(cursor: MatrixCursor, store: String, item: JSONObject) {
        val directory = item.optBoolean("directory")
        val locked = item.optBoolean("locked")
        val rights = item.optJSONObject("rights") ?: JSONObject()
        var flags = 0
        if (!locked) {
            if (directory && rights.optBoolean("add")) flags = flags or Document.FLAG_DIR_SUPPORTS_CREATE
            if (!directory && rights.optBoolean("write")) flags = flags or Document.FLAG_SUPPORTS_WRITE
            if (rights.optBoolean("rename")) flags = flags or Document.FLAG_SUPPORTS_RENAME
            if (rights.optBoolean("delete")) {
                flags = flags or Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_MOVE
            }
        }
        val name = item.text("name").orEmpty()
        cursor
            .newRow()
            .add(Document.COLUMN_DOCUMENT_ID, "$store:${item.getString("id")}")
            .add(Document.COLUMN_DISPLAY_NAME, name)
            .add(Document.COLUMN_MIME_TYPE, if (directory) Document.MIME_TYPE_DIR else mediaType(item, name))
            .add(Document.COLUMN_SIZE, if (directory) null else item.optLong("size"))
            .add(Document.COLUMN_LAST_MODIFIED, item.text("modified")?.let(::millis))
            .add(Document.COLUMN_FLAGS, flags)
            .add(Document.COLUMN_SUMMARY, if (locked) requireContext().getString(R.string.documents_locked) else null)
    }

    private fun mediaType(item: JSONObject, name: String): String =
        item.text("mediaType")
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"

    private fun millis(text: String): Long? =
        try {
            Instant.parse(text).toEpochMilli()
        } catch (_: java.time.format.DateTimeParseException) {
            null
        }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor =
        guard {
            val (store, node) = split(documentId)
            if (node.isEmpty()) throw FileNotFoundException("a store's top has no content")
            val file = File(File(requireContext().cacheDir, "documents").apply { mkdirs() }, UUID.randomUUID().toString())
            val writes = 'w' in mode || 'a' in mode
            // "w" and "wt" start empty; reading, "rw" and "wa" need what is there.
            if (writes && (mode == "w" || 't' in mode)) {
                file.createNewFile()
            } else {
                try {
                    ask("fetch", request(store, "id", node).put("to", file.path))
                } catch (error: IOException) {
                    file.delete()
                    throw error
                }
            }
            signal?.throwIfCanceled()
            if (!writes) {
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY, ProviderSession.worker) {
                    file.delete()
                }
            } else {
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode), ProviderSession.worker) { failed ->
                    try {
                        if (failed == null) {
                            val item = ask("modify", request(store, "id", node).put("from", file.path))
                            notifyChildren(store, item.getJSONObject("item").text("parent"))
                        }
                    } catch (error: IOException) {
                        // OPEN: kept and tried again instead of dropped.
                        Log.w(TAG, "a written file could not be uploaded: ${error.message}")
                    } finally {
                        file.delete()
                    }
                }
            }
        }

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String = guard {
        val (store, parent) = split(parentDocumentId)
        val directory = mimeType == Document.MIME_TYPE_DIR
        val name = unique(store, parent, if (directory) displayName else withExtension(displayName, mimeType))
        val request = request(store, "parent", parent).put("name", name).put("directory", directory)
        var empty: File? = null
        if (!directory) {
            empty = File.createTempFile("new", null, requireContext().cacheDir)
            request.put("from", empty.path)
        }
        val item =
            try {
                ask("create", request).getJSONObject("item")
            } finally {
                empty?.delete()
            }
        notifyChildren(store, parent)
        "$store:${item.getString("id")}"
    }

    /** The name with the extension of [mimeType] when it has none that fits. */
    private fun withExtension(name: String, mimeType: String): String {
        val types = MimeTypeMap.getSingleton()
        val extension = types.getExtensionFromMimeType(mimeType) ?: return name
        val current = name.substringAfterLast('.', "").lowercase()
        return if (current == extension || types.getMimeTypeFromExtension(current) == mimeType) name else "$name.$extension"
    }

    /** [name], or `name (2).ext` and so on when the folder has it already – as Android expects of a provider. */
    private fun unique(store: String, parent: String, name: String): String {
        val items = ask("list", request(store, "parent", parent)).getJSONArray("items")
        val taken = (0 until items.length()).mapNotNull { items.getJSONObject(it).text("name") }.toSet()
        if (name !in taken) return name
        val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
        val (stem, extension) = name.substring(0, dot) to name.substring(dot)
        return (2..Int.MAX_VALUE).asSequence().map { "$stem ($it)$extension" }.first { it !in taken }
    }

    override fun renameDocument(documentId: String, displayName: String): String? = guard {
        val (store, node) = split(documentId)
        val item = ask("modify", request(store, "id", node).put("name", displayName)).getJSONObject("item")
        notifyChildren(store, item.text("parent"))
        null
    }

    override fun deleteDocument(documentId: String) = guard {
        val (store, node) = split(documentId)
        if (node.isEmpty()) throw FileNotFoundException("a store cannot be deleted")
        val parent = ask("item", request(store, "id", node)).getJSONObject("item").text("parent")
        ask("delete", request(store, "id", node))
        revokeDocumentPermission(documentId)
        notifyChildren(store, parent)
    }

    override fun moveDocument(
        sourceDocumentId: String,
        sourceParentDocumentId: String,
        targetParentDocumentId: String,
    ): String = guard {
        val (store, node) = split(sourceDocumentId)
        val (targetStore, target) = split(targetParentDocumentId)
        // OPEN: between stores – a copy and a delete, as the web app does.
        if (store != targetStore) throw FileNotFoundException("moving between stores is not supported yet")
        val request = request(store, "id", node).put("parent", target.ifEmpty { JSONObject.NULL })
        ask("modify", request)
        notifyChildren(store, split(sourceParentDocumentId).second)
        notifyChildren(store, target)
        sourceDocumentId
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean = guard {
        val (store, parent) = split(parentDocumentId)
        val (childStore, child) = split(documentId)
        if (store != childStore || child.isEmpty()) return@guard false
        if (parent.isEmpty()) return@guard true
        var node: String? = child
        repeat(64) {
            node = ask("item", request(store, "id", node!!)).getJSONObject("item").text("parent")
            if (node == null) return@guard false
            if (node == parent) return@guard true
        }
        false
    }
}
