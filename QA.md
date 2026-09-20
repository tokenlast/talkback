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

The native tests cover silence/stability, configurable pause, replacement of
volatile speech results, final-only submission, repeated consumption, future
segments, and discarding oversized conversation without executing a suffix.

## Real local speech model, synthetic input

```sh
say -v Samantha -o /tmp/talkback-speech-fixture.aiff \
  'Mute this track and solo this track. [[slnc 2000]]'
xcrun swiftc -parse-as-library -target arm64-apple-macos26.0 \
  scripts/continuous_speech_smoke.swift \
  Talkback/Sources/Talkback/DictationController.swift \
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

The installed Talkback control surface v0.19 passed all 54 regression cases:
54 PASS, 0 FAIL, 0 SKIP. Local execution p50 was 83 ms and p95 was 181 ms in that
run. These measurements exclude speech recognition and the pause.

Additional real-Live checks verified spoken-number normalization through the
voice request path (track 6 from −12 dB to −2 dB) and Arrangement Record plus Play
visually on in Live. Recording respects Live's count-in; an immediate `is_playing`
read can still be false during that count-in. This was state verification, not a
recorded-audio-quality test.

`scripts/talkback_live_smoke.py` is an extra opt-in fixture-specific check for
recording and Serum inside an Instruments group. It refuses unexpected track
counts/names. The extended run was paused when the fixture structure changed;
real grouped-Serum insertion and end-to-end physical speech-command execution
remain release gates, not claimed passes. Group validation and failure cleanup
are covered by mocked Live-object tests.

## Manual release gates

- Test real microphone → final transcript → local command → Live readback.
- Repeat independent phrases; test Enter, Escape, shortcut, typing, and Off.
- Confirm unrelated speech, negations, and other foreground apps cannot write.
- Exercise a custom mapping, both recording destinations, and missing targets.
- Verify grouped plug-in insertion and undo in a clean disposable set.
- Test prolonged music playback, sleep/wake, input-device changes, and login.
- Recheck installed app signature, bundled modules, and source/binary privacy.

The installed settings UI and launch-at-login registration have been exercised.
Notarized packaging and reboot/login behavior have not been verified for this preview.
