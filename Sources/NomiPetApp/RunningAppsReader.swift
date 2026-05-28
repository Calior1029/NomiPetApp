import AppKit

enum RunningAppsReader {
    private static let systemApps: Set<String> = [
        "Finder", "SystemUIServer", "Dock", "WindowServer", "loginwindow",
        "NotificationCenter", "ControlCenter", "Spotlight", "AirPlayUIAgent",
        "TextInputMenuAgent", "universalaccessd", "talagent", "Accessibility Inspector"
    ]

    // Returns names of user-facing running apps (max 6), excluding common system processes
    nonisolated static func userFacingApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .filter { systemApps.contains($0) == false }
            .prefix(6)
            .map { $0 }
    }
}
