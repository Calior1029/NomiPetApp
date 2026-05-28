import AppKit
import Foundation

@MainActor
final class SettingsStore {
    static let sizeDidChange = Notification.Name("NomiPetSizeDidChange")
    static let bubbleDidChange = Notification.Name("NomiPetBubbleDidChange")
    static let monitoringDidChange = Notification.Name("NomiPetMonitoringDidChange")
    static let personalityDidChange = Notification.Name("NomiPetPersonalityDidChange")
    static let minPetScale: CGFloat = 0.2
    static let maxPetScale: CGFloat = 1.6
    static let minBubbleScale: CGFloat = 0.75
    static let maxBubbleScale: CGFloat = 1.35
    static let minBubbleOffsetX: CGFloat = -16
    static let maxBubbleOffsetX: CGFloat = 80
    static let minBubbleOffsetY: CGFloat = -10
    static let maxBubbleOffsetY: CGFloat = 70
    static let minBubbleTitleFontSize: CGFloat = 14
    static let maxBubbleTitleFontSize: CGFloat = 28
    static let minBubbleBodyFontSize: CGFloat = 13
    static let maxBubbleBodyFontSize: CGFloat = 26
    static let defaultBubbleTitleFontSize: CGFloat = 21
    static let defaultBubbleBodyFontSize: CGFloat = 20
    static let minBubbleLineSpacing: CGFloat = 0
    static let maxBubbleLineSpacing: CGFloat = 10
    static let defaultBubbleLineSpacing: CGFloat = 2
    static let minBubbleTextPadding: CGFloat = 14
    static let maxBubbleTextPadding: CGFloat = 44
    static let defaultBubbleTextPadding: CGFloat = 24

