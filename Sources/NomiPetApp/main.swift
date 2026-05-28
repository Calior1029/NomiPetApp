import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var chatWindow: ChatWindowController?
    private var petWindow: PetWindowController?
    private var appMonitor: AppLaunchMonitor?
    private var sleepMonitor: ScreenSleepMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if another NomiPetApp is already running, quit immediately.
        let bundleID = Bundle.main.bundleIdentifier ?? "app.nomi.desktop-pet"
        let duplicate = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if duplicate != nil {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        do {
            let settings = SettingsStore()
            let store = try AnimationStore()
            let memory = MemoryStore()
            let window = PetWindowController(settings: settings)
            let monitor = ProgressMonitor(settings: settings)
            let deepSeekConfig = DeepSeekConfigStore()
            let deepSeek = DeepSeekClient()
            let patterns = UsagePatternStore()
            let userMemory = UserMemoryStore()
            let personality = PersonalityEngine(deepSeek: deepSeek, settings: settings, memory: memory, patterns: patterns, userMemory: userMemory)
            let chat = ChatWindowController(deepSeek: deepSeek, memory: memory, userMemory: userMemory, settings: settings)

            settingsWindow = SettingsWindowController(settings: settings, deepSeekConfig: deepSeekConfig)
            chatWindow = chat
            petWindow = window

            window.onOpenSettings = { [weak self] in
                self?.settingsWindow?.show()
            }
            window.onOpenChat = { [weak self] in
                guard let self, let chatWin = self.chatWindow, let petWin = self.petWindow else { return }
                chatWin.toggle(near: petWin.frame)
            }
            window.onHeadpat = { [weak controller] in
                controller?.handleRightClick()
            }
            window.onRightClick = { [weak self] in
                guard let self, let chatWin = self.chatWindow, let petWin = self.petWindow else { return }
                chatWin.toggle(near: petWin.frame)
            }
            chat.onNomiResponse = { [weak self] response in
                self?.controller?.receiveChat(response: response)
            }

            let controller = PetController(
                store: store,
                window: window,
                monitor: monitor,
                personality: personality,
                memory: memory,
                patterns: patterns
            )
            // Bubble → Chat bridge: pet's proactive bubble lines flow into the chat window
            // so the user can reply and get a contextually aware response.
            controller.onBubbleLine = { [weak chat] line in
                chat?.receiveBubbleLine(line)
            }

            let appLaunchMonitor = AppLaunchMonitor()
            appLaunchMonitor.onBurst = { [weak controller] apps in
                controller?.handleAppLaunchBurst(apps: apps)
            }
            appLaunchMonitor.start()
            self.appMonitor = appLaunchMonitor

            let screenSleepMonitor = ScreenSleepMonitor()
            screenSleepMonitor.onSleep = { [weak controller] in
                controller?.handleScreenSleep()
            }
            screenSleepMonitor.onWake = { [weak controller] duration in
                controller?.handleScreenWake(duration: duration)
            }
            screenSleepMonitor.start()
            self.sleepMonitor = screenSleepMonitor

            self.controller = controller
            controller.start()
            setupStatusItem()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Nomi 启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Nomi"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 Nomi", action: #selector(showNomi), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "和糯米聊天", action: #selector(openChat), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "刷新进度", action: #selector(refreshActivity), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func showNomi() {
        controller?.showPet()
    }

    @objc private func openChat() {
        guard let chatWin = chatWindow, let petWin = petWindow else { return }
        chatWin.toggle(near: petWin.frame)
    }

    @objc private func refreshActivity() {
        controller?.refreshActivity()
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
