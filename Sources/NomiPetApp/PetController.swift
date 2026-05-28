import AppKit
import Foundation

@MainActor
final class PetController {
    private let store: AnimationStore
    private let window: PetWindowController
    private let monitor: ProgressMonitor
    private let personality: PersonalityEngine
    private let memory: MemoryStore
    private let patterns: UsagePatternStore

    private var currentAnimation: LoadedAnimation?
    private var currentLine = NomiPersonality.openingLine
    private var currentBubbleStyle: BubblePresentationStyle = .compact
    private var visibleLine: String?
    private var currentStatus: AssistantStatus?
    private var visibleStatus: AssistantStatus?
    private var visibleBubbleStyle: BubblePresentationStyle = .compact
    private var frameIndex = 0
    private var frameTimer: Timer?
    private var returnToIdleTimer: Timer?
    private var bubbleHideTimer: Timer?
    private var ambientEventTimer: Timer?
    private var dragAnimationID: String?
    private var lineBeforeDrag: String?
    private var persistentWorkLine: String?
    private var persistentWorkStyle: BubblePresentationStyle = .compact
    private var isHovering = false
    private var lastInteractionAt: [PetInteractionEvent: Date] = [:]
    private var wanderStepTimer: Timer?
    private var wanderTimer: Timer?
    private var isWandering = false
    private var wanderRemaining: CGFloat = 0
    private var wanderDX: CGFloat = 0

    /// Fires whenever the pet shows a line in a bubble.
    /// All bubble lines — work status, ambient, interaction, greeting — are forwarded to the chat window.
    var onBubbleLine: ((String) -> Void)?

    private static let musicApps: Set<String> = [
        "Spotify", "Apple Music", "网易云音乐", "IINA", "VLC", "Music"
    ]

    init(store: AnimationStore, window: PetWindowController, monitor: ProgressMonitor, personality: PersonalityEngine, memory: MemoryStore, patterns: UsagePatternStore) {
        self.store = store
        self.window = window
        self.monitor = monitor
        self.personality = personality
        self.memory = memory
        self.patterns = patterns
    }

    func start() {
        playCalmIdle(line: currentLine, showBubble: true)
        window.show()

        window.onDragPhase = { [weak self] phase in
            self?.handleDrag(phase)
        }
        window.onHoverChanged = { [weak self] isHovering in
            self?.handleHover(isHovering)
        }
        monitor.onActivity = { [weak self] activity in
            self?.handle(activity: activity)
        }
        monitor.start()
        scheduleNextAmbientEvent()
        scheduleNextWander()
        scheduleStartupGreeting()
    }

    func stop() {
        frameTimer?.invalidate()
        returnToIdleTimer?.invalidate()
        bubbleHideTimer?.invalidate()
        ambientEventTimer?.invalidate()
        wanderTimer?.invalidate()
        wanderStepTimer?.invalidate()
        monitor.stop()
        memory.recordSessionEnd()
        patterns.recordSessionEnd()
    }

    func showPet() {
        window.show()
        playReaction(animationID: "wave", line: "我在这里。你忙你的，我陪着。", duration: 3.5, bubbleDuration: 3.0)
    }

    func refreshActivity() {
        playReaction(animationID: "thinking", line: "我看一下最新进度，马上回来。", duration: 4.5, bubbleDuration: 3.0)
        monitor.refresh()
    }

    // MARK: - Screen sleep / wake

    func handleScreenSleep() {
        // Screen going to sleep; nothing active needed — wake handles the greeting
    }

    func handleScreenWake(duration: TimeInterval) {
        guard let gapNote = NomiPersonality.sessionGapNote(duration) else { return }
        guard dragAnimationID == nil else { return }
        personality.interactionLine(for: .hover, context: gapNote) { [weak self] line in
            Task { @MainActor in
                guard let self, self.dragAnimationID == nil else { return }
                self.currentLine = line.text
                self.currentBubbleStyle = .dynamic
                // wake_up → idle → then the reaction line
                self.playReaction(animationID: "wake_up", line: "", duration: 1.2, showBubble: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self else { return }
                    self.playReaction(
                        animationID: line.mood.animationID,
                        line: line.text,
                        duration: self.reactionDuration(for: line.mood),
                        bubbleDuration: 5.0,
                        style: .dynamic
                    )
                    if line.text.isEmpty == false {
                        self.onBubbleLine?(line.text)
                    }
                }
            }
        }
    }

