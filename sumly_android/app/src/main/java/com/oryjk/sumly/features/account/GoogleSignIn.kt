package com.oryjk.sumly.features.account

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

internal object GoogleSignIn {
    suspend fun pickCredential(context: Context, clientId: String, nonce: String): String? {
        val activity = context.findActivity() ?: throw AuthFailure.GoogleCredentialUnavailable
        val manager = CredentialManager.create(activity.applicationContext)
        val option = GetSignInWithGoogleOption.Builder(clientId).setNonce(nonce).build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        return try {
            val credential = manager.getCredential(activity, request).credential
            if (credential !is CustomCredential ||
                credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                throw AuthFailure.GoogleCredentialUnavailable
            }
            GoogleIdTokenCredential.createFrom(credential.data).idToken
        } catch (_: GetCredentialCancellationException) {
            null
        } catch (_: GetCredentialException) {
            throw AuthFailure.GoogleCredentialUnavailable
        } catch (_: GoogleIdTokenParsingException) {
            throw AuthFailure.GoogleCredentialUnavailable
        }
    }

    suspend fun clearCredentialState(applicationContext: Context) {
        try {
            CredentialManager.create(applicationContext).clearCredentialState(ClearCredentialStateRequest())
        } catch (_: ClearCredentialException) {
            // Some devices do not have an available credential provider.
        }
    }

    private tailrec fun Context.findActivity(): Activity? = when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
}
