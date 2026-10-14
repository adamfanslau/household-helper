// Push: asks for permission once a household exists, forwards the FCM registration token to
// PUT /v1/me/push-tokens, forgets it before sign-out, and decides what a notification does when
// it arrives (banner only for other households; a tap switches to the household).
// Dev (emulator) builds never register with APNs/FCM: `xcrun simctl push` exercises the handling.
import Foundation
import Observation
import OSLog
import UserNotifications
import UIKit

/// The keys hh-api puts in every push (`data` in FCM, top-level keys in the APNs payload).
nonisolated struct PushPayload: Sendable, Equatable {
    let householdID: String
    let type: String

    init?(userInfo: [AnyHashable: Any]) {
        guard let hid = userInfo["household_id"] as? String, !hid.isEmpty else { return nil }
        householdID = hid
        type = userInfo["type"] as? String ?? ""
    }

    init(householdID: String, type: String) {
        self.householdID = householdID
        self.type = type
    }
}

@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    enum Status: Equatable { case unknown, notAsked, authorized, denied }
    private(set) var status: Status = .unknown
    /// Household a notification tap asked for before the households were loaded.
    private(set) var pendingHouseholdID: String?

    private var api: ApiClient?
    private var households: HouseholdStore?
    private var router: AppRouter?
    private var fcmToken: String?
    private var uploadedToken: String?
    private var signedInUID: String?

    private init() {}

    func attach(api: ApiClient, households: HouseholdStore, router: AppRouter) {
        self.api = api
        self.households = households
        self.router = router
    }

    // MARK: Permission + registration

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = Self.status(for: settings.authorizationStatus)
    }

    /// Called once the user has a household: the first ask happens at a moment the value is obvious.
    func requestAuthorizationIfNeeded() async {
        await refreshStatus()
        guard status == .notAsked else {
            if status == .authorized { registerWithAPNs() }
            return
        }
        await requestAuthorization()
    }

    /// Explicit ask (Settings row). Returns the resulting status.
    @discardableResult
    func requestAuthorization() async -> Status {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            status = granted ? .authorized : .denied
            Log.push.info("notification permission: \(granted ? "granted" : "denied", privacy: .public)")
            if granted { registerWithAPNs() }
        } catch {
            Log.push.error("notification permission failed: \(error.localizedDescription, privacy: .public)")
            await refreshStatus()
        }
        return status
    }

    private func registerWithAPNs() {
        #if HH_EMULATOR
        Log.push.info("apns registration skipped (dev build)")
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private static func status(for s: UNAuthorizationStatus) -> Status {
        switch s {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .authorized
        }
    }

    // MARK: Token upload

    /// From MessagingDelegate (FCM rotates tokens; re-uploading is idempotent server-side).
    func didReceiveFCMToken(_ token: String?) {
        fcmToken = token
        Task { await upload() }
    }

    func authChanged(uid: String?) {
        signedInUID = uid
        if uid == nil { uploadedToken = nil } else { Task { await upload() } }
    }

    private func upload() async {
        guard let api, let token = fcmToken, signedInUID != nil, token != uploadedToken else { return }
        do {
            try await api.put("/v1/me/push-tokens", ["token": token, "platform": "ios"])
            uploadedToken = token
            Log.push.info("push token registered")
        } catch {
            Log.push.error("push token upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Before sign-out, while the ID token still works: the device must stop getting this user's pushes.
    func unregister() async {
        guard let api, let token = uploadedToken ?? fcmToken else { return }
        do {
            try await api.delete("/v1/me/push-tokens/\(token)")
            Log.push.info("push token removed")
        } catch {
            Log.push.error("push token removal failed: \(error.localizedDescription, privacy: .public)")
        }
        uploadedToken = nil
    }

    // MARK: Incoming notifications

    /// Foreground: no banner for the household already on screen (the list updates live over SSE).
    func shouldPresent(_ payload: PushPayload?) -> Bool {
        guard let payload, UIApplication.shared.applicationState == .active,
              payload.householdID == households?.current?.id else { return true }
        Log.push.info("suppressed push for the current household \(payload.householdID, privacy: .public)")
        return false
    }

    /// Tap: switch to that household's list (deferred until the households are loaded).
    func open(_ payload: PushPayload) {
        pendingHouseholdID = payload.householdID
        openPending()
    }

    func openPending() {
        guard let hid = pendingHouseholdID, let households, households.loaded else { return }
        pendingHouseholdID = nil
        guard let h = households.households.first(where: { $0.id == hid }) else {
            Log.push.info("push tap for an unknown household \(hid, privacy: .public)")
            return
        }
        if households.current?.id != hid { households.select(h) }
        router?.tab = .list
        Log.push.info("opened household \(hid, privacy: .public) from a push")
    }
}
