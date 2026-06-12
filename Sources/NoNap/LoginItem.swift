import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at login" toggle.
///
/// This only works from a real `.app` bundle (it needs a bundle identifier).
/// Under `swift run` there is no bundle id, so the calls degrade gracefully:
/// `isEnabled` reports false and `set(_:)` is a no-op rather than crashing.
enum LoginItem {

    /// Whether NoNap is currently registered to launch at login.
    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Whether login-item registration is even possible in this build
    /// (i.e. we're running from a bundle with an identifier).
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Register or unregister NoNap as a login item. Throws on failure so the
    /// caller can surface a problem; safe to call when unsupported (no-op).
    static func set(_ on: Bool) throws {
        guard isSupported else { return }
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
