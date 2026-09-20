import AppKit
import Darwin

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class Onboarding: NSObject, NSWindowDelegate {
    private enum State { case pending, ok, problem }
    private let viewModel: ViewModel
    private let voice: PanelController
    private let preferences = SettingsEditor()
    private let listeningButton = NSButton(checkboxWithTitle: "Listening", target: nil, action: nil)
    private let cloudButton = NSButton(checkboxWithTitle: "Use cloud interpretation for unfamiliar commands", target: nil, action: nil)
    private let voiceLabel = NSTextField(wrappingLabelWithString: "")
    private let connectionLabel = NSTextField(labelWithString: "Checking Live…")
    private let window: NSWindow
    private var timer: Timer?
    private var states: [State] = [.pending, .pending, .pending, .pending]
    private var glyphs: [NSImageView] = []
    private var titles: [NSTextField] = []
    private var helps: [NSTextField] = []
    private var buttons: [(NSButton, AppText.Key)] = []
    private let keyField = NSSecureTextField()
    private var installButton: NSButton!
    private var removeButton: NSButton!
    private var doneButton: NSButton!
    private var hasKey = false
    private var keyFailed = false
    private var liveStatus: StatusMessage?
    private var connectionProblem: String?
    private var installProblem = false
    private var tried = false
    private var checking = false
    private var tryLine: String?

    init(viewModel: ViewModel, voice: PanelController) {
        self.viewModel = viewModel
        self.voice = voice
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 360)
        build()
        viewModel.onSetupMessage = { [weak self] message in self?.receive(message) }
        viewModel.onSetupConnection = { [weak self] line in
            guard let self, self.window.isVisible else { return }
            self.liveStatus = nil
            self.connectionProblem = line
            self.checking = false
            if self.tried { self.tryLine = line }
            self.refresh()
        }
        updateLocalizedText()
    }

    private func text(_ key: AppText.Key) -> String { viewModel.text(key) }

    func show() {
        preferences.reload()
        readKey()
        liveStatus = nil
        connectionProblem = nil
        tried = false
        checking = false
        tryLine = nil
        refresh()
        window.center()
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        keyField.stringValue = ""
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    func windowDidDeminiaturize(_ notification: Notification) { startPolling() }

    private func startPolling() {
        timer?.invalidate()
        viewModel.pollSetupStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.window.isVisible, !self.window.isMiniaturized else { return }
                self.viewModel.pollSetupStatus()
            }
        }
    }

    private func build() {
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        let material = SettingsDocumentView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = material
        window.contentView = scroll
        material.translatesAutoresizingMaskIntoConstraints = false
        material.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: material.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -24)
        ])
        let heading = NSTextField(labelWithString: "Talkback")
        heading.font = NSFont(name: "Helvetica", size: 28)
        stack.addArrangedSubview(heading)
        listeningButton.target = self
        listeningButton.action = #selector(toggleListening)
        listeningButton.font = NSFont(name: "Helvetica", size: 14)
        voiceLabel.font = NSFont(name: "Helvetica", size: 12)
        connectionLabel.font = NSFont(name: "Helvetica", size: 12)
        let voiceStack = NSStackView(views: [listeningButton, voiceLabel, connectionLabel])
        voiceStack.orientation = .vertical
        voiceStack.alignment = .leading
        voiceStack.spacing = 8
        stack.addArrangedSubview(voiceStack)
        voiceLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(preferences)
        preferences.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        preferences.onAdvancedChange = { [weak self] expanded in
            self?.window.setContentSize(NSSize(width: 560, height: expanded ? 760 : 460))
        }
        for index in 0..<4 {
            let glyph = NSImageView()
            glyph.setAccessibilityElement(true)
            glyph.widthAnchor.constraint(equalToConstant: 20).isActive = true
            glyph.heightAnchor.constraint(equalToConstant: 20).isActive = true
            glyphs.append(glyph)
            let title = NSTextField(labelWithString: "")
            title.font = NSFont(name: "Helvetica", size: 14)
            titles.append(title)
            let help = NSTextField(wrappingLabelWithString: "")
            help.font = NSFont(name: "Helvetica", size: 12)
            help.textColor = .black
            helps.append(help)
            let body = NSStackView(views: [title, help])
            body.orientation = .vertical
            body.alignment = .leading
            body.spacing = 8
            let row = NSStackView(views: [glyph, body])
            row.alignment = .top
            row.spacing = 12
            preferences.advancedContent.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            help.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            switch index {
            case 0:
                installButton = button(.install, #selector(installScript))
                body.addArrangedSubview(NSStackView(views: [installButton, button(.chooseLibrary, #selector(chooseLibrary), secondary: true)]))
            case 2:
                cloudButton.target = self
                cloudButton.action = #selector(toggleCloud)
                cloudButton.font = NSFont(name: "Helvetica", size: 13)
                body.addArrangedSubview(cloudButton)
                keyField.font = NSFont(name: "Helvetica", size: 13)
                keyField.widthAnchor.constraint(equalToConstant: 290).isActive = true
                body.addArrangedSubview(NSStackView(views: [keyField, button(.saveKey, #selector(saveKey))]))
                removeButton = button(.removeKey, #selector(removeKey), secondary: true)
                body.addArrangedSubview(NSStackView(views: [button(.getKey, #selector(getKey), secondary: true), removeButton]))
            case 3:
                body.addArrangedSubview(button(.tryIt, #selector(tryConnection)))
            default: break
            }
        }
        let footer = NSStackView()
        let spacer = NSView()
        doneButton = button(.finishLater, #selector(finish))
        doneButton.keyEquivalent = "\r"
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(doneButton)
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func button(_ key: AppText.Key, _ action: Selector, secondary: Bool = false) -> NSButton {
        let button = NSButton(title: text(key), target: self, action: action)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = NSFont(name: "Helvetica", size: 13)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel(text(key))
        buttons.append((button, key))
        return button
    }

    func updateLocalizedText() {
        window.title = "Talkback Settings"
        for (button, key) in buttons {
            button.title = text(key)
            button.setAccessibilityLabel(text(key))
        }
        for (index, key) in [AppText.Key.installScript, .selectLive, .addKey, .tryIt].enumerated() {
            titles[index].stringValue = text(key)
        }
        titles[2].stringValue = "Cloud interpretation · optional"
        keyField.setAccessibilityLabel(text(.addKey))
        keyField.setAccessibilityHelp(text(.keyHelp))
        refresh()
    }

    private var library: URL {
        if let path = UserDefaults.standard.string(forKey: "TalkbackUserLibrary") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Ableton/User Library")
    }

    private var destination: URL { library.appendingPathComponent("Remote Scripts/Talkback") }

    private func version(in folder: URL) -> String? {
        guard let content = try? String(contentsOf: folder.appendingPathComponent("Talkback.py"), encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"["']version["']\s*:\s*["']([^"']+)["']"#),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[range])
    }

    private func readKey() {
        guard UserDefaults.standard.bool(forKey: "TalkbackAllowJev") else { hasKey = false; keyFailed = false; return }
        do {
            hasKey = try Keychain.read() != nil
            keyFailed = false
        } catch { hasKey = false; keyFailed = true }
    }

    private func refresh() {
        preferences.refreshMicrophones()
        refreshVoice()
        let sourceVersion = version(in: DaemonClient.remoteScriptSource)
        let installedVersion = version(in: destination)
        let exists = FileManager.default.fileExists(atPath: destination.path)
        let older = installedVersion.map { $0.compare(sourceVersion ?? "", options: .numeric) == .orderedAscending } ?? false
        states[0] = sourceVersion != nil && sourceVersion == installedVersion ? .ok : (exists || sourceVersion == nil ? .problem : .pending)
        helps[0].stringValue = text(installProblem ? .installFailed : sourceVersion == nil ? .scriptProblem : states[0] == .ok ? .installed : exists ? (installedVersion == nil ? .scriptProblem : older ? .olderScript : .differentScript) : .missingScript)
        if installProblem { states[0] = .problem }
        installButton.title = text(exists ? .update : .install)
        installButton.setAccessibilityLabel(installButton.title)
        installButton.isEnabled = sourceVersion != nil && states[0] != .ok
        installButton.toolTip = destination.path
        states[1] = liveStatus?.live == true ? .ok : (liveStatus != nil || connectionProblem != nil ? .problem : .pending)
        connectionLabel.stringValue = states[1] == .ok ? "Connected to Live · on-device speech" : "Live not connected — open Advanced"
        helps[1].stringValue = text(.selectLiveHelp)
        let cloud = UserDefaults.standard.bool(forKey: "TalkbackAllowJev")
        states[2] = !cloud || hasKey || liveStatus?.jev == true ? .ok : (keyFailed ? .problem : .pending)
        helps[2].stringValue = cloud ? "Accepted commands and Live context may be sent to TypeSafe. Audio stays local." : "Off. No API key needed for local commands."
        keyField.isEnabled = cloud
        removeButton.isHidden = !hasKey
        states[3] = tried && !checking ? (liveStatus?.live == true && connectionProblem == nil ? .ok : .problem) : .pending
        helps[3].stringValue = tryLine ?? text(.tryHelp)
        for index in 0..<4 {
            let state = states[index]
            let symbol = state == .ok ? "checkmark.circle.fill" : state == .problem ? "exclamationmark.circle" : "circle.dotted"
            let label = text(state == .ok ? .ready : state == .problem ? .problem : .pending)
            glyphs[index].image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            glyphs[index].contentTintColor = state == .pending ? .tertiaryLabelColor : .labelColor
            glyphs[index].setAccessibilityLabel("\(titles[index].stringValue): \(label)")
        }
        doneButton.title = text(states.prefix(2).allSatisfy { $0 == .ok } ? .done : .finishLater)
        doneButton.setAccessibilityLabel(doneButton.title)
    }

    func refreshVoice() {
        listeningButton.state = voice.listeningEnabled ? .on : .off
        voiceLabel.stringValue = voice.voiceStatus
        cloudButton.state = UserDefaults.standard.bool(forKey: "TalkbackAllowJev") ? .on : .off
    }

    @objc private func toggleListening() { voice.setListening(listeningButton.state == .on) }

    @objc private func toggleCloud() {
        UserDefaults.standard.set(cloudButton.state == .on, forKey: "TalkbackAllowJev")
        keyChanged()
    }

    private func receive(_ message: DaemonMessage) {
        guard window.isVisible else { return }
        switch message {
        case .status(let status):
            checking = false
            liveStatus = status
            connectionProblem = nil
            if tried { tryLine = status.line }
        case .error(let error) where error.id?.hasPrefix("setup-") == true:
            checking = false
            connectionProblem = error.line
            liveStatus = nil
            if tried { tryLine = error.line }
        default: return
        }
        refresh()
    }

    @objc private func installScript() {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".Talkback-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            defer { if manager.fileExists(atPath: temporary.path) { try? manager.trashItem(at: temporary, resultingItemURL: nil) } }
            try manager.copyItem(at: DaemonClient.remoteScriptSource, to: temporary)
            guard version(in: temporary) != nil else { throw CocoaError(.fileReadCorruptFile) }
            if manager.fileExists(atPath: destination.path) {
                // Exchange siblings so Live never sees a partially copied script folder.
                guard renamex_np(temporary.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
            installProblem = false
        } catch { installProblem = true }
        refresh()
    }

    @objc private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = library
        panel.prompt = text(.chooseLibrary)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            UserDefaults.standard.set(url.path, forKey: "TalkbackUserLibrary")
            self.installProblem = false
            self.refresh()
        }
    }

    @objc private func saveKey() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try Keychain.save(key)
            keyField.stringValue = ""
            keyChanged()
        } catch { keyFailed = true; refresh() }
    }

    @objc private func removeKey() {
        do {
            try Keychain.delete()
            keyField.stringValue = ""
            keyChanged()
        } catch { keyFailed = true; refresh() }
    }

    private func keyChanged() {
        readKey()
        liveStatus = nil
        connectionProblem = nil
        tryLine = nil
        tried = false
        checking = false
        refresh()
        viewModel.restartDaemon()
    }

    @objc private func getKey() {
        NSWorkspace.shared.open(URL(string: "https://typesafe.ai")!)
    }

    @objc private func tryConnection() {
        tried = true
        checking = true
        tryLine = text(.checkingLive)
        refresh()
        viewModel.pollSetupStatus()
    }

    @objc private func finish() {
        UserDefaults.standard.set(true, forKey: "TalkbackSetupDone")
        window.close()
    }
}
