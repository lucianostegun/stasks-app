import AppKit
import CoreServices

/// Apple Events (Automation) permission towards one target app, as macOS reports it through
/// `AEDeterminePermissionToAutomateTarget`. The system only knows the answer while the target is running.
enum AutomationPermission {
    enum State: Equatable {
        case granted
        case denied
        case notDetermined
        case targetNotRunning
        case unknown(OSStatus)
    }

    /// `ask == true` shows the system consent dialog when the user has not decided yet, and blocks until they answer.
    static func check(bundleId: String, ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let desc = target.aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case -1743: return .denied            // errAEEventNotPermitted
        case -1744: return .notDetermined     // errAEEventWouldRequireUserConsent
        case -600: return .targetNotRunning   // procNotFound
        default: return .unknown(status)
        }
    }

    static func isInstalled(bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    static func isRunning(bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
