import AppKit
import ServiceManagement

@MainActor
final class SettingsEditor: NSStackView {
    let advancedContent = NSStackView()
    var onAdvancedChange: ((Bool) -> Void)?
    private let advancedButton = NSButton(title: "▸ Advanced", target: nil, action: nil)
    private let recording = NSPopUpButton()
    private let shortcut = NSPopUpButton()
    private let microphone = NSPopUpButton()
    private var microphoneUIDs: [String] = []
    private var availableMicrophones: [Microphone] = []
    private let shortcutAction = NSPopUpButton()
    private let pause = NSTextField()
    private let noise = NSTextField()
    private let wake = NSTextField()
    private let autoSubmit = NSButton(checkboxWithTitle: "Send after a pause", target: nil, action: nil)
    private let liveOnly = NSButton(checkboxWithTitle: "Only act while Ableton is in front", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let commands = NSTextView()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var loadedCommands: String?
    private let shortcutKeys = ["commandShiftSpace", "commandOptionSpace", "controlOptionSpace", "disabled"]

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 12
        let defaults = UserDefaults.standard
        reloadMicrophones(uid: defaults.string(forKey: "TalkbackMicrophoneUID") ?? "")
        recording.addItems(withTitles: ["Arrangement timeline", "Session clips"])
        recording.selectItem(at: defaults.string(forKey: "TalkbackRecordingMode") == "session" ? 1 : 0)
        shortcut.addItems(withTitles: ["⌘⇧Space", "⌘⌥Space", "⌃⌥Space", "Off"])
        shortcut.selectItem(at: shortcutKeys.firstIndex(of: defaults.string(forKey: "TalkbackShortcut") ?? "commandShiftSpace") ?? 0)
        shortcutAction.addItems(withTitles: ["Toggle listening", "Send current phrase"])
        shortcutAction.selectItem(at: defaults.string(forKey: "TalkbackShortcutAction") == "send" ? 1 : 0)
        pause.stringValue = String(format: "%.1f", TalkbackSettings.pause)
        noise.stringValue = String(format: "%.0f", TalkbackSettings.noiseFloor)
        wake.stringValue = defaults.string(forKey: "TalkbackWakePhrase") ?? ""
        wake.placeholderString = "None — e.g. Talkback"
        autoSubmit.state = TalkbackSettings.autoSubmit ? .on : .off
        liveOnly.state = TalkbackSettings.liveOnly ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        addRow("Microphone", microphone)
        addRow("Listening shortcut", shortcut)
        addRow("Pause (0.1–10 seconds)", pause)
        addArrangedSubview(label("Keeps listening after each command."))
        advancedButton.target = self
        advancedButton.action = #selector(toggleAdvanced)
        advancedButton.isBordered = false
        advancedButton.font = NSFont(name: "Helvetica", size: 13)
        advancedButton.setAccessibilityLabel("Advanced settings")
        addArrangedSubview(advancedButton)
        advancedContent.orientation = .vertical
        advancedContent.alignment = .leading
        advancedContent.spacing = 12
        advancedContent.isHidden = true
        addArrangedSubview(advancedContent)
        advancedContent.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        addRow("“Start recording” means", recording, to: advancedContent)
        addRow("Shortcut action", shortcutAction, to: advancedContent)
        advancedContent.addArrangedSubview(login)
        advancedContent.addArrangedSubview(liveOnly)
        advancedContent.addArrangedSubview(autoSubmit)
        addRow("Quiet threshold (dB)", noise, to: advancedContent)
        addRow("Opening phrase", wake, to: advancedContent)
        advancedContent.addArrangedSubview(label("Quiet threshold: −70 to −15 dB. Any voice or recording saying a command can trigger it."))
        advancedContent.addArrangedSubview(label("Custom commands", size: 18))
        advancedContent.addArrangedSubview(label("Exact phrase => supported command. Local only."))
        commands.isRichText = false
        commands.isAutomaticQuoteSubstitutionEnabled = false
        commands.isAutomaticDashSubstitutionEnabled = false
        commands.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        commands.textColor = .black
        commands.backgroundColor = .white
        commands.isVerticallyResizable = true
        commands.autoresizingMask = [.width]
        commands.textContainer?.widthTracksTextView = true
        loadedCommands = try? String(contentsOf: TalkbackSettings.commandsURL, encoding: .utf8)
        commands.string = loadedCommands ?? TalkbackSettings.commandExample
        commands.setAccessibilityLabel("Custom commands")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.documentView = commands
        advancedContent.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        commands.frame = NSRect(x: 0, y: 0, width: 520, height: 160)
        let save = bareButton("Save preferences", #selector(save))
        let reference = bareButton("All supported commands", #selector(openReference))
        advancedContent.addArrangedSubview(reference)
        addArrangedSubview(save)
        feedback.font = NSFont(name: "Helvetica", size: 12)
        addArrangedSubview(feedback)
        for control in [autoSubmit, liveOnly, login] { control.font = NSFont(name: "Helvetica", size: 13) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat = 12) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont(name: "Helvetica", size: size)
        label.textColor = .black
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
        return label
    }

    private func addRow(_ title: String, _ control: NSControl, to container: NSStackView? = nil) {
        control.font = NSFont(name: "Helvetica", size: 13)
        control.setAccessibilityLabel(title)
        let titleLabel = label(title, size: 13)
        titleLabel.widthAnchor.constraint(equalToConstant: 185).isActive = true
        let row = NSStackView(views: [titleLabel, control])
        row.spacing = 16
        control.widthAnchor.constraint(equalToConstant: control === wake ? 260 : control is NSPopUpButton ? 210 : 75).isActive = true
        (container ?? self).addArrangedSubview(row)
    }

    @objc private func toggleAdvanced() {
        advancedContent.isHidden.toggle()
        advancedButton.title = advancedContent.isHidden ? "▸ Advanced" : "▾ Advanced"
        onAdvancedChange?(!advancedContent.isHidden)
    }

    func refreshMicrophones() {
        guard availableMicrophones != Microphones.inputs else { return }
        let index = microphone.indexOfSelectedItem
        reloadMicrophones(uid: microphoneUIDs.indices.contains(index) ? microphoneUIDs[index] : "")
    }

    private func reloadMicrophones(uid: String) {
        availableMicrophones = Microphones.inputs
        microphone.removeAllItems()
        microphone.addItem(withTitle: availableMicrophones.first(where: { $0.builtIn })?.name ?? "Built-in mic unavailable")
        microphoneUIDs = [""]
        for input in availableMicrophones where !input.builtIn {
            microphone.addItem(withTitle: input.name)
            microphoneUIDs.append(input.uid)
        }
        if !microphoneUIDs.contains(uid) {
            microphone.addItem(withTitle: "Selected mic unavailable")
            microphoneUIDs.append(uid)
        }
        microphone.selectItem(at: microphoneUIDs.firstIndex(of: uid) ?? 0)
    }

    private func bareButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = NSFont(name: "Helvetica", size: 13)
        return button
    }

    @objc private func save() {
        let disk = try? String(contentsOf: TalkbackSettings.commandsURL, encoding: .utf8)
        guard disk == loadedCommands else { feedback.stringValue = "The command file changed outside Talkback. Reopen Settings before saving."; return }
        guard let seconds = Double(pause.stringValue), seconds.isFinite, TalkbackSettings.pauseRange.contains(seconds),
              let decibels = Double(noise.stringValue), decibels.isFinite, (-70 ... -15).contains(decibels),
              wake.stringValue.count <= 80 else {
            feedback.stringValue = "Check the pause, quiet threshold, and opening phrase (80 characters maximum)."
            return
        }
        guard commands.string.utf8.count <= 65536 else { feedback.stringValue = "Command list exceeds 64 KB."; return }
        var seen = Set<String>()
        for (index, line) in commands.string.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let pieces = trimmed.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty, pieces[0].count <= 200, pieces[1].count <= 500 else {
                feedback.stringValue = "Line \(index + 1): use phrase => supported command."; return
            }
            let key = pieces[0].lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".! "))
            guard seen.insert(key).inserted else { feedback.stringValue = "Line \(index + 1): duplicate phrase."; return }
        }
        do {
            try FileManager.default.createDirectory(at: TalkbackSettings.commandsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try commands.string.write(to: TalkbackSettings.commandsURL, atomically: true, encoding: .utf8)
            loadedCommands = commands.string
            if login.state == .on && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if login.state == .off && SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            let defaults = UserDefaults.standard
            defaults.set(microphoneUIDs[microphone.indexOfSelectedItem], forKey: "TalkbackMicrophoneUID")
            defaults.set(recording.indexOfSelectedItem == 1 ? "session" : "arrangement", forKey: "TalkbackRecordingMode")
            defaults.set(shortcutKeys[shortcut.indexOfSelectedItem], forKey: "TalkbackShortcut")
            defaults.set(shortcutAction.indexOfSelectedItem == 1 ? "send" : "toggle", forKey: "TalkbackShortcutAction")
            defaults.set(seconds, forKey: "TalkbackPause")
            defaults.set(decibels, forKey: "TalkbackNoiseFloor")
            defaults.set(wake.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "TalkbackWakePhrase")
            defaults.set(autoSubmit.state == .on, forKey: "TalkbackAutoSubmit")
            defaults.set(liveOnly.state == .on, forKey: "TalkbackLiveOnly")
            NotificationCenter.default.post(name: TalkbackSettings.changed, object: nil)
            feedback.stringValue = SMAppService.mainApp.status == .requiresApproval ? "Saved. Approve Talkback in System Settings → Login Items." : "Saved."
        } catch { feedback.stringValue = "Could not save: \(error.localizedDescription)" }
    }

    @objc private func openReference() {
        if let url = Bundle.main.url(forResource: "COMMANDS", withExtension: "md") { NSWorkspace.shared.open(url) }
    }

    func reload() {
        let defaults = UserDefaults.standard
        reloadMicrophones(uid: defaults.string(forKey: "TalkbackMicrophoneUID") ?? "")
        recording.selectItem(at: defaults.string(forKey: "TalkbackRecordingMode") == "session" ? 1 : 0)
        shortcut.selectItem(at: shortcutKeys.firstIndex(of: defaults.string(forKey: "TalkbackShortcut") ?? "commandShiftSpace") ?? 0)
        shortcutAction.selectItem(at: defaults.string(forKey: "TalkbackShortcutAction") == "send" ? 1 : 0)
        pause.stringValue = String(format: "%.1f", TalkbackSettings.pause)
        noise.stringValue = String(format: "%.0f", TalkbackSettings.noiseFloor)
        wake.stringValue = defaults.string(forKey: "TalkbackWakePhrase") ?? ""
        autoSubmit.state = TalkbackSettings.autoSubmit ? .on : .off
        liveOnly.state = TalkbackSettings.liveOnly ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loadedCommands = try? String(contentsOf: TalkbackSettings.commandsURL, encoding: .utf8)
        commands.string = loadedCommands ?? TalkbackSettings.commandExample
        feedback.stringValue = ""
    }
}