    // Called by AppLaunchMonitor when a burst of notable apps are opened
    func handleAppLaunchBurst(apps: [String]) {
        guard dragAnimationID == nil else { return }
        let hasMusic = apps.contains { Self.musicApps.contains($0) }
        personality.reactToAppLaunches(apps) { [weak self] line in
            guard let self else { return }
            self.currentLine = line.text
            self.currentBubbleStyle = .dynamic
            // Override animation with dance when music app detected
            let animID = hasMusic ? "dance" : line.mood.animationID
            let duration: TimeInterval = hasMusic ? 6.0 : 4.5
            self.playReaction(animationID: animID, line: line.text, duration: duration, bubbleDuration: 5.0, style: .dynamic)
            if line.text.isEmpty == false {
                self.onBubbleLine?(line.text)
            }
        }
    }

    // Called when user right-clicks Nomi
    func handleRightClick() {
        guard dragAnimationID == nil else { return }
        if canRunInteraction(.headpat, cooldown: 30) {
            requestInteraction(.headpat, animationID: "headpat", duration: 2.5, bubbleDuration: 3.5)
        }
    }

    // Called when the chat window gets an AI response — play matching animation
    func receiveChat(response: AIResponse) {
        guard dragAnimationID == nil else { return }
        let animID = response.mood.animationID
        let duration = reactionDuration(for: response.mood)
        playReaction(
            animationID: animID,
            line: response.line,
            duration: max(duration, 3.5),
            bubbleDuration: 4.0,
            style: .dynamic
        )
        currentLine = response.line
        currentBubbleStyle = .dynamic
    }

    private func handle(activity: AssistantActivity?) {
        if activity != nil { patterns.recordActivityStart() }
        personality.checkAndCompressMemory()
        personality.line(for: activity) { [weak self] line in
            Task { @MainActor in
                guard self?.dragAnimationID == nil else { return }
                let presentation = PetBubbleComposer.presentation(activity: activity, line: line)
                let displayLine = presentation.text
                let keepBubbleVisible = activity?.keepsBubbleVisible == true

                self?.currentLine = displayLine
                self?.currentBubbleStyle = presentation.style
                self?.currentStatus = activity?.status
                self?.persistentWorkLine = keepBubbleVisible ? displayLine : nil
                self?.persistentWorkStyle = keepBubbleVisible ? presentation.style : .compact
                self?.scheduleNextAmbientEvent()
                self?.scheduleNextWander()
                switch line.mood {
                case .idle:
                    self?.playCalmIdle(line: displayLine, showBubble: true)
                default:
                    self?.playReaction(
                        animationID: line.mood.animationID,
                        line: displayLine,
                        duration: self?.reactionDuration(for: line.mood) ?? 4,
                        bubbleDuration: keepBubbleVisible ? nil : self?.bubbleDuration(for: line.mood) ?? 4,
                        style: presentation.style
                    )
                }
                if displayLine.isEmpty == false {
                    self?.onBubbleLine?(displayLine)
                }
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        guard dragAnimationID == nil else { return }

        if hovering {
            personality.resetBoredom()
            guard currentAnimation?.spec.id == "idle_breathe" else { return }
            if persistentWorkLine == nil, canRunInteraction(.hover, cooldown: 45) {
                requestInteraction(.hover, animationID: "jump", duration: 1.4, bubbleDuration: 3.4)
            } else {
                playReaction(
                    animationID: "jump",
                    line: currentLine,
                    duration: 0.9,
                    showBubble: persistentWorkLine != nil,
                    style: persistentWorkLine == nil ? currentBubbleStyle : persistentWorkStyle
                )
            }
        } else if currentAnimation?.spec.id == "jump" {
            playCalmIdle(line: currentLine, showBubble: false)
        }
    }

    private func handleDrag(_ phase: PetDragPhase) {
        switch phase {
        case .started:
            personality.resetBoredom()
            lineBeforeDrag = currentLine
            dragAnimationID = nil
            returnToIdleTimer?.invalidate()
            returnToIdleTimer = nil
            hideBubble()
        case .movingLeft:
            playDragAnimation(id: "run_left")
        case .movingRight:
            playDragAnimation(id: "run_right")
        case .ended:
            dragAnimationID = nil
            if canRunInteraction(.dragEnded, cooldown: 20) {
                requestInteraction(.dragEnded, animationID: "wave", duration: 3.2, bubbleDuration: 3.0)
            } else {
                playCalmIdle(line: lineBeforeDrag ?? currentLine, showBubble: false)
            }
            lineBeforeDrag = nil
        }
    }

    private func playDragAnimation(id: String) {
        guard dragAnimationID != id else { return }
        dragAnimationID = id
        play(animationID: id, line: lineBeforeDrag ?? currentLine, showBubble: false)
    }

    private func playCalmIdle(line: String, showBubble: Bool = false) {
        returnToIdleTimer?.invalidate()
        returnToIdleTimer = nil
        let shouldShowBubble = showBubble || persistentWorkLine != nil
        let lineToShow = persistentWorkLine ?? line
        let style = persistentWorkLine == nil ? currentBubbleStyle : persistentWorkStyle
        play(animationID: "idle_breathe", line: lineToShow, showBubble: shouldShowBubble, style: style)
        if showBubble {
            scheduleBubbleHide(after: 4.5)
        }
    }

    private func playReaction(
        animationID: String,
        line: String,
        duration: TimeInterval,
        bubbleDuration: TimeInterval? = 3.5,
        showBubble: Bool = true,
        style: BubblePresentationStyle = .compact
    ) {
        returnToIdleTimer?.invalidate()
        play(animationID: animationID, line: line, showBubble: showBubble, style: style)
        if let bubbleDuration, showBubble {
            scheduleBubbleHide(after: bubbleDuration)
        } else if showBubble {
            bubbleHideTimer?.invalidate()
            bubbleHideTimer = nil
        }
        returnToIdleTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playCalmIdle(line: self.persistentWorkLine ?? self.currentLine, showBubble: false)
            }
        }
    }

