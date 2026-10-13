package com.householdhelper.app.data

import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.householdhelper.app.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await

/** Firebase Auth: session state, ID tokens for the API, dev sign-in (emulator), sign-out. */
class AuthRepository(private val auth: FirebaseAuth = FirebaseAuth.getInstance()) {
    private val _user = MutableStateFlow(auth.currentUser)
    val user: StateFlow<FirebaseUser?> = _user
    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready

    init {
        auth.addAuthStateListener { a ->
            _user.value = a.currentUser
            _ready.value = true
            Log.i(TAG, "auth state: ${a.currentUser?.uid ?: "signed out"}")
        }
    }

    val uid: String? get() = auth.currentUser?.uid
    val email: String? get() = auth.currentUser?.email

    /** Cached by Firebase; forceRefresh after a server 401. Throws when signed out. */
    suspend fun idToken(forceRefresh: Boolean = false): String {
        val user = auth.currentUser ?: throw ApiException(401, "unauthorized", "signed out")
        return user.getIdToken(forceRefresh).await().token ?: throw ApiException(401, "unauthorized", "no token")
    }

    /** dev flavor only: the seeded emulator users (alice | bob | carol, password "password"). */
    suspend fun signInDev(who: String) {
        check(BuildConfig.DEV_LOGIN) { "dev sign-in is only available in the dev flavor" }
        auth.signInWithEmailAndPassword("$who@dev.local", "password").await()
    }

    fun signOut() {
        auth.signOut()
    }

    companion object {
        const val TAG = "HH"
    }
}
