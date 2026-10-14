// UIKit delegate for what SwiftUI has no hook for: the APNs token (forwarded to FCM by hand,
// swizzling is off via FirebaseAppDelegateProxyEnabled=NO), FCM token rotation, and the
// UNUserNotificationCenter delegate. Everything is handed to PushRegistrar on the main actor.
import FirebaseMessaging
import OSLog
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if !HH_EMULATOR
        Messaging.messaging().delegate = self
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if !HH_EMULATOR
        Messaging.messaging().apnsToken = deviceToken
        #endif
        Log.push.info("apns token received")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Log.push.error("apns registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        let present = await MainActor.run { PushRegistrar.shared.shouldPresent(payload) }
        return present ? [.banner, .list, .sound] : []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let payload = PushPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { PushRegistrar.shared.open(payload) }
    }
}

#if !HH_EMULATOR
extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        let token = fcmToken
        Task { @MainActor in PushRegistrar.shared.didReceiveFCMToken(token) }
    }
}
#endif
