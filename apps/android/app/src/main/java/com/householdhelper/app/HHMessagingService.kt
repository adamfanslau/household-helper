package com.householdhelper.app

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.householdhelper.app.data.PushRegistrar

/**
 * FCM entry points. In the background the SDK posts hh-api's `notification` block itself (channel
 * "household", tap opens MainActivity with the `data` keys as extras); in the foreground the message
 * lands here and PushRegistrar decides whether a banner is warranted.
 */
class HHMessagingService : FirebaseMessagingService() {
    private val push get() = (application as HHApplication).container.push

    override fun onNewToken(token: String) {
        push.onToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        push.handleMessage(
            householdId = message.data[PushRegistrar.EXTRA_HOUSEHOLD_ID],
            type = message.data[PushRegistrar.EXTRA_TYPE] ?: "",
            title = message.notification?.title,
            body = message.notification?.body,
        )
    }
}
