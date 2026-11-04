// SPDX-License-Identifier: MIT
package dev.kernoid.kernoid

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The DocumentsProvider's own login (what `Kernoid.keptLogin` gave for it), never the app's: kernoid rotates refresh
 * tokens, and two holders renewing one login would end it. Kept encrypted with AES-GCM under a key of the Android
 * Keystore that never leaves it, in a SharedPreferences file of its own. A copy restored on another device cannot be
 * decrypted there and counts as none.
 */
object ProviderLogin {
    private const val PREFERENCES = "kernoid_documents"
    private const val LOGIN = "login"
    private const val ALIAS = "kernoid.documents.login"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    fun load(context: Context): String? {
        val stored = preferences(context).getString(LOGIN, null) ?: return null
        return try {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
            String(cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES), Charsets.UTF_8)
        } catch (_: GeneralSecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /** Keeps [kept] – written at once, as the login before it is used up. */
    fun save(context: Context, kept: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(kept.toByteArray(Charsets.UTF_8))
        preferences(context).edit().putString(LOGIN, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()
    }

    fun clear(context: Context) {
        preferences(context).edit().remove(LOGIN).commit()
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as SecretKey?)?.let { return it }
        val spec =
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(spec)
            generateKey()
        }
    }
}