    private let settingsURL: URL
    private var currentScale: CGFloat
    private var currentBubbleScale: CGFloat
    private var currentBubbleOffsetX: CGFloat
    private var currentBubbleOffsetY: CGFloat
    private var currentBubbleTitleFontSize: CGFloat
    private var currentBubbleBodyFontSize: CGFloat
    private var currentBubbleLineSpacing: CGFloat
    private var currentBubbleTextPadding: CGFloat
    private var currentMonitorCodex: Bool
    private var currentMonitorClaude: Bool
    private var currentPersonalityIntensity: PersonalityIntensity
    private var currentUserFoundation: String

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nomi-pet", isDirectory: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: settingsURL),
           let payload = try? JSONDecoder().decode(SettingsPayload.self, from: data) {
            currentScale = Self.clamp(CGFloat(payload.petScale))
            currentBubbleScale = Self.clampBubbleScale(CGFloat(payload.bubbleScale ?? 1.0))
            currentBubbleOffsetX = Self.clampBubbleOffsetX(CGFloat(payload.bubbleOffsetX ?? 0))
            currentBubbleOffsetY = Self.clampBubbleOffsetY(CGFloat(payload.bubbleOffsetY ?? 0))
            currentBubbleTitleFontSize = Self.clampBubbleTitleFontSize(CGFloat(payload.bubbleTitleFontSize ?? Self.defaultBubbleTitleFontSize))
            currentBubbleBodyFontSize = Self.clampBubbleBodyFontSize(CGFloat(payload.bubbleBodyFontSize ?? Self.defaultBubbleBodyFontSize))
            currentBubbleLineSpacing = Self.clampBubbleLineSpacing(CGFloat(payload.bubbleLineSpacing ?? Self.defaultBubbleLineSpacing))
            currentBubbleTextPadding = Self.clampBubbleTextPadding(CGFloat(payload.bubbleTextPadding ?? Self.defaultBubbleTextPadding))
            currentMonitorCodex = payload.monitorCodex ?? true
            currentMonitorClaude = payload.monitorClaude ?? true
            currentPersonalityIntensity = PersonalityIntensity(rawValue: payload.personalityIntensity ?? PersonalityIntensity.normal.rawValue) ?? .normal
            currentUserFoundation = payload.userFoundation ?? ""
        } else {
            let migrated = UserDefaults.standard.double(forKey: "petScale")
            currentScale = Self.clamp(migrated > 0 ? CGFloat(migrated) : 1.0)
            currentBubbleScale = 1.0
            currentBubbleOffsetX = 0
            currentBubbleOffsetY = 0
            currentBubbleTitleFontSize = Self.defaultBubbleTitleFontSize
            currentBubbleBodyFontSize = Self.defaultBubbleBodyFontSize
            currentBubbleLineSpacing = Self.defaultBubbleLineSpacing
            currentBubbleTextPadding = Self.defaultBubbleTextPadding
            currentMonitorCodex = true
            currentMonitorClaude = true
            currentPersonalityIntensity = .normal
            currentUserFoundation = ""
            save()
        }
    }

    var petScale: CGFloat {
        get {
            currentScale
        }
        set {
            currentScale = Self.clamp(newValue)
            save()
            NotificationCenter.default.post(name: Self.sizeDidChange, object: self)
        }
    }

    var monitorCodex: Bool {
        get {
            currentMonitorCodex
        }
        set {
            guard currentMonitorCodex != newValue else { return }
            currentMonitorCodex = newValue
            save()
            NotificationCenter.default.post(name: Self.monitoringDidChange, object: self)
        }
    }

    var bubbleScale: CGFloat {
        get {
            currentBubbleScale
        }
        set {
            currentBubbleScale = Self.clampBubbleScale(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var bubbleOffsetX: CGFloat {
        get {
            currentBubbleOffsetX
        }
        set {
            currentBubbleOffsetX = Self.clampBubbleOffsetX(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var bubbleOffsetY: CGFloat {
        get {
            currentBubbleOffsetY
        }
        set {
            currentBubbleOffsetY = Self.clampBubbleOffsetY(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var bubbleTitleFontSize: CGFloat {
        get {
            currentBubbleTitleFontSize
        }
        set {
            currentBubbleTitleFontSize = Self.clampBubbleTitleFontSize(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var bubbleBodyFontSize: CGFloat {
        get {
            currentBubbleBodyFontSize
        }
        set {
            currentBubbleBodyFontSize = Self.clampBubbleBodyFontSize(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var bubbleLineSpacing: CGFloat {
        get {
            currentBubbleLineSpacing
        }
        set {
            currentBubbleLineSpacing = Self.clampBubbleLineSpacing(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var bubbleTextPadding: CGFloat {
        get {
            currentBubbleTextPadding
        }
        set {
            currentBubbleTextPadding = Self.clampBubbleTextPadding(newValue)
            save()
            NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
        }
    }

    var monitorClaude: Bool {
        get {
            currentMonitorClaude
        }
        set {
            guard currentMonitorClaude != newValue else { return }
            currentMonitorClaude = newValue
            save()
            NotificationCenter.default.post(name: Self.monitoringDidChange, object: self)
        }
    }

    var userFoundation: String {
        get { currentUserFoundation }
        set {
            currentUserFoundation = newValue
            save()
        }
    }

    var personalityIntensity: PersonalityIntensity {
        get {
            currentPersonalityIntensity
        }
        set {
            guard currentPersonalityIntensity != newValue else { return }
            currentPersonalityIntensity = newValue
            save()
            NotificationCenter.default.post(name: Self.personalityDidChange, object: self)
        }
    }

    func reset() {
        currentScale = 1.0
        currentBubbleScale = 1.0
        currentBubbleOffsetX = 0
        currentBubbleOffsetY = 0
        currentBubbleTitleFontSize = Self.defaultBubbleTitleFontSize
        currentBubbleBodyFontSize = Self.defaultBubbleBodyFontSize
        currentBubbleLineSpacing = Self.defaultBubbleLineSpacing
        currentBubbleTextPadding = Self.defaultBubbleTextPadding
        currentPersonalityIntensity = .normal
        save()
        NotificationCenter.default.post(name: Self.sizeDidChange, object: self)
        NotificationCenter.default.post(name: Self.bubbleDidChange, object: self)
    }

    private func save() {
        let payload = SettingsPayload(
            petScale: Double(currentScale),
            bubbleScale: Double(currentBubbleScale),
            bubbleOffsetX: Double(currentBubbleOffsetX),
            bubbleOffsetY: Double(currentBubbleOffsetY),
            bubbleTitleFontSize: Double(currentBubbleTitleFontSize),
            bubbleBodyFontSize: Double(currentBubbleBodyFontSize),
            bubbleLineSpacing: Double(currentBubbleLineSpacing),
            bubbleTextPadding: Double(currentBubbleTextPadding),
            monitorCodex: currentMonitorCodex,
            monitorClaude: currentMonitorClaude,
            personalityIntensity: currentPersonalityIntensity.rawValue,
            userFoundation: currentUserFoundation.isEmpty ? nil : currentUserFoundation
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(maxPetScale, max(minPetScale, value))
    }

    private static func clampBubbleScale(_ value: CGFloat) -> CGFloat {
        min(maxBubbleScale, max(minBubbleScale, value))
    }

    private static func clampBubbleOffsetX(_ value: CGFloat) -> CGFloat {
        min(maxBubbleOffsetX, max(minBubbleOffsetX, value))
    }

    private static func clampBubbleOffsetY(_ value: CGFloat) -> CGFloat {
        min(maxBubbleOffsetY, max(minBubbleOffsetY, value))
    }

    private static func clampBubbleTitleFontSize(_ value: CGFloat) -> CGFloat {
        min(maxBubbleTitleFontSize, max(minBubbleTitleFontSize, value))
    }

    private static func clampBubbleBodyFontSize(_ value: CGFloat) -> CGFloat {
        min(maxBubbleBodyFontSize, max(minBubbleBodyFontSize, value))
    }

    private static func clampBubbleLineSpacing(_ value: CGFloat) -> CGFloat {
        min(maxBubbleLineSpacing, max(minBubbleLineSpacing, value))
    }

    private static func clampBubbleTextPadding(_ value: CGFloat) -> CGFloat {
        min(maxBubbleTextPadding, max(minBubbleTextPadding, value))
    }
}

private struct SettingsPayload: Codable {
    let petScale: Double
    let bubbleScale: Double?
    let bubbleOffsetX: Double?
    let bubbleOffsetY: Double?
    let bubbleTitleFontSize: Double?
    let bubbleBodyFontSize: Double?
    let bubbleLineSpacing: Double?
    let bubbleTextPadding: Double?
    let monitorCodex: Bool?
    let monitorClaude: Bool?
    let personalityIntensity: Int?
    let userFoundation: String?
}
