# Talkback verification

Development-preview checks on Apple Silicon, macOS 26, Ableton Live 12.2 Suite.
Do not equate an automated build with physical-microphone or production-set proof.

## Automated checks

```sh
python3 -m unittest discover -q
cd Talkback && swift test
```

Python coverage includes the local grammar, target checks, undo/rollback, socket
protocol, voice admission, command mappings, recording modes, and group-placement
guards. One inherited test is skipped because the upstream private publishing
script is intentionally absent from the public repository.
Latest Python run: 352 tests, zero failures, one skipped. Last native run: 21 tests passed.

The reported phrase “Can you start a new track in instruments?” is covered through
voice admission, local parsing, daemon dispatch, and a mocked Live group-creation
surface. Polite question punctuation is accepted; general questions, negations,
missing/duplicate groups, and unavailable group-aware control surfaces stay safe.
The installed parser previously rejected the question mark or treated “start a
new” as a plug-in name. This regression is fixed without changing the speech engine.
These mocked checks are not physical-microphone-to-Live proof. Continuous human
speech-command execution remains an open real-world acceptance issue.

The native tests cover silence/stability, configurable pause, replacement of
volatile speech results, final-only submission, repeated consumption, future
segments, discarding oversized conversation without executing a suffix, built-in
microphone defaults, stable device identity, and refusing an unavailable input.
They also cover finalization watermarks for unchanged partial results, invalid and
cross-boundary watermarks, silence-only punctuation, and microphone RMS thresholds.
The recognizer now honors consumed-result watermarks instead of requiring every
partial to arrive again with `isFinal`. Closed input/result streams trigger recovery
rather than silently leaving the listener inactive. These fixes address concrete
failure paths; they do not prove the cause of every previously observed timeout.
The supplied-logo checks lock the screenshot's Display P3 orange, black-only menu
ink in both listening states, the app icon's retained white keyline, padded
grayscale-mask decoding, and fixed menu dimensions. Edge coverage is antialiased;
no shading or drop shadow is added.

## Real local speech model, synthetic input

```sh
say -v Samantha -o /tmp/talkback-speech-fixture.aiff \
  'Mute this track and solo this track. [[slnc 2000]]'
xcrun swiftc -parse-as-library -target arm64-apple-macos26.0 \
  scripts/continuous_speech_smoke.swift \
  Talkback/Sources/Talkback/DictationController.swift \
  Talkback/Sources/Talkback/Microphones.swift \
  Talkback/Sources/Talkback/VoiceState.swift \
  Talkback/Sources/Talkback/TalkbackSettings.swift \
  Talkback/Sources/Talkback/Messages.swift \
  Talkback/Sources/Talkback/Log.swift \
  -o /tmp/talkback-speech-smoke
/tmp/talkback-speech-smoke /tmp/talkback-speech-fixture.aiff
```

Twenty consecutive fixture phrases passed through a single on-device analyzer.
In the watermark-fix run, finalization took 17–47 ms after accelerated fixture delivery.
These are not microphone-to-Live latency measurements and exclude the configured
pause. This test caught an audio-timestamp-overlap defect: input now uses the
analyzer's exact contiguous frame timeline, not rounded timestamps.

### Short-command recognition repair (September 21)

The previous `SpeechTranscriber` configuration misrecognized a synthetic
“Add Operator” and returned punctuation-only results on subsequent repetitions.
Both fast and normal-accuracy modes failed this short-phrase fixture. The new
`DictationTranscriber` uses on-device short-form recognition, volatile previews,
and frequent finalization. Dispatch still requires final results and foreground
admission; uncertain previews are never executed as a fallback.

Music-vocabulary context is supplied through `AnalysisContext`, without replacing
recognized words in the command parser. Without these hints, the alternate engine
misheard “solo” as “so” in repeated compound commands. With the hints, twenty
consecutive “Mute this track and solo this track” fixtures passed at real-time
delivery, including an explicit finalization request at about 0.7 seconds of silence
while the remaining audio continued streaming. This is synthetic recognition proof,
not a measurement of human-microphone-to-Live latency.

The smoke harness accepts `--realtime`, `--pause-boundary`, `--operator` (five short
Operator commands), or `--expected 'fixture text'` (five exact-text checks).
Pause-boundary fixtures must end in two seconds of silence. Its raw result output
is confined to explicit synthetic fixtures; the app still never logs ambient words.

Final short-form configuration passed five real-time, pause-boundary repetitions
each of “Add Operator”, “Add Operator to a new track”, “Do not delete this track”,
and “Do not add Operator”. The local admission filter continues to reject both
negated phrases. The real-microphone stopped-engine recovery check also passed
with sustained resumed input. Python: 352 tests, one intentional skip, no failures;
native: 21 passed. Installed Developer ID signature and staged/binary equality passed.

Direct Operator insertion through the Live control surface was separately verified
with explicit permission on the selected sixth track, retaining its existing effects.
No Live edits were made during the recognition repair. Human speech through the
installed app is still a separate acceptance gate; synthetic fixtures do not prove it.

## Real Ableton, disposable set only

Open a disposable set containing a unique `LJ-TEST` marker, two additional tracks,
and a return track. Select a non-marker track. Never run regression in a project
you care about. Save the baseline first.

