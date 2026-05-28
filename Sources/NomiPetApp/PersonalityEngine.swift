import Foundation

@MainActor
final class PersonalityEngine {
    private let deepSeek: DeepSeekClient
    private let settings: SettingsStore
    private let memory: MemoryStore
    private let patterns: UsagePatternStore
    private let userMemory: UserMemoryStore
    private var lastSourceKey = ""
    private var taskStartTimes: [String: Date] = [:]
    private var lastMemoryCompressionAt: Date?

    // Internal state
    private let sessionStartDate = Date()
    private var lastActivityAt = Date()

    private let ambientEvents: [(event: AmbientPetEvent, weight: Int)] = [
        (AmbientPetEvent(line: "我悄悄巡逻一下，看看有没有新动静。",  animationID: "peek",        duration: 3.8, bubbleDuration: 3.0), 4),
        (AmbientPetEvent(line: "主人，肩膀放松一点。",               animationID: "wave",        duration: 3.2, bubbleDuration: 2.8), 5),
        (AmbientPetEvent(line: "伸个懒腰。",                        animationID: "stretch",     duration: 3.5, bubbleDuration: 2.5), 3),
        (AmbientPetEvent(line: "偷偷靠近一点。",                     animationID: "happy",       duration: 3.4, bubbleDuration: 2.8), 3),
        (AmbientPetEvent(line: "有点困了。",                        animationID: "sleep",       duration: 5.5, bubbleDuration: 3.0), 1),
        (AmbientPetEvent(line: "喝口水？",                          animationID: "eat",         duration: 3.8, bubbleDuration: 3.0), 4),
        (AmbientPetEvent(line: "发个呆。",                          animationID: "pout",        duration: 4.0, bubbleDuration: 2.5), 2),
        (AmbientPetEvent(line: "看看周围有啥。",                     animationID: "look_around", duration: 3.8, bubbleDuration: 2.5), 2)
    ]

    init(deepSeek: DeepSeekClient, settings: SettingsStore, memory: MemoryStore, patterns: UsagePatternStore, userMemory: UserMemoryStore) {
        self.deepSeek = deepSeek
        self.settings = settings
        self.memory = memory
        self.patterns = patterns
        self.userMemory = userMemory
    }

    // MARK: - Activity line

    func line(for activity: AssistantActivity?, completion: @escaping @MainActor @Sendable (PetLine) -> Void) {
        guard let activity else {
            completion(PetLine(text: NomiPersonality.idleLines.randomElement() ?? NomiPersonality.openingLine, mood: .idle))
            return
        }

        let sourceKey = "\(activity.source)-\(activity.projectName)-\(activity.status.rawValue)-\(activity.detail)"
        if sourceKey == lastSourceKey {
            completion(idleLine(for: activity))
            return
        }
        lastSourceKey = sourceKey
        resetBoredom()

        let taskKey = "\(activity.source)-\(activity.projectName)"
        if taskStartTimes[taskKey] == nil { taskStartTimes[taskKey] = Date() }
        let duration = Date().timeIntervalSince(taskStartTimes[taskKey] ?? Date())

        if deepSeek.isConfigured {
            let ctx = buildContext(taskDuration: duration)
            deepSeek.generateLine(activity: activity, intensity: settings.personalityIntensity, context: ctx) { [weak self] response in
                Task { @MainActor in
                    guard let self else { return }
                    if let r = response, r.line.isEmpty == false,
                       r.line.hasPrefix("{") == false {   // guard: never store raw JSON
                        // Store the objective task fact (source + status + task title),
                        // NOT the AI's commentary line which may contain inferences.
                        let taskLabel = activity.projectName.isEmpty
                            ? activity.title
                            : activity.title.isEmpty
                                ? activity.projectName
                                : "\(activity.projectName)·\(activity.title)"
                        self.memory.append(type: .workEvent, content: "\(activity.source) \(activity.status.displayName)：\(taskLabel)")
                        completion(PetLine(text: r.line, mood: r.mood, source: .ai))
                    } else {
                        completion(self.localLine(for: activity))
                    }
                }
            }
        } else {
            completion(localLine(for: activity))
        }
    }

