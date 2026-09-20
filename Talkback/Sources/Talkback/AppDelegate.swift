import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = ViewModel()
    private var panelController: PanelController?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var onboarding: Onboarding?
    private var loginItem: NSMenuItem?
    private var listeningItem: NSMenuItem?
    private var resultItem: NSMenuItem?
    private var proposalItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["language": AppLanguage.auto.rawValue, "TalkbackListeningEnabled": true, "TalkbackAllowJev": false])
        let panelController = PanelController(viewModel: viewModel)
        self.panelController = panelController
        NSApp.mainMenu = makeMainMenu()
        configureMenuBar()
        panelController.onVoiceStateChange = { [weak self] in self?.updateVoiceState() }
        panelController.onResultChange = { [weak self] in self?.updateResult() }

        let hotKey = HotKey { [weak self] in self?.handleShortcut() }
        self.hotKey = hotKey
        do {
            try hotKey.register()
        } catch {
            Log.shared.write(error.localizedDescription)
        }

        viewModel.start()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: TalkbackSettings.changed, object: nil)
        panelController.reconcileListening()
        if !UserDefaults.standard.bool(forKey: "TalkbackSetupDone") { showSetup() }
        updateVoiceState()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stopListening()
        viewModel.stop()
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: 36)
        item.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Talkback"
        )
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        listeningItem = menu.addItem(withTitle: "Listening", action: #selector(toggleListening), keyEquivalent: "")
        listeningItem?.state = panelController?.listeningEnabled == true ? .on : .off
        resultItem = menu.addItem(withTitle: "No commands yet", action: nil, keyEquivalent: "")
        resultItem?.isEnabled = false
        menu.addItem(withTitle: "Send current phrase", action: #selector(sendCurrentPhrase), keyEquivalent: "")
        menu.addItem(withTitle: "Discard current phrase", action: #selector(discardCurrentPhrase), keyEquivalent: "")
        menu.addItem(withTitle: viewModel.text(.setup), action: #selector(showSetup), keyEquivalent: "")
        let loginItem = menu.addItem(
            withTitle: viewModel.text(.launchAtLogin),
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        self.loginItem = loginItem
        updateLoginItemState()
        menu.addItem(.separator())
        let languageItem = NSMenuItem(title: viewModel.text(.language), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: viewModel.text(.language))
        for (index, value) in AppLanguage.allCases.enumerated() {
            let key: AppText.Key = value == .auto ? .automatic : value == .ja ? .japanese : .english
            let item = languageMenu.addItem(withTitle: viewModel.text(key), action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = value == viewModel.language ? .on : .off
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = menu.addItem(withTitle: "\(viewModel.text(.version)) \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: viewModel.text(.quit), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    // Even a menu-bar-only app needs an Edit menu for Cmd-C/V/A/Z to reach its window.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: viewModel.text(.setup), action: #selector(showSetup), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(viewModel.text(.quit)) Talkback", action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: viewModel.text(.edit))
        edit.addItem(withTitle: viewModel.text(.undo), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: viewModel.text(.redo), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: viewModel.text(.cut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: viewModel.text(.copy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: viewModel.text(.paste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: viewModel.text(.selectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    @objc private func showSetup() {
        if onboarding == nil, let panelController { onboarding = Onboarding(viewModel: viewModel, voice: panelController) }
        onboarding?.show()
    }

    @objc private func toggleListening() {
        guard let panelController else { return }
        panelController.setListening(!panelController.listeningEnabled)
    }

    @objc private func settingsChanged() {
        viewModel.restartDaemon()
        panelController?.restartSpeechLanguage()
        hotKey = nil
        let replacement = HotKey { [weak self] in self?.handleShortcut() }
        do { try replacement.register(); hotKey = replacement }
        catch { Log.shared.write("Shortcut unavailable: \(error.localizedDescription)") }
        updateLoginItemState()
    }

    private func updateVoiceState() {
        guard let panelController else { return }
        listeningItem?.state = panelController.listeningEnabled ? .on : .off
        statusItem?.button?.toolTip = "Talkback — \(panelController.voiceStatus)"
        statusItem?.button?.image = Self.statusBadge(listening: panelController.listeningEnabled)
        statusItem?.button?.setAccessibilityLabel("Talkback — \(panelController.voiceStatus)")
        onboarding?.refreshVoice()
    }

    private func updateResult() {
        let line = viewModel.results.first?.line ?? "No commands yet"
        resultItem?.title = String(line.prefix(110)) + (line.count > 110 ? "…" : "")
        resultItem?.toolTip = line
        if let menu = statusItem?.menu, let resultItem {
            proposalItems.forEach { menu.removeItem($0) }
            proposalItems.removeAll()
            let latest = viewModel.results.first
            if let id = latest?.confirmationID {
                for (title, approved) in [("Confirm command", true), ("Cancel command", false)] {
                    let item = NSMenuItem(title: title, action: #selector(answerMenuConfirmation(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = id
                    item.tag = approved ? 1 : 0
                    proposalItems.append(item)
                }
            } else if latest?.kind == .ask, let id = latest?.requestID {
                for option in latest?.options ?? [] {
                    let item = NSMenuItem(title: option, action: #selector(answerMenuQuestion(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = id
                    proposalItems.append(item)
                }
            }
            for (offset, item) in proposalItems.enumerated() {
                menu.insertItem(item, at: menu.index(of: resultItem) + 1 + offset)
            }
        }
        onboarding?.refreshVoice()
    }

    @objc private func answerMenuConfirmation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        viewModel.answerConfirmation(id: id, confirmed: sender.tag == 1)
    }

    @objc private func answerMenuQuestion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              viewModel.results.first?.requestID == id else { return }
        viewModel.submit(sender.title, answering: id)
    }

    private func handleShortcut() {
        if UserDefaults.standard.string(forKey: "TalkbackShortcutAction") == "send" { sendCurrentPhrase() }
        else { toggleListening() }
    }

    @objc private func sendCurrentPhrase() { panelController?.sendCurrentPhrase() }
    @objc private func discardCurrentPhrase() { panelController?.discardCurrentPhrase() }

    private static func statusBadge(listening: Bool) -> NSImage {
        // The chosen mic artwork will replace the neutral waveform here.
        let image = NSImage(size: NSSize(width: 32, height: 20), flipped: false) { rect in
            (listening ? NSColor(calibratedRed: 1, green: 0.79, blue: 0.22, alpha: 1) : .lightGray).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
            NSColor.black.setStroke()
            for (index, height) in [CGFloat(5), 10, 7, 12, 5].enumerated() {
                let path = NSBezierPath()
                path.lineWidth = 1.6
                path.lineCapStyle = .round
                let x = CGFloat(10 + index * 3)
                path.move(to: NSPoint(x: x, y: 10 - height / 2))
                path.line(to: NSPoint(x: x, y: 10 + height / 2))
                path.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.shared.write("login item update failed: \(error.localizedDescription)")
        }
        updateLoginItemState()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard AppLanguage.allCases.indices.contains(sender.tag) else { return }
        viewModel.setLanguage(AppLanguage.allCases[sender.tag])
        NSApp.mainMenu = makeMainMenu()
        statusItem?.menu = makeStatusMenu()
        updateResult()
        panelController?.updateLocalizedText()
        panelController?.restartSpeechLanguage()
        onboarding?.updateLocalizedText()
    }

    private func updateLoginItemState() {
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
