# Talkback macOS app

Swift 6.2 / macOS 26+ menu-bar app with Apple's on-device SpeechAnalyzer.

`Onboarding.swift` presents the Web1-style settings and Live setup checks.
`SettingsEditor.swift` edits operational preferences and the plain-text command list.
`DictationController.swift` owns the continuous audio stream and final-result boundary.
`VoiceState.swift` contains the testable endpoint and transcript state.
`Panel.swift` restricts command dispatch to the configured application context.
`DaemonClient.swift` starts the bundled Python service over stdin/stdout.

Audio and ambient text are not logged or persisted. The desktop app starts the
daemon in local-only mode unless cloud interpretation is explicitly enabled.
Optional keys use macOS Keychain service `es.charlieyat.talkback`.

Run `swift test` here, or `bash scripts/build-app.sh` from the repository root.
See the root [installation guide](../INSTALL.md) and [command reference](../COMMANDS.md).
