# Install Talkback

## Build from source

You need Apple Silicon, macOS 26 or newer, Xcode 26 / Swift 6.2, Homebrew Python
3.13, and Ableton Live 12. No TypeSafe account or API key is required for local use.

```sh
git clone https://github.com/tokenlast/talkback.git
cd talkback
python3 -m unittest discover -q
bash scripts/build-app.sh
open "$HOME/Applications/Talkback.app"
```

The local build is ad-hoc signed, not a notarized public binary. The build script
keeps the previous installed app as `~/dev/talkback-build/stage.noindex/previous/Talkback.app` and
moves older generated artifacts to Trash. The app bundles the daemon source;
it does not need the source checkout to stay in place.

## Connect Ableton

1. Open Talkback's menu-bar menu → **Settings…**.
2. Under Install the Live control script, select **Install**. If your User Library
   is elsewhere, select that library first.
3. In Live → Settings → Link, Tempo & MIDI, choose **Talkback** in a Control Surface
   slot. Leave Input and Output as None.
4. Restart Live. Settings should show the connection as ready.

If upgrading from the original project, disable its old control-surface slot
before enabling Talkback. Do not run two scripts on port 9140. Keep the old app or
script as a backup, but quit the old app so it does not own the same shortcut.

## Configure listening

Allow Talkback's microphone request. The first start may download Apple's local
speech model. No Accessibility permission is required for the command shortcut.

Listening remains on until disabled. The menu bar's Listening checkbox reflects
the preference; Settings shows whether the engine is actually listening or has
encountered an error. Enable **Launch at login** and save preferences to restart it
automatically at future logins.

Defaults: English recognition, one-second pause, quiet threshold −48 dB,
Arrangement recording, no opening phrase, foreground-only actions, ⌘⇧Space.
Settings lets you change these behaviors. The language menu controls the interface;
English is currently required for hands-free command admission.

A required opening phrase such as “Talkback” reduces false activations. Any voice
or recording can still say it. Start with a disposable set, especially around loud
music or open speakers. Turn Listening off when you do not want voice control.

## Custom commands

Open Settings → Custom commands. Enter one `phrase => command` per line and select
**Save preferences**. The “All supported commands” link opens the bundled reference.

The format is validated on save. Actual action, target, plug-in, and clip validity
is checked against the current set when the command runs. Mappings are not code
and never use cloud fallback. External edits to the plain-text command file are
picked up on the next command.

## Optional cloud interpretation

Leave this off for entirely local command handling. If you choose to enable it,
enter your TypeSafe key yourself in Settings; it is stored in Keychain. Accepted
commands and relevant Live names can then leave the Mac. Audio remains local.

The command-line daemon is also local by default. An explicitly enabled cloud
CLI uses `TALKBACK_LOCAL_ONLY=0`; do not put keys in source, examples, or commits.

## Checks and troubleshooting

```sh
python3 plugin_script.py ping
TALKBACK_LOCAL_ONLY=1 python3 cli.py status
```

- No connection: confirm Talkback is the enabled control surface, restart Live,
  and check for another process using port 9140.
- No speech: check Microphone permission and Settings' status. Toggle Listening
  off/on after changing audio hardware or a speech error.
- No automatic submission during music: adjust the quiet threshold or use
  headphones/a closer mic; open the command bar and press Return.
- No shortcut: try the menu's Show command bar, then choose another shortcut in Settings.
- No plug-in: confirm it is installed and visible in Live's browser. Ambiguous
  names need a more specific name.
- No recording: check the recording destination and armed tracks. Talkback does
  not silently arm tracks you did not request.

Logs: `~/Library/Logs/Talkback.log`. Preferences use `es.charlieyat.talkback`.
Custom commands: `~/Library/Application Support/Talkback/commands.txt`.

## Uninstall

Disable Launch at login, switch Listening off, and quit Talkback. Set its Live
Control Surface slot to None, then move Talkback.app and
`User Library/Remote Scripts/Talkback` to Trash. Keep your command file if you
want to reinstall later. An optional saved cloud key can be removed in Settings.
