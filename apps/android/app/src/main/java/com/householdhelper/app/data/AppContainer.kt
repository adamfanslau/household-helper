package com.householdhelper.app.data

import android.content.Context

/** Manual DI: one instance of each service for the process (HHApplication.container). */
class AppContainer(context: Context) {
    val auth = AuthRepository()
    val api = ApiClient(auth)
    val households = HouseholdRepository(context.applicationContext, api)
    val list = ListRepository(api)
}