```sh
TALKBACK_LOCAL_ONLY=1 python3 scripts/live_regression.py --check
TALKBACK_LOCAL_ONLY=1 python3 scripts/live_regression.py --json /tmp/talkback-qa.json
```

The installed Talkback control surface v0.20 passed all 54 regression cases:
54 PASS, 0 FAIL, 0 SKIP. Local execution p50 was 80 ms and p95 was 179 ms in that
run. These measurements exclude speech recognition and the pause.

Additional real-Live checks verified spoken-number normalization through the
voice request path (track 6 from −12 dB to −2 dB) and Arrangement Record plus Play
visually on in Live. Recording respects Live's count-in; an immediate `is_playing`
read can still be false during that count-in. A follow-up integration run caught
a real defect: calling `continue_playing` while Record had already started a
count-in could stall it. Control surface v0.20 makes resume idempotent during
count-in or playback, and the full recording/transport check now passes.
This was state verification, not a recorded-audio-quality test.

`scripts/talkback_live_smoke.py` is an extra opt-in fixture-specific check for
recording and Serum inside an Instruments group. It refuses unexpected track
counts/names. After explicit permission to reset the fixture, the full extended
run passed: numbered volume, Arrangement recording, track arming, missing-group
rejection, Serum in Instruments, and grouped-track undo. End-to-end physical
speech-command execution is a separate check. Group validation and failure
cleanup are also covered by mocked Live-object tests.

A separate real-Live check passed an exact plain-text custom voice mapping and
the Session recording setting. Both recording destinations have now been checked;
these checks use the voice request protocol, not microphone recognition.

## Physical microphone check

The installed app opened the MacBook Pro's built-in microphone, explicitly bound
through CoreAudio rather than following the system input. Speaker-played “Mute
track three” passed through that microphone, the production on-device recognizer,
and the local command path; Live's mute state changed. The foreground restriction
was temporarily disabled for that isolated test and was restored afterward.

Subsequent speaker-played phrases did not change Live. Repeated physical commands
and positive foreground admission are therefore **not yet verified**; the single
pass must not be described as a full continuous-listening acceptance test. Native
UI automation subsequently became unavailable (control-server initialization
timeout), preventing further interactive diagnosis in that run. QA track mute,
solo, and recording/transport states were restored afterward.

A later user-spoken harmless probe verified nonzero built-in microphone audio,
partial and final recognition, foreground admission, and daemon receipt. The local
filter ignored this non-command as expected. A second utterance was rejected after
the foreground app changed. This verifies the input path, not a successful Live edit.
The open set subsequently changed to a separate Constellate QA project without an
Instruments group; it was left untouched. The reported track-creation phrase still
needs a physical-microphone acceptance check against the intended destination.

`--voice-diagnostics` temporarily logs only pipeline metadata (levels, timing,
character counts, admission flags, response kinds), never audio or transcript words.
It is off by default and expires after 15 minutes. Normal relaunch disables it.

Normal app relaunch exposed a separate permission failure: macOS rejected the
previous microphone approval because the ad hoc signature's code hash changed.
The build script now selects a unique available Developer ID certificate, or an
explicit `TALKBACK_SIGN_IDENTITY`. Its ad hoc fallback warns about permission loss.
The app explicitly displays a pending microphone-permission request. Switching
from an ad hoc build to certificate signing requires fresh OS consent; subsequent
certificate-signed updates retain a stable designated requirement.
The installed Developer ID signature and staged/installed binary equality passed.
The normal launch connected to Live and visibly reached “Waiting for microphone
permission…”; final microphone consent and a spoken Live edit remain user gates.

The user subsequently confirmed spoken track creation worked. A later failure
showed repeated `Microphone input interrupted` errors and audio-engine configuration
notifications. The controller now restarts a stopped, still-bound engine when its
format is unchanged, rejects recovery across an unfinished utterance, and only
reports Listening after receiving audio. Failed starts no longer reset retry backoff.
The exact phrase `add Operator to a new track` passes local voice admission and
resolves to a new MIDI track with Operator in the regression suite.

`scripts/microphone_recovery_smoke.swift` is an opt-in real-input test, compiled
with `-D DEBUG` and the same controller sources as the synthetic speech test.
Run the resulting executable with `--microphone`. It has no Live connection,
saves no audio/transcripts, simulates a stopped-engine configuration notification,
and requires resumed physical buffers plus four seconds without an input failure.
This physical recovery test passed locally; the installed signature also verified.
The test-only stop hook is excluded from release builds. Actual spoken Operator
insertion and real device-switch stress testing still require separate acceptance.

## Manual release gates

- Test real microphone → final transcript → local command → Live readback.
- Repeat independent phrases; test Send current phrase, Discard, shortcut, and Off.
- Confirm unrelated speech, negations, and other foreground apps cannot write.
- Exercise a custom mapping, both recording destinations, and missing targets.
- Verify grouped plug-in insertion and undo in a clean disposable set.
- Test prolonged music playback, sleep/wake, input-device changes, and login.
- Recheck installed app signature, bundled modules, and source/binary privacy.

The installed settings UI and launch-at-login registration have been exercised.
Notarized packaging and reboot/login behavior have not been verified for this preview.
