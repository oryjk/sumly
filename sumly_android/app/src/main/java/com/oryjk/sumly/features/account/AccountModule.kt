package com.oryjk.sumly.features.account

import android.content.Context
import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.core.network.ApiException

fun createAccountViewModel(
    api: ApiClient,
    context: Context,
    onAccountDeleted: suspend (Long) -> Unit = {},
): AccountViewModel = AccountViewModel(
    BackendAuthGateway(api),
    KeystoreCredentialStore(context),
    isUnauthorized = { error ->
        error == AuthFailure.Unauthorized || (error is ApiException && error.httpStatus == 401)
    },
    onAccountDeleted = onAccountDeleted,
    clearGoogleCredentialState = { GoogleSignIn.clearCredentialState(context.applicationContext) },
)
