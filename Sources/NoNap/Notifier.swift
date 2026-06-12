import Foundation
import UserNotifications

/// Thin wrapper over `UNUserNotificationCenter` for the "notify when a timed
/// session ends" feature.
///
/// Like login items, this needs a real `.app` bundle; under `swift run` the
/// notification center is unavailable, so the calls become no-ops instead of
/// crashing. Authorization is requested lazily (on the first timed start) so
/// users who never use timers are never prompted.
enum Notifier {

    private static var available: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Ask for notification permission once. Safe to call repeatedly.
    static func requestAuthorizationIfNeeded() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a notification immediately (best effort).
    static func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // deliver now
        )
        UNUserNotificationCenter.current().add(request)
    }
}
