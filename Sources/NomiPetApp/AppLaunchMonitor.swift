import AppKit

// Watches NSWorkspace for app-launch bursts and notable single launches,
// then fires onBurst with the recently opened app names so Nomi can react.
@MainActor
final class AppLaunchMonitor {
    private static let burstWindow: TimeInterval = 12    // seconds to group launches
    private static let burstThreshold = 2               // min apps to call it a burst
    private static let cooldown: TimeInterval = 90      // min gap between triggers
    private static let ignoredApps: Set<String> = [
        "NomiPetApp", "Finder", "SystemUIServer", "Dock", "loginwindow",
        "Terminal", "iTerm2", "Xcode", "Simulator"
    ]
    // These apps are interesting enough to trigger even alone (clear scene shift)
    private static let notableApps: Set<String> = [
        // Video
        "IINA", "VLC", "Infuse", "Infuse 7", "QuickTime Player", "Apple TV",
        "Bilibili", "哔哩哔哩", "爱奇艺", "优酷", "腾讯视频", "芒果TV", "Netflix",
        // Music
        "Spotify", "Music", "网易云音乐", "QQ音乐", "酷狗音乐",
        // Social
        "WeChat", "微信", "QQ", "Telegram", "Discord", "WhatsApp", "Line",
        // Gaming
        "Steam", "Epic Games Launcher", "GOG Galaxy",
        // Short video
        "抖音", "TikTok"
    ]

    var onBurst: (([String]) -> Void)?

    private var recentLaunches: [(name: String, at: Date)] = []
    private var lastTriggerDate: Date = .distantPast
    private var isObserving = false

    func start() {
        guard isObserving == false else { return }
        isObserving = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract app info here (on main queue) before hopping to MainActor
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName
            let policy = app?.activationPolicy
            Task { @MainActor [weak self] in
                self?.handleLaunch(name: name, policy: policy)
            }
        }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isObserving = false
    }

    private func handleLaunch(name: String?, policy: NSApplication.ActivationPolicy?) {
        guard
            let name,
            policy == .regular,
            Self.ignoredApps.contains(name) == false
        else { return }

        let now = Date()

        // Prune stale entries, then record the new launch
        recentLaunches = recentLaunches.filter { now.timeIntervalSince($0.at) < Self.burstWindow }
        recentLaunches.append((name: name, at: now))

        guard now.timeIntervalSince(lastTriggerDate) >= Self.cooldown else { return }

        let hasBurst = recentLaunches.count >= Self.burstThreshold
        let isNotable = Self.notableApps.contains(name)

        if hasBurst || isNotable {
            lastTriggerDate = now
            let triggered = recentLaunches.map(\.name)
            recentLaunches = []
            onBurst?(triggered)
        }
    }
}
