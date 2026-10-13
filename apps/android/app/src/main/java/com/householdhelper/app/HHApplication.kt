package com.householdhelper.app

import android.app.Application
import com.google.firebase.auth.FirebaseAuth
import com.householdhelper.app.data.AppContainer

class HHApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        // dev flavor: Firebase Auth emulator on the host (10.0.2.2). Must run before any auth use.
        if (BuildConfig.AUTH_EMULATOR_HOST.isNotEmpty()) {
            val (host, port) = BuildConfig.AUTH_EMULATOR_HOST.split(":")
            FirebaseAuth.getInstance().useEmulator(host, port.toInt())
        }
        container = AppContainer(this)
    }
}