    private func requestInteraction(
        _ event: PetInteractionEvent,
        animationID: String,
        duration: TimeInterval,
        bubbleDuration: TimeInterval
    ) {
        let context = persistentWorkLine ?? currentLine
        personality.interactionLine(for: event, context: context) { [weak self] line in
            Task { @MainActor in
                guard let self, self.dragAnimationID == nil else { return }
                if event == .hover, self.isHovering == false { return }
                let style = PetBubbleComposer.style(for: line)
                self.currentLine = line.text
                self.currentBubbleStyle = style
                self.currentStatus = nil
                self.visibleStatus = nil
                self.playReaction(
                    animationID: animationID,
                    line: line.text,
                    duration: duration,
                    bubbleDuration: bubbleDuration,
                    style: style
                )
                if line.text.isEmpty == false {
                    self.onBubbleLine?(line.text)
                }
            }
        }
    }

    private func canRunInteraction(_ event: PetInteractionEvent, cooldown: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastInteractionAt[event], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastInteractionAt[event] = now
        return true
    }

    private func reactionDuration(for mood: PetMood) -> TimeInterval {
        switch mood {
        case .idle:                return 0
        case .happy, .caring:      return 3.8
        case .nod:                 return 2.0
        case .shrug:               return 2.5
        case .thinking:            return 5.2
        case .working:             return 7.0
        case .waiting, .concerned: return 5.5
        case .sleepy, .worried:    return 8.0
        }
    }

    private func bubbleDuration(for mood: PetMood) -> TimeInterval {
        switch mood {
        case .idle:                          return 4.0
        case .happy, .caring, .nod, .shrug:  return 3.2
        case .thinking, .working, .waiting,
             .sleepy, .concerned, .worried:  return 4.0
        }
    }

