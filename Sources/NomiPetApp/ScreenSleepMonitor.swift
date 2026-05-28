import AppKit

@MainActor
final class ScreenSleepMonitor {
    var onSleep: (() -> Void)?
    /// Called with the number of seconds the screen was asleep.
    var onWake: ((TimeInterval) -> Void)?

    private var sleepDate: Date?
    private var isObserving = false

    func start() {
        guard isObserving == false else { return }
        isObserving = true

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleSleep() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWake() }
        }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isObserving = false
    }

    private func handleSleep() {
        sleepDate = Date()
        onSleep?()
    }

    private func handleWake() {
        let duration = sleepDate.map { Date().timeIntervalSince($0) } ?? 0
        sleepDate = nil
        onWake?(duration)
    }
}
