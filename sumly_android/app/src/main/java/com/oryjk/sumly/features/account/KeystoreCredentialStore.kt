package com.oryjk.sumly.features.account

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

internal class KeystoreCredentialStore(context: Context) : CredentialStore {
    private val preferences = context.applicationContext.getSharedPreferences(
        "sumly_native_auth", Context.MODE_PRIVATE,
    )

    override fun load(): StoredSession? {
        return storage {
            if (preferences.getBoolean(SignedOut, false)) return@storage null
            val ciphertext = preferences.getString(Session, null) ?: return@storage null
            val encoded = Base64.decode(ciphertext, Base64.NO_WRAP)
            if (encoded.size <= IvSize) throw AuthFailure.SafeStorage
            val key = keyStore().getKey(KeyAlias, null) as? SecretKey ?: throw AuthFailure.SafeStorage
            val cipher = Cipher.getInstance(Algorithm)
            val parameters = GCMParameterSpec(128, encoded, 0, IvSize)
            cipher.init(Cipher.DECRYPT_MODE, key, parameters)
            cipher.updateAAD(AssociatedData)
            val payload = JSONObject(cipher.doFinal(encoded, IvSize, encoded.size - IvSize).decodeToString())
            StoredSession(
                credentials = AuthJson.decodeLogin(payload.getJSONObject("credentials")),
                expiresAtMillis = payload.getLong("expires_at_ms"),
                primaryLoginAtMillis = payload.getLong("primary_login_at_ms"),
            )
        }
    }

    override fun save(value: StoredSession) {
        storage {
            val key = keyStore().getKey(KeyAlias, null) as? SecretKey ?: generateKey()
            val cipher = Cipher.getInstance(Algorithm)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.updateAAD(AssociatedData)
            val payload = JSONObject()
                .put("credentials", AuthJson.encodeLogin(value.credentials))
                .put("expires_at_ms", value.expiresAtMillis)
                .put("primary_login_at_ms", value.primaryLoginAtMillis)
            val ciphertext = cipher.iv + cipher.doFinal(payload.toString().encodeToByteArray())
            val persisted = preferences.edit()
                .putString(Session, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                .remove(SignedOut)
                .commit()
            if (!persisted) throw AuthFailure.SafeStorage
        }
    }

    override fun clear() {
        val markerSaved = try {
            preferences.edit().remove(Session).putBoolean(SignedOut, true).commit()
        } catch (_: Exception) {
            false
        }
        val keyRemoved = try {
            val keys = keyStore()
            keys.deleteEntry(KeyAlias)
            !keys.containsAlias(KeyAlias)
        } catch (_: Exception) {
            false
        }
        if (!markerSaved && !keyRemoved) throw AuthFailure.SignOutStorage
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(AndroidKeyStore).apply { load(null) }

    private fun generateKey(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, AndroidKeyStore)
        val spec = KeyGenParameterSpec.Builder(
            KeyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private inline fun <T> storage(block: () -> T): T = try {
        block()
    } catch (_: Exception) {
        throw AuthFailure.SafeStorage
    }

    companion object {
        private const val AndroidKeyStore = "AndroidKeyStore"
        private const val KeyAlias = "com.oryjk.sumly.native-auth.v1"
        private const val Algorithm = "AES/GCM/NoPadding"
        private const val IvSize = 12
        private const val Session = "encrypted_session"
        private const val SignedOut = "signed_out"
        private val AssociatedData = KeyAlias.encodeToByteArray()
    }
}
