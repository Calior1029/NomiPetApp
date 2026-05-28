import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let deepSeekConfig: DeepSeekConfigStore
    private let slider = NSSlider(
        value: 1.0,
        minValue: Double(SettingsStore.minPetScale),
        maxValue: Double(SettingsStore.maxPetScale),
        target: nil,
        action: nil
    )
    private let valueLabel = NSTextField(labelWithString: "100%")
    private let bubbleScaleSlider = NSSlider(
        value: 1.0,
        minValue: Double(SettingsStore.minBubbleScale),
        maxValue: Double(SettingsStore.maxBubbleScale),
        target: nil,
        action: nil
    )
    private let bubbleScaleLabel = NSTextField(labelWithString: "100%")
    private let bubbleXSlider = NSSlider(
        value: 0,
        minValue: Double(SettingsStore.minBubbleOffsetX),
        maxValue: Double(SettingsStore.maxBubbleOffsetX),
        target: nil,
        action: nil
    )
    private let bubbleXLabel = NSTextField(labelWithString: "0")
    private let bubbleYSlider = NSSlider(
        value: 0,
        minValue: Double(SettingsStore.minBubbleOffsetY),
        maxValue: Double(SettingsStore.maxBubbleOffsetY),
        target: nil,
        action: nil
    )
    private let bubbleYLabel = NSTextField(labelWithString: "0")
    private let titleFontSlider = NSSlider(
        value: Double(SettingsStore.defaultBubbleTitleFontSize),
        minValue: Double(SettingsStore.minBubbleTitleFontSize),
        maxValue: Double(SettingsStore.maxBubbleTitleFontSize),
        target: nil,
        action: nil
    )
    private let titleFontLabel = NSTextField(labelWithString: "\(Int(SettingsStore.defaultBubbleTitleFontSize))")
    private let bodyFontSlider = NSSlider(
        value: Double(SettingsStore.defaultBubbleBodyFontSize),
        minValue: Double(SettingsStore.minBubbleBodyFontSize),
        maxValue: Double(SettingsStore.maxBubbleBodyFontSize),
        target: nil,
        action: nil
    )
    private let bodyFontLabel = NSTextField(labelWithString: "\(Int(SettingsStore.defaultBubbleBodyFontSize))")
    private let lineSpacingSlider = NSSlider(
        value: Double(SettingsStore.defaultBubbleLineSpacing),
        minValue: Double(SettingsStore.minBubbleLineSpacing),
        maxValue: Double(SettingsStore.maxBubbleLineSpacing),
        target: nil,
        action: nil
    )
    private let lineSpacingLabel = NSTextField(labelWithString: "\(Int(SettingsStore.defaultBubbleLineSpacing))")
    private let textPaddingSlider = NSSlider(
        value: Double(SettingsStore.defaultBubbleTextPadding),
        minValue: Double(SettingsStore.minBubbleTextPadding),
        maxValue: Double(SettingsStore.maxBubbleTextPadding),
        target: nil,
        action: nil
    )
    private let textPaddingLabel = NSTextField(labelWithString: "\(Int(SettingsStore.defaultBubbleTextPadding))")
    private let codexCheckbox = NSButton(checkboxWithTitle: "监听 Codex 项目进度", target: nil, action: nil)
    private let claudeCheckbox = NSButton(checkboxWithTitle: "监听 Claude 项目进度", target: nil, action: nil)
    private let loginItemCheckbox = NSButton(checkboxWithTitle: "开机时自动启动 Nomi", target: nil, action: nil)
    private let personalityControl = NSSegmentedControl(labels: ["克制", "正常", "粘人"], trackingMode: .selectOne, target: nil, action: nil)
    private let profileScrollView = NSScrollView()
    private let profileTextView = NSTextView()
    private let baseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let apiStatusLabel = NSTextField(labelWithString: "")

    init(settings: SettingsStore, deepSeekConfig: DeepSeekConfigStore) {
        self.settings = settings
        self.deepSeekConfig = deepSeekConfig

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 620),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Nomi 设置"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false

        super.init(window: panel)
        buildContent()
        syncFromSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        syncFromSettings()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)

        let title = NSTextField(labelWithString: "桌宠大小")
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "调整 Nomi 在桌面上的显示尺寸")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        [bubbleScaleLabel, bubbleXLabel, bubbleYLabel, titleFontLabel, bodyFontLabel, lineSpacingLabel, textPaddingLabel].forEach {
            $0.alignment = .right
            $0.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            $0.widthAnchor.constraint(equalToConstant: 48).isActive = true
        }

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        bubbleScaleSlider.isContinuous = true
        bubbleScaleSlider.target = self
        bubbleScaleSlider.action = #selector(bubbleScaleChanged)
        bubbleXSlider.isContinuous = true
        bubbleXSlider.target = self
        bubbleXSlider.action = #selector(bubbleXChanged)
        bubbleYSlider.isContinuous = true
        bubbleYSlider.target = self
        bubbleYSlider.action = #selector(bubbleYChanged)
        titleFontSlider.isContinuous = true
        titleFontSlider.target = self
        titleFontSlider.action = #selector(titleFontChanged)
        bodyFontSlider.isContinuous = true
        bodyFontSlider.target = self
        bodyFontSlider.action = #selector(bodyFontChanged)
        lineSpacingSlider.isContinuous = true
        lineSpacingSlider.target = self
        lineSpacingSlider.action = #selector(lineSpacingChanged)
        textPaddingSlider.isContinuous = true
        textPaddingSlider.target = self
        textPaddingSlider.action = #selector(textPaddingChanged)

        let sliderRow = NSStackView(views: [slider, valueLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 12
        sliderRow.alignment = .centerY
        sliderRow.setHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let resetButton = NSButton(title: "恢复默认", target: self, action: #selector(resetSize))
        resetButton.bezelStyle = .rounded

        let separator = NSBox()
        separator.boxType = .separator

        let bubbleTitle = NSTextField(labelWithString: "气泡")
        bubbleTitle.font = .systemFont(ofSize: 14, weight: .semibold)

        let bubbleSubtitle = NSTextField(labelWithString: "调整气泡大小和位置，不影响小人点击区")
        bubbleSubtitle.font = .systemFont(ofSize: 12)
        bubbleSubtitle.textColor = .secondaryLabelColor

        let bubbleScaleTitle = NSTextField(labelWithString: "大小")
        bubbleScaleTitle.font = .systemFont(ofSize: 12)
        let titleFontTitle = NSTextField(labelWithString: "标题")
        titleFontTitle.font = .systemFont(ofSize: 12)
        let bodyFontTitle = NSTextField(labelWithString: "正文")
        bodyFontTitle.font = .systemFont(ofSize: 12)
        let lineSpacingTitle = NSTextField(labelWithString: "行距")
        lineSpacingTitle.font = .systemFont(ofSize: 12)
        let textPaddingTitle = NSTextField(labelWithString: "边距")
        textPaddingTitle.font = .systemFont(ofSize: 12)
        let bubbleXTitle = NSTextField(labelWithString: "左右")
        bubbleXTitle.font = .systemFont(ofSize: 12)
        let bubbleYTitle = NSTextField(labelWithString: "上下")
        bubbleYTitle.font = .systemFont(ofSize: 12)

        let bubbleScaleRow = makeSliderRow(label: bubbleScaleTitle, slider: bubbleScaleSlider, valueLabel: bubbleScaleLabel)
        let titleFontRow = makeSliderRow(label: titleFontTitle, slider: titleFontSlider, valueLabel: titleFontLabel)
        let bodyFontRow = makeSliderRow(label: bodyFontTitle, slider: bodyFontSlider, valueLabel: bodyFontLabel)
        let lineSpacingRow = makeSliderRow(label: lineSpacingTitle, slider: lineSpacingSlider, valueLabel: lineSpacingLabel)
        let textPaddingRow = makeSliderRow(label: textPaddingTitle, slider: textPaddingSlider, valueLabel: textPaddingLabel)
        let bubbleXRow = makeSliderRow(label: bubbleXTitle, slider: bubbleXSlider, valueLabel: bubbleXLabel)
        let bubbleYRow = makeSliderRow(label: bubbleYTitle, slider: bubbleYSlider, valueLabel: bubbleYLabel)

        let bubbleStack = NSStackView(views: [bubbleTitle, bubbleSubtitle, bubbleScaleRow, titleFontRow, bodyFontRow, lineSpacingRow, textPaddingRow, bubbleXRow, bubbleYRow])
        bubbleStack.orientation = .vertical
        bubbleStack.spacing = 8
        bubbleStack.alignment = .leading

        let separator2 = NSBox()
        separator2.boxType = .separator

        let monitorTitle = NSTextField(labelWithString: "项目进度")
        monitorTitle.font = .systemFont(ofSize: 14, weight: .semibold)

        let monitorSubtitle = NSTextField(labelWithString: "Nomi 会读取最近活跃项目并给出轻提示")
        monitorSubtitle.font = .systemFont(ofSize: 12)
        monitorSubtitle.textColor = .secondaryLabelColor

        codexCheckbox.target = self
        codexCheckbox.action = #selector(codexToggled)
        claudeCheckbox.target = self
        claudeCheckbox.action = #selector(claudeToggled)

        let monitorStack = NSStackView(views: [monitorTitle, monitorSubtitle, codexCheckbox, claudeCheckbox])
        monitorStack.orientation = .vertical
        monitorStack.spacing = 8
        monitorStack.alignment = .leading

        let separator3 = NSBox()
        separator3.boxType = .separator

        let companionTitle = NSTextField(labelWithString: "陪伴感")
        companionTitle.font = .systemFont(ofSize: 14, weight: .semibold)

        let companionSubtitle = NSTextField(labelWithString: "调整 Nomi 说话时的亲近程度")
        companionSubtitle.font = .systemFont(ofSize: 12)
        companionSubtitle.textColor = .secondaryLabelColor

        personalityControl.segmentStyle = .rounded
        personalityControl.target = self
        personalityControl.action = #selector(personalityChanged)
        personalityControl.selectedSegment = settings.personalityIntensity.rawValue
        personalityControl.widthAnchor.constraint(equalToConstant: 210).isActive = true

        let companionStack = NSStackView(views: [companionTitle, companionSubtitle, personalityControl])
        companionStack.orientation = .vertical
        companionStack.spacing = 8
        companionStack.alignment = .leading

        let separator4 = NSBox()
        separator4.boxType = .separator

        // MARK: 了解主人 section
        let profileTitle = NSTextField(labelWithString: "了解主人")
        profileTitle.font = .systemFont(ofSize: 14, weight: .semibold)

        let profileSubtitle = NSTextField(wrappingLabelWithString: "告诉糯米一些你的基本情况，帮她更了解你。和她聊天后她会自己学到更多，那些会优先参考。")
        profileSubtitle.font = .systemFont(ofSize: 12)
        profileSubtitle.textColor = .secondaryLabelColor

        let profilePlaceholder = NSTextField(wrappingLabelWithString: "例：我是个程序员，喜欢深夜工作，有时候会忘记喝水。最近在做一个 iOS 游戏。")
        profilePlaceholder.font = .systemFont(ofSize: 11)
        profilePlaceholder.textColor = NSColor.tertiaryLabelColor

        profileTextView.font = .systemFont(ofSize: 12)
        profileTextView.isEditable = true
        profileTextView.isSelectable = true
        profileTextView.isRichText = false
        profileTextView.allowsUndo = true
        profileTextView.textContainerInset = NSSize(width: 6, height: 6)
        profileTextView.isVerticallyResizable = true
        profileTextView.isHorizontallyResizable = false

        profileScrollView.borderType = .bezelBorder
        profileScrollView.hasVerticalScroller = true
        profileScrollView.hasHorizontalScroller = false
        profileScrollView.documentView = profileTextView
        profileScrollView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        profileScrollView.translatesAutoresizingMaskIntoConstraints = false

        let saveProfileButton = NSButton(title: "保存", target: self, action: #selector(saveFoundation))
        saveProfileButton.bezelStyle = .rounded
        saveProfileButton.controlSize = .small

        let profileStack = NSStackView(views: [profileTitle, profileSubtitle, profilePlaceholder, profileScrollView, saveProfileButton])
        profileStack.orientation = .vertical
        profileStack.spacing = 8
        profileStack.alignment = .leading

        let separator5 = NSBox()
        separator5.boxType = .separator

        let apiTitle = NSTextField(labelWithString: "DeepSeek API")
        apiTitle.font = .systemFont(ofSize: 14, weight: .semibold)

        let apiSubtitle = NSTextField(labelWithString: "配置对话生成接口")
        apiSubtitle.font = .systemFont(ofSize: 12)
        apiSubtitle.textColor = .secondaryLabelColor

        [baseURLField, apiKeyField, modelField].forEach {
            $0.font = .systemFont(ofSize: 12)
            $0.controlSize = .small
            $0.usesSingleLineMode = true
        }
        baseURLField.placeholderString = DeepSeekConfigFile.defaultBaseURL
        apiKeyField.placeholderString = "sk-..."
        modelField.placeholderString = DeepSeekConfigFile.defaultModel

        apiStatusLabel.font = .systemFont(ofSize: 12)
        apiStatusLabel.textColor = .secondaryLabelColor

        let saveAPIButton = NSButton(title: "保存 API 配置", target: self, action: #selector(saveAPIConfig))
        saveAPIButton.bezelStyle = .rounded

        let apiButtonRow = NSStackView(views: [saveAPIButton, apiStatusLabel])
        apiButtonRow.orientation = .horizontal
        apiButtonRow.spacing = 10
        apiButtonRow.alignment = .centerY

        let apiStack = NSStackView(views: [
            apiTitle,
            apiSubtitle,
            makeFieldRow(title: "Base URL", field: baseURLField),
            makeFieldRow(title: "API Key", field: apiKeyField),
            makeFieldRow(title: "Model", field: modelField),
            apiButtonRow
        ])
        apiStack.orientation = .vertical
        apiStack.spacing = 8
        apiStack.alignment = .leading

        let separator6 = NSBox()
        separator6.boxType = .separator

        let systemTitle = NSTextField(labelWithString: "系统")
        systemTitle.font = .systemFont(ofSize: 14, weight: .semibold)

        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(loginItemToggled)

        let systemStack = NSStackView(views: [systemTitle, loginItemCheckbox])
        systemStack.orientation = .vertical
        systemStack.spacing = 8
        systemStack.alignment = .leading

        let stack = NSStackView(views: [title, subtitle, sliderRow, resetButton, separator, bubbleStack, separator2, monitorStack, separator3, companionStack, separator4, profileStack, separator5, apiStack, separator6, systemStack])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator3.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator4.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator5.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator6.widthAnchor.constraint(equalTo: stack.widthAnchor),
            profileScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 210)
        ])
    }

    private func syncFromSettings() {
        deepSeekConfig.reload()
        slider.doubleValue = Double(settings.petScale)
        bubbleScaleSlider.doubleValue = Double(settings.bubbleScale)
        bubbleXSlider.doubleValue = Double(settings.bubbleOffsetX)
        bubbleYSlider.doubleValue = Double(settings.bubbleOffsetY)
        titleFontSlider.doubleValue = Double(settings.bubbleTitleFontSize)
        bodyFontSlider.doubleValue = Double(settings.bubbleBodyFontSize)
        lineSpacingSlider.doubleValue = Double(settings.bubbleLineSpacing)
        textPaddingSlider.doubleValue = Double(settings.bubbleTextPadding)
        codexCheckbox.state = settings.monitorCodex ? .on : .off
        claudeCheckbox.state = settings.monitorClaude ? .on : .off
        loginItemCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        personalityControl.selectedSegment = settings.personalityIntensity.rawValue
        let apiConfig = deepSeekConfig.config
        baseURLField.stringValue = apiConfig.baseURL
        apiKeyField.stringValue = apiConfig.apiKey
        modelField.stringValue = apiConfig.model
        apiStatusLabel.stringValue = apiConfig.apiKey.isEmpty ? "未配置" : "已配置"
        profileTextView.string = settings.userFoundation
        updateValueLabel()
        updateBubbleLabels()
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int(round(slider.doubleValue * 100)))%"
    }

    private func updateBubbleLabels() {
        bubbleScaleLabel.stringValue = "\(Int(round(bubbleScaleSlider.doubleValue * 100)))%"
        titleFontLabel.stringValue = "\(Int(round(titleFontSlider.doubleValue)))"
        bodyFontLabel.stringValue = "\(Int(round(bodyFontSlider.doubleValue)))"
        lineSpacingLabel.stringValue = "\(Int(round(lineSpacingSlider.doubleValue)))"
        textPaddingLabel.stringValue = "\(Int(round(textPaddingSlider.doubleValue)))"
        bubbleXLabel.stringValue = "\(Int(round(bubbleXSlider.doubleValue)))"
        bubbleYLabel.stringValue = "\(Int(round(bubbleYSlider.doubleValue)))"
    }

    private func makeSliderRow(label: NSTextField, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        label.widthAnchor.constraint(equalToConstant: 36).isActive = true
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        let row = NSStackView(views: [label, slider, valueLabel])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func makeFieldRow(title: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    @objc private func sliderChanged() {
        settings.petScale = CGFloat(slider.doubleValue)
        updateValueLabel()
    }

    @objc private func resetSize() {
        settings.reset()
        syncFromSettings()
    }

    @objc private func bubbleScaleChanged() {
        settings.bubbleScale = CGFloat(bubbleScaleSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func bubbleXChanged() {
        settings.bubbleOffsetX = CGFloat(bubbleXSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func bubbleYChanged() {
        settings.bubbleOffsetY = CGFloat(bubbleYSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func titleFontChanged() {
        settings.bubbleTitleFontSize = CGFloat(titleFontSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func bodyFontChanged() {
        settings.bubbleBodyFontSize = CGFloat(bodyFontSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func lineSpacingChanged() {
        settings.bubbleLineSpacing = CGFloat(lineSpacingSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func textPaddingChanged() {
        settings.bubbleTextPadding = CGFloat(textPaddingSlider.doubleValue)
        updateBubbleLabels()
    }

    @objc private func codexToggled() {
        settings.monitorCodex = codexCheckbox.state == .on
    }

    @objc private func claudeToggled() {
        settings.monitorClaude = claudeCheckbox.state == .on
    }

    @objc private func personalityChanged() {
        settings.personalityIntensity = PersonalityIntensity(rawValue: personalityControl.selectedSegment) ?? .normal
    }

    @objc private func loginItemToggled() {
        let enable = loginItemCheckbox.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently revert — most likely running outside an app bundle during development.
            loginItemCheckbox.state = enable ? .off : .on
        }
    }

    @objc private func saveFoundation() {
        settings.userFoundation = profileTextView.string
    }

    @objc private func saveAPIConfig() {
        do {
            try deepSeekConfig.update(
                apiKey: apiKeyField.stringValue,
                baseURL: baseURLField.stringValue,
                model: modelField.stringValue
            )
            let apiConfig = deepSeekConfig.config
            baseURLField.stringValue = apiConfig.baseURL
            apiKeyField.stringValue = apiConfig.apiKey
            modelField.stringValue = apiConfig.model
            apiStatusLabel.stringValue = apiConfig.apiKey.isEmpty ? "已清空" : "已保存"
        } catch {
            apiStatusLabel.stringValue = "保存失败"
        }
    }
}