    // MARK: - Interaction line

    func interactionLine(
        for event: PetInteractionEvent,
        context: String,
        completion: @escaping @MainActor @Sendable (PetLine) -> Void
    ) {
        resetBoredom()
        if deepSeek.isConfigured {
            let ctx = buildContext(taskDuration: 0)
            deepSeek.generateInteractionLine(
                event: event,
                context: context,
                generationContext: ctx,
                intensity: settings.personalityIntensity
            ) { [weak self] response in
                Task { @MainActor in
                    guard let self else { return }
                    if let r = response, r.line.isEmpty == false {
                        // Store the objective interaction event only — not the AI's response
                        // which may contain inferences about user state.
                        self.memory.append(type: .interaction, content: event.promptName)
                        completion(PetLine(text: r.line, mood: r.mood, source: .ai))
                    } else {
                        completion(Self.localInteractionLine(for: event))
                    }
                }
            }
        } else {
            completion(Self.localInteractionLine(for: event))
        }
    }

    // MARK: - App launch observation

    func reactToAppLaunches(_ apps: [String], completion: @escaping @MainActor @Sendable (PetLine) -> Void) {
        guard deepSeek.isConfigured else { return }
        let ctx = buildContext(taskDuration: 0)
        deepSeek.generateAppObservation(apps: apps, context: ctx, intensity: settings.personalityIntensity) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                if let r = response, r.line.isEmpty == false {
                    // Store only the objective app list — not the AI's reaction line.
                    self.memory.append(type: .observation, content: "发现打开了：\(apps.joined(separator: "、"))")
                    completion(PetLine(text: r.line, mood: r.mood, source: .ai))
                }
            }
        }
    }

    // MARK: - Boredom reset

    func resetBoredom() {
        lastActivityAt = Date()
    }

    // MARK: - Memory compression

    /// Call periodically. When MemoryStore is approaching its limit, compresses
    /// the oldest records into a single distilled summary via AI.
    func checkAndCompressMemory() {
        guard memory.needsCompression, deepSeek.isConfigured else { return }
        // Cooldown: at most once every 30 minutes to avoid hammering the API.
        if let last = lastMemoryCompressionAt, Date().timeIntervalSince(last) < 1800 { return }
        lastMemoryCompressionAt = Date()

        let batch = memory.recordsForCompression()
        guard batch.isEmpty == false else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        let text = batch.map { "[\(formatter.string(from: $0.timestamp))] \($0.content)" }
                        .joined(separator: "\n")

        deepSeek.compressMemoryRecords(text) { [weak self] summary in
            Task { @MainActor in
                guard let self, let summary, summary.isEmpty == false else { return }
                self.memory.applyCompression(replacing: batch.count, with: summary)
            }
        }
    }

    // MARK: - Ambient event

    func randomAmbientEvent() -> AmbientPetEvent {
        let total = ambientEvents.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else {
            return AmbientPetEvent(line: "...", animationID: "wave", duration: 3.0, bubbleDuration: 2.5)
        }
        var ticket = Int.random(in: 0..<total)
        for item in ambientEvents {
            let w = max(0, item.weight)
            if ticket < w { return item.event }
            ticket -= w
        }
        return ambientEvents[0].event
    }

    // MARK: - Context builder

    func buildContext(taskDuration: TimeInterval) -> GenerationContext {
        var notes: [String] = []

        // Weekday / holiday
        let weekday = NomiPersonality.weekdayNote()
        if weekday.isEmpty == false { notes.append(weekday) }

        // Tiredness
        let tired = tirednessHint()
        if tired.isEmpty == false { notes.append("你\(tired)") }

        // Boredom
        let bored = boredHint()
        if bored.isEmpty == false { notes.append("你\(bored)") }

        // Work pattern
        if let pattern = patterns.patternNote() { notes.append(pattern) }

        // Combine AI-learned profile (priority) with user-written foundation (supplementary)
        let learned = userMemory.profileSummary()
        let foundation = settings.userFoundation.trimmingCharacters(in: .whitespacesAndNewlines)
        var profileParts: [String] = []
        if learned.isEmpty == false { profileParts.append(learned) }
        if foundation.isEmpty == false {
            let tag = learned.isEmpty ? "" : "（主人自己写的背景，供参考）"
            profileParts.append(tag.isEmpty ? foundation : "\(tag)\(foundation)")
        }

        return GenerationContext(
            memorySummary: memory.contextSummary(),
            runningApps: RunningAppsReader.userFacingApps(),
            timeDescription: NomiPersonality.timeDescription(),
            taskDurationDescription: NomiPersonality.durationDescription(taskDuration),
            situationNotes: notes,
            userProfileSummary: profileParts.joined(separator: "\n")
        )
    }

    // MARK: - Internal state

    private var tirednessLevel: Double {
        let c = Calendar.current
        let h = Double(c.component(.hour, from: Date())) + Double(c.component(.minute, from: Date())) / 60
        var t = 0.0
        switch h {
        case 0..<3:   t += 0.9
        case 3..<5:   t += 1.0
        case 5..<7:   t += 0.5
        case 7..<9:   t += 0.2
        case 9..<20:  t += 0.0
        case 20..<22: t += 0.2
        default:      t += 0.6  // 22-24
        }
        let sessionHours = Date().timeIntervalSince(sessionStartDate) / 3600
        if sessionHours > 5 { t += 0.4 } else if sessionHours > 3 { t += 0.2 }
        return min(1.0, t)
    }

    private func tirednessHint() -> String {
        switch tirednessLevel {
        case 0..<0.3: return ""
        case 0.3..<0.6: return "有点困了"
        case 0.6..<0.85: return "困了"
        default: return "很困很困"
        }
    }

    private var boredLevel: Double {
        let idle = Date().timeIntervalSince(lastActivityAt)
        switch idle {
        case ..<300:   return 0
        case ..<600:   return 0.3
        case ..<1200:  return 0.6
        default:       return 1.0
        }
    }

    private func boredHint() -> String {
        switch boredLevel {
        case 0..<0.3: return ""
        case 0.3..<0.7: return "有点无聊"
        default: return "无聊了"
        }
    }

    // MARK: - Local fallbacks

    private func localLine(for activity: AssistantActivity) -> PetLine {
        let title = activity.projectName.isEmpty ? activity.title : activity.projectName
        let text: String
        switch activity.status {
        case .failed:    text = "\(activity.source) 好像卡了一下。\(title) 看一眼？"
        case .waiting:   text = "\(activity.source) 在等你：\(title)。"
        case .running:   text = "\(activity.source) 在跑：\(title)。"
        case .completed: text = "\(activity.source) 这步完成了：\(title)。"
        case .thinking:  text = "\(activity.source) 在想：\(title)。"
        case .stalled:   text = "\(activity.source) 好久没动：\(title)。"
        }
        return PetLine(text: text, mood: localMood(for: activity))
    }

    private func idleLine(for activity: AssistantActivity) -> PetLine {
        let lines = NomiPersonality.repeatedActivityLines
            + ["还在看 \(activity.source) 的动静。"]
        return PetLine(text: lines.randomElement() ?? "...", mood: .idle)
    }

    private static func localInteractionLine(for event: PetInteractionEvent) -> PetLine {
        switch event {
        case .hover:    return PetLine(text: "嗯？", mood: .happy)
        case .dragEnded: return PetLine(text: "放好了。", mood: .caring)
        case .ambient:  return PetLine(text: "喝口水？", mood: .caring)
        case .headpat:  return PetLine(text: "……", mood: .nod)
        }
    }

    private func localMood(for activity: AssistantActivity) -> PetMood {
        switch activity.status {
        case .failed, .stalled: return .concerned
        case .waiting:          return .waiting
        case .running:          return .working
        case .completed:        return .nod
        case .thinking:         return .thinking
        }
    }
}
