import AppKit

@MainActor
final class ChatWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let deepSeek: DeepSeekClient
    private let memory: MemoryStore
    private let userMemory: UserMemoryStore
    private let settings: SettingsStore
    private var messages: [ChatMessage] = []
    private var isWaiting = false
    private var lastExtractionCount = 0   // message count at last fact extraction
    private var lastCompressionCount = 0  // message count at last session summary
    /// Bubble lines queued while the panel is hidden, injected on next open.
    private var pendingBubbleLines: [String] = []

    // Persisted history
    private static let maxPersistedMessages = 60
    private static let historyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".nomi-pet/chat_history.json")

    private let historyTextView: NSTextView
    private let historyScrollView: NSScrollView
    private let inputField: NSTextField
    private let sendButton: NSButton
    private let statusLabel: NSTextField

    var onNomiResponse: ((AIResponse) -> Void)?

    // MARK: - Bubble line bridge

    /// Called by PetController whenever the pet shows a line in a bubble.
    /// If the chat panel is open the line appears immediately; otherwise it queues until next open.
    func receiveBubbleLine(_ line: String) {
        if panel.isVisible {
            injectBubbleLine(line)
        } else {
            pendingBubbleLines.append(line)
        }
    }

    // MARK: - Init

    init(deepSeek: DeepSeekClient, memory: MemoryStore, userMemory: UserMemoryStore, settings: SettingsStore) {
        self.deepSeek = deepSeek
        self.memory = memory
        self.userMemory = userMemory
        self.settings = settings

        // Panel
        let panelSize = NSSize(width: 320, height: 480)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 260, height: 360)

        // History text view
        historyScrollView = NSScrollView()
        historyTextView = NSTextView()
        inputField = NSTextField()
        sendButton = NSButton()
        statusLabel = NSTextField(labelWithString: "")

        super.init()
        buildUI()

        // Restore previous conversation so the AI remembers past sessions
        let saved = Self.loadPersistedHistory()
        if saved.isEmpty == false {
            messages = saved
            lastExtractionCount = saved.count   // don't re-extract already-processed facts
            lastCompressionCount = saved.count  // don't re-summarize old sessions
        }
    }

    // MARK: - Show / Toggle

    func show(near petWindowFrame: NSRect) {
        flushPendingBubbleLines()
        positionPanel(near: petWindowFrame)
        panel.makeKeyAndOrderFront(nil)
        updateTextContainerWidth()
    }

    func toggle(near petWindowFrame: NSRect) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(near: petWindowFrame)
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in self.updateTextContainerWidth() }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.persistHistory()
            self.triggerFactExtraction()
            self.compressSession()
        }
    }

    // MARK: - Text container width sync

    private func updateTextContainerWidth() {
        let w = historyScrollView.documentVisibleRect.width
        guard w > 0 else { return }
        historyTextView.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
        historyTextView.frame = NSRect(x: 0, y: 0, width: w, height: historyTextView.frame.height)
    }

    // MARK: - Build UI

    private func buildUI() {
        panel.title = "和糯米聊天"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.97)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        guard let contentView = panel.contentView else { return }

        // History scroll view
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false
        historyScrollView.hasVerticalScroller = true
        historyScrollView.borderType = .noBorder
        historyScrollView.backgroundColor = .clear
        historyScrollView.drawsBackground = false

        historyTextView.isEditable = false
        historyTextView.isSelectable = true
        historyTextView.backgroundColor = .clear
        historyTextView.drawsBackground = false
        historyTextView.textContainerInset = NSSize(width: 12, height: 12)
        historyTextView.font = NSFont.systemFont(ofSize: 13)
        historyTextView.textColor = .white
        // Grow vertically with content, wrap horizontally at view width
        historyTextView.isVerticallyResizable = true
        historyTextView.isHorizontallyResizable = false
        historyTextView.autoresizingMask = [.width]
        historyTextView.minSize = NSSize(width: 0, height: 0)
        historyTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        historyTextView.textContainer?.widthTracksTextView = true
        // Don't hardcode width here — updateTextContainerWidth() sets it after layout

        historyScrollView.documentView = historyTextView
        contentView.addSubview(historyScrollView)

        // Separator line
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12)
        contentView.addSubview(separator)

        // Status label (shows "糯米正在回复…")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        statusLabel.stringValue = ""
        contentView.addSubview(statusLabel)

        // Input field
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "和糯米说点什么…"
        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.isBordered = false
        inputField.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        inputField.textColor = .white
        inputField.focusRingType = .none
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 8
        inputField.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        (inputField.cell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
        contentView.addSubview(inputField)

        // Send button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = "发送"
        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .regular
        sendButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        sendButton.contentTintColor = .white
        sendButton.wantsLayer = true
        sendButton.layer?.backgroundColor = NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.72, alpha: 1).cgColor
        sendButton.layer?.cornerRadius = 8
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(handleSend)
        contentView.addSubview(sendButton)

        // Constraints
        NSLayoutConstraint.activate([
            historyScrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 36),
            historyScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            historyScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            historyScrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),
            separator.heightAnchor.constraint(equalToConstant: 1),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            statusLabel.bottomAnchor.constraint(equalTo: inputField.topAnchor, constant: -6),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),

            inputField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            inputField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            inputField.heightAnchor.constraint(equalToConstant: 34),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 58),
            sendButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        // Return key in input field triggers send
        inputField.target = self
        inputField.action = #selector(handleSend)

        // Opening message
        appendLine(role: .nomi, text: NomiPersonality.openingLine)
    }

    // MARK: - Send

    @objc private func handleSend() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, isWaiting == false else { return }

        inputField.stringValue = ""
        isWaiting = true
        sendButton.isEnabled = false

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        appendLine(role: .user, text: text)

        statusLabel.stringValue = "糯米正在回复…"

        let historyForAPI = messages.dropLast()
        let ctx = GenerationContext(
            memorySummary: memory.contextSummary(),
            runningApps: RunningAppsReader.userFacingApps(),
            timeDescription: NomiPersonality.timeDescription(),
            taskDurationDescription: "",
            situationNotes: [],
            userProfileSummary: userMemory.profileSummary()
        )

        deepSeek.chat(
            history: Array(historyForAPI),
            userMessage: text,
            context: ctx,
            intensity: settings.personalityIntensity
        ) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.statusLabel.stringValue = ""
                self.isWaiting = false
                self.sendButton.isEnabled = true

                let replyText = response?.line ?? "嗯…（糯米有点迷糊，主人再说一次？）"
                let nomiMsg = ChatMessage(role: .nomi, content: replyText)
                self.messages.append(nomiMsg)
                self.appendLine(role: .nomi, text: replyText)
                self.persistHistory()

                if let r = response {
                    self.onNomiResponse?(r)
                }

                // Periodic extraction: every 8 messages (4 exchanges)
                if self.messages.count - self.lastExtractionCount >= 8 {
                    self.triggerFactExtraction()
                }
            }
        }
    }

    // MARK: - Chat history persistence

    private static func loadPersistedHistory() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: historyURL),
              let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return [] }
        return Array(msgs.suffix(maxPersistedMessages))
    }

    private func persistHistory() {
        let toSave = Array(messages.suffix(Self.maxPersistedMessages))
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        let dir = Self.historyURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.historyURL, options: .atomic)
    }

    // MARK: - Session compression (on window close)

    /// Generates a compressed summary of new messages from this session
    /// and saves it to MemoryStore as `.chatSummary` so future sessions
    /// can recall what was discussed.
    private func compressSession() {
        let newMessages = Array(messages.dropFirst(lastCompressionCount))
        guard newMessages.count >= 4, deepSeek.isConfigured else { return }
        let countSnapshot = messages.count

        deepSeek.summarizeConversation(messages: newMessages) { [weak self] summary in
            Task { @MainActor in
                guard let self, let summary, summary.isEmpty == false else { return }
                self.memory.append(type: .chatSummary, content: summary)
                self.lastCompressionCount = countSnapshot
            }
        }
    }

    // MARK: - Fact extraction (background, silent)

    private func triggerFactExtraction() {
        let newMessages = messages.dropFirst(lastExtractionCount)
        guard newMessages.count >= 2 else { return }
        lastExtractionCount = messages.count

        let snapshot = Array(newMessages)
        deepSeek.extractUserFacts(conversation: snapshot) { [weak self] facts in
            Task { @MainActor in
                guard let self, let facts, facts.isEmpty == false else { return }
                self.userMemory.merge(newFacts: facts)
            }
        }
    }

    // MARK: - Append text to history

    private func appendLine(role: ChatRole, text: String) {
        guard let storage = historyTextView.textStorage else { return }

        let isNomi = role == .nomi
        let nameColor = isNomi
            ? NSColor(calibratedRed: 0.72, green: 0.54, blue: 1.0, alpha: 1)
            : NSColor(calibratedRed: 0.46, green: 0.72, blue: 1.0, alpha: 1)
        let nameText = isNomi ? "糯米  " : "你  "

        let nameAttr = NSAttributedString(string: nameText, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: nameColor
        ])
        let bodyAttr = NSAttributedString(string: text + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1)
        ])

        let combined = NSMutableAttributedString()
        combined.append(nameAttr)
        combined.append(bodyAttr)

        storage.beginEditing()
        storage.append(combined)
        storage.endEditing()

        // Scroll to bottom
        let range = NSRange(location: storage.length, length: 0)
        historyTextView.scrollRangeToVisible(range)
    }

    // MARK: - Bubble line injection

    /// Drains the queue of bubble lines accumulated while the panel was hidden.
    private func flushPendingBubbleLines() {
        guard pendingBubbleLines.isEmpty == false else { return }
        let lines = pendingBubbleLines
        pendingBubbleLines = []
        for line in lines {
            injectBubbleLine(line)
        }
    }

    /// Appends a Nomi bubble line into the chat UI and message history.
    /// Skips the injection if the line is already the last Nomi message to avoid duplicates.
    private func injectBubbleLine(_ line: String) {
        let alreadyLast = messages.last.map { $0.role == .nomi && $0.content == line } ?? false
        guard alreadyLast == false else { return }
        let msg = ChatMessage(role: .nomi, content: line)
        messages.append(msg)
        appendLine(role: .nomi, text: line)
    }

    // MARK: - Positioning

    private func positionPanel(near petFrame: NSRect) {
        let panelWidth = panel.frame.width
        var x = petFrame.minX - panelWidth - 10
        let y = petFrame.minY

        // If no room on the left, try right side
        if let screen = NSScreen.main {
            if x < screen.visibleFrame.minX {
                x = petFrame.maxX + 10
            }
            if x + panelWidth > screen.visibleFrame.maxX {
                x = screen.visibleFrame.maxX - panelWidth - 10
            }
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
