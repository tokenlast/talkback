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
Latest run: 344 Python tests, zero failures, one skipped; 16 native tests passed.

The native tests cover silence/stability, configurable pause, replacement of
volatile speech results, final-only submission, repeated consumption, future
segments, discarding oversized conversation without executing a suffix, built-in
microphone defaults, stable device identity, and refusing an unavailable input.
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
In the final run, finalization took 16–48 ms after accelerated fixture delivery.
These are not microphone-to-Live latency measurements and exclude the configured
pause. This test caught an audio-timestamp-overlap defect: input now uses the
analyzer's exact contiguous frame timeline, not rounded timestamps.

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