    private func scheduleBubbleHide(after seconds: TimeInterval) {
        bubbleHideTimer?.invalidate()
        bubbleHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideBubble()
            }
        }
    }

    private func hideBubble() {
        bubbleHideTimer?.invalidate()
        bubbleHideTimer = nil
        guard persistentWorkLine == nil else {
            visibleLine = persistentWorkLine
            visibleStatus = currentStatus
            visibleBubbleStyle = persistentWorkStyle
            renderCurrentFrame()
            return
        }
        visibleLine = nil
        visibleStatus = nil
        visibleBubbleStyle = .compact
        renderCurrentFrame()
    }

    // MARK: - Wandering

    private func scheduleNextWander() {
        wanderTimer?.invalidate()
        guard persistentWorkLine == nil else { return }
        let delay = TimeInterval.random(in: 480...720)  // 8-12 min
        wanderTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.startWander() }
        }
    }

    private func startWander() {
        guard persistentWorkLine == nil,
              dragAnimationID == nil,
              isHovering == false,
              isWandering == false,
              currentAnimation?.spec.id == "idle_breathe"
        else {
            scheduleNextWander()
            return
        }

        let dx = CGFloat.random(in: -90...90)
        guard abs(dx) > 24 else { scheduleNextWander(); return }

        isWandering = true
        wanderRemaining = abs(dx)
        wanderDX = dx
        let animID = dx < 0 ? "walk_left" : "walk_right"
        play(animationID: animID, line: currentLine, showBubble: persistentWorkLine != nil)

        let stepSize: CGFloat = 2.5
        let stepInterval: TimeInterval = 0.05

        wanderStepTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isWandering, self.dragAnimationID == nil else {
                    self.wanderStepTimer?.invalidate()
                    self.wanderStepTimer = nil
                    self.isWandering = false
                    self.scheduleNextWander()
                    return
                }
                let step = min(stepSize, self.wanderRemaining)
                self.window.moveBy(dx: self.wanderDX < 0 ? -step : step)
                self.wanderRemaining -= step
                if self.wanderRemaining <= 0 {
                    self.wanderStepTimer?.invalidate()
                    self.wanderStepTimer = nil
                    self.isWandering = false
                    self.playCalmIdle(line: self.currentLine, showBubble: false)
                    self.scheduleNextWander()
                }
            }
        }
    }

    private func scheduleStartupGreeting() {
        let gap = memory.timeSinceLastSession()
        memory.recordSessionStart()
        guard let gap, let gapNote = NomiPersonality.sessionGapNote(gap) else { return }

        let useWakeUp = gap > 14400  // show wake_up animation if away > 4 h
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.dragAnimationID == nil else { return }
                if useWakeUp {
                    self.playReaction(animationID: "wake_up", line: "", duration: 1.2, showBubble: false)
                }
                let delay: TimeInterval = useWakeUp ? 1.2 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.personality.interactionLine(for: .hover, context: gapNote) { [weak self] line in
                        Task { @MainActor in
                            guard let self else { return }
                            self.currentLine = line.text
                            self.currentBubbleStyle = .dynamic
                            self.playReaction(
                                animationID: line.mood.animationID,
                                line: line.text,
                                duration: self.reactionDuration(for: line.mood),
                                bubbleDuration: 5.0,
                                style: .dynamic
                            )
                            if line.text.isEmpty == false {
                                self.onBubbleLine?(line.text)
                            }
                        }
                    }
                }
            }
        }
    }

    private func scheduleNextAmbientEvent() {
        ambientEventTimer?.invalidate()
        ambientEventTimer = nil
        guard persistentWorkLine == nil else { return }

        let delay = TimeInterval.random(in: 75...150)
        ambientEventTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerAmbientEvent()
            }
        }
    }

    private func triggerAmbientEvent() {
        defer { scheduleNextAmbientEvent() }
        guard persistentWorkLine == nil,
              dragAnimationID == nil,
              isHovering == false,
              currentAnimation?.spec.id == "idle_breathe"
        else {
            return
        }

        if canRunInteraction(.ambient, cooldown: 90) {
            requestInteraction(.ambient, animationID: "wave", duration: 3.8, bubbleDuration: 3.8)
        } else {
            let event = personality.randomAmbientEvent()
            currentStatus = nil
            visibleStatus = nil
            memory.append(type: .observation, content: "糯米自言自语：「\(event.line)」")
            playReaction(
                animationID: event.animationID,
                line: event.line,
                duration: event.duration,
                bubbleDuration: event.bubbleDuration
            )
            if event.line.isEmpty == false {
                onBubbleLine?(event.line)
            }
        }
    }

    private func play(
        animationID: String,
        line: String,
        showBubble: Bool,
        style: BubblePresentationStyle = .compact
    ) {
        guard let animation = store.animation(id: animationID) ?? store.animation(id: "idle_breathe") else {
            return
        }

        currentAnimation = animation
        currentLine = line
        currentBubbleStyle = style
        visibleLine = showBubble ? line : nil
        visibleStatus = showBubble ? currentStatus : nil
        visibleBubbleStyle = showBubble ? style : .compact
        frameIndex = 0
        frameTimer?.invalidate()
        renderCurrentFrame()

        let fps = effectiveFPS(for: animation)
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    private func advanceFrame() {
        guard let animation = currentAnimation else { return }
        frameIndex += 1
        if frameIndex >= animation.frames.count {
            if animation.spec.loop {
                frameIndex = 0
            } else {
                playCalmIdle(line: currentLine, showBubble: false)
                return
            }
        }
        renderCurrentFrame()
    }

    private func effectiveFPS(for animation: LoadedAnimation) -> Int {
        switch animation.spec.id {
        case "idle_breathe":
            return 3
        case "look_around":
            return 5
        default:
            return max(1, animation.spec.fps)
        }
    }

    private func renderCurrentFrame() {
        guard let animation = currentAnimation, animation.frames.indices.contains(frameIndex) else {
            return
        }
        window.update(image: animation.frames[frameIndex], line: visibleLine, status: visibleStatus, style: visibleBubbleStyle)
    }
}
