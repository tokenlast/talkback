# Talkback

Always-available, local voice control for Ableton Live on macOS.

Say “turn that one up 3 dB,” pause, and Talkback acts on the selected track.
Speech recognition runs on-device. Familiar commands use deterministic local
controls; no API key is needed. An optional cloud interpreter is off by default.

**Development preview:** save your Live set before trying hands-free control.
This is not speaker identification: music, videos, or another person saying an
accepted command can trigger it. An optional opening phrase reduces accidental
activation, but does not authenticate the speaker.

## Requirements and installation

Apple Silicon, macOS 26+, Xcode 26+ / Swift 6.2, Homebrew Python 3.13, and Ableton
Live 12. Tested locally with Live 12.2 Suite. Apple speech assets may need an
initial download; recognition subsequently runs locally.

See [INSTALL.md](INSTALL.md) for build and setup. Source is published; a signed,
notarized Talkback binary release has not been published.

## Using it

- Launch Talkback once. It stays in the menu bar; closing its window does not quit.
- Listening is enabled by default. Turn it off with the menu bar **Listening**
  toggle. Enable **Launch at login** in Settings for future logins.
- By default, commands act only while Live is in front.
  Switching applications during a phrase discards that phrase.
- Pause to send; listening continues for the next command. New installs default
  to 0.7 seconds. Settings accepts 0.1–10 seconds and preserves your saved choice.
- **⌘⇧Space** toggles listening without a floating bar. Advanced settings can
  change the shortcut to send the current phrase instead. The menu also offers
  Send current phrase and Discard current phrase.
- Results and errors stay in the menu; they never steal focus from Live.
- “Start recording” defaults to **Arrangement**; Settings can switch it to Session.
  Explicit “start arrangement recording” and “start session recording” override that setting.
- The main settings show listening, microphone, shortcut, and pause. **Advanced** holds recording
  destination, quiet threshold, opening phrase, automatic submission, foreground
  restriction, shortcut action, login, custom commands, connection setup, and cloud use.

[All supported commands and custom phrase examples](COMMANDS.md).

## Your own phrases, without code

Settings → Custom commands accepts a plain-text list:

```text
bring it forward => turn this track up 3 dB
quiet please => mute this track
my synth => throw Serum on a new track in Instruments
ready to go => arm this track and start recording
```

Exact phrase matching ignores case and final punctuation. Mappings select existing
local controls, not arbitrary code. No shell execution, recursive expansion, or
cloud fallback is allowed for a custom mapping. The file is stored separately
from source at `~/Library/Application Support/Talkback/commands.txt`.

## Privacy and boundaries

Talkback chooses the Mac's built-in microphone by default, independently of the
system or Ableton audio-interface selection. Choose a different input in Settings.
An unavailable selected device does not silently fall back to another microphone.

Audio and ambient transcripts are not saved by Talkback or sent to its cloud
interpreter. The speech model and command-admission filter run on the Mac.
Rejected conversation is discarded. Operational/error logs contain microphone
state, not ambient transcripts.

If you explicitly enable cloud interpretation, accepted commands and the Live
context needed to interpret them (including names) may be sent to TypeSafe.
The key is stored in macOS Keychain. Apple downloads its speech assets separately.
Custom mappings always stay on the local interpretation path.

The Live control surface binds to `127.0.0.1:9140`. It accepts a fixed allow-list,
not arbitrary Python or shell commands. Other local processes can connect to this
port: loopback is not an authentication boundary. Do not expose it to a network.

## Reliability and limits

- Hands-free admission is currently English; inherited typed commands also support Japanese.
- The endpoint uses an adjustable sound threshold, not speaker separation.
  Loud continuous playback may delay automatic submission. A close microphone or
  headphones helps; Send current phrase is the manual override.
- Commands wait for a final recognition result, never just an unstable partial.
- Track names and targets are checked before writes. Missing targets do not fall
  back to another track.
- Compatible multi-action commands are planned before writes. Runtime rollback
  is attempted, and failures are reported; this is not an atomic Live transaction.
- There is no “zero latency” promise: the selected pause, final recognition, Live's
  response, and plug-in loading all contribute. Plug-ins can take substantially longer.
  Arrangement recording also respects Live's configured count-in.
- Hardware or speech-engine interruptions discard the phrase and retry with
  backoff while Listening remains enabled. Settings shows the error. Quitting
  the app or turning Listening off stops the microphone and retries.

See [QA.md](QA.md) for test scope and reproducible checks.

## Development

```sh
python3 -m unittest discover -q
cd Talkback && swift test
# From the repository root:
bash scripts/build-app.sh
```

The app bundles its Python sources and control script. Python code changes require
rebuilding/reopening the app. Control-script changes require updating it in Settings
and restarting Live.

The action registry is `actions.py`; fixed phrase parsers are `intent_en.py` and
`intent.py`. New kinds of operations require implementation, allow-list review,
and tests. Plain-text mappings intentionally cannot bypass these boundaries.

## Credits and license

Talkback is a fork of [Okina Audio's Live Jev](https://github.com/okinaaudio/live-jev),
not an official upstream release. Git history and the original copyright are
preserved. Talkback adds continuous on-device speech, local command filtering,
configurable settings and phrase mappings, Arrangement recording, and a new UI.

MIT licensed. See [LICENSE](LICENSE).
