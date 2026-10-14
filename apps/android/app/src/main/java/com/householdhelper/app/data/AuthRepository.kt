package com.householdhelper.app.data

import android.content.Context
import android.util.Log
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.householdhelper.app.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await

/** Firebase Auth: session state, ID tokens for the API, dev sign-in (emulator), sign-out. */
class AuthRepository(private val auth: FirebaseAuth? = FirebaseAuth.getInstance()) {
    private val _user = MutableStateFlow(auth?.currentUser)
    val user: StateFlow<FirebaseUser?> = _user
    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready
    /** Runs while the ID token still works (push token removal). */
    var beforeSignOut: (suspend () -> Unit)? = null

    init {
        auth?.addAuthStateListener { a ->
            _user.value = a.currentUser
            _ready.value = true
            Log.i(TAG, "auth state: ${a.currentUser?.uid ?: "signed out"}")
        }
    }

    val uid: String? get() = auth?.currentUser?.uid
    val email: String? get() = auth?.currentUser?.email
    val displayName: String? get() = auth?.currentUser?.displayName

    /** Cached by Firebase; forceRefresh after a server 401. Throws when signed out. */
    suspend fun idToken(forceRefresh: Boolean = false): String {
        val user = auth?.currentUser ?: throw ApiException(401, "unauthorized", "signed out")
        return user.getIdToken(forceRefresh).await().token ?: throw ApiException(401, "unauthorized", "no token")
    }

    /** dev flavor only: the seeded emulator users (alice | bob | carol, password "password"). */
    suspend fun signInDev(who: String) {
        check(BuildConfig.DEV_LOGIN) { "dev sign-in is only available in the dev flavor" }
        auth!!.signInWithEmailAndPassword("$who@dev.local", "password").await()
    }

    /** Credential Manager → Google ID token → Firebase. Needs the real project's Web client id (prod flavor). */
    suspend fun signInWithGoogle(activity: Context) {
        val clientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
        check(clientId.isNotEmpty()) { "Google sign-in needs the prod flavor (hh.googleWebClientId)" }
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(clientId)
            .setFilterByAuthorizedAccounts(false)
            .setAutoSelectEnabled(true)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val credential = try {
            CredentialManager.create(activity).getCredential(activity, request).credential
        } catch (e: GetCredentialCancellationException) {
            throw SignInCancelled()
        }
        check(credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) { "unexpected credential ${credential.type}" }
        val idToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
        auth!!.signInWithCredential(GoogleAuthProvider.getCredential(idToken, null)).await()
        Log.i(TAG, "google sign-in ok")
    }

    suspend fun signOut(context: Context? = null) {
        beforeSignOut?.invoke()
        auth?.signOut()
        // Forget the Google selection so the next sign-in shows the account picker again.
        context?.let { runCatching { CredentialManager.create(it).clearCredentialState(ClearCredentialStateRequest()) } }
    }

    class SignInCancelled : Exception("cancelled")

    companion object {
        const val TAG = "HH"
        /** For pure unit tests: no Firebase instance. */
        val NONE: AuthRepository by lazy { AuthRepository(null) }
    }
}
