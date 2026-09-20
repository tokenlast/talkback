# Talkback commands

English voice commands are checked locally. Say one, then pause; Talkback keeps
listening for the next command. The CLI also supports typed English and the
inherited Japanese grammar. There is no floating command bar.

## Targets

`this track`, `that one`, and no stated track use the current selected track.
`track 6` uses the sixth track (including group tracks). Exact track names work.
If a stated target is missing or ambiguous, Talkback must not pick another one.

## Mixer and tracks

- `turn that one up 3 dB` / `turn track 6 down 10 dB`
- `set this track volume to -6 dB`
- `pan this track left` / `pan this track center`
- `mute this track` / `unmute this track`
- `solo this track` / `unsolo this track`
- `arm this track` / `disarm this track`
- `mute tracks 3 to 6` / `unmute everything` / `solo only Bass`
- `set send A on this track to 20 percent`
- `monitor this track in` / `monitor this track auto` / `monitor this track off`
- `fold this track` / `unfold this track` (groups)
- `rename this track to Lead`
- `add a MIDI track` / `add an audio track`

## Transport

- `play` / `stop` / `resume`
- `start recording` / `stop recording` — destination selected in Settings
- `start arrangement recording` / `stop arrangement recording` — explicit override
- `start session recording` / `stop session recording` — explicit override
- `arm this track and start recording` (also accepts `start recording arm this track`)
- `set tempo to 120 bpm` / `tap tempo`
- `turn loop on` / `turn loop off`
- `turn metronome on` / `turn metronome off`
- `turn overdub on` / `turn overdub off`
- `jump to bar 17` / `capture MIDI` / `stop all clips`

Recording uses the tracks currently armed in Live; it does not silently arm a
different track. Arrangement recording starts the stopped transport at its current
position. Stopping recording leaves playback running; say `stop` to stop transport.
Live's own count-in still applies before the take starts.

## Devices and plug-ins

- `add Serum to this track`
- `throw Serum on a new track in Instruments` — an existing group named Instruments
- `create a track with Wavetable`
- `turn Reverb off` / `turn Reverb on`
- `set Dry/Wet on Reverb on Pad to 30 percent`

Plug-ins must already be installed and visible in Live's browser. Exact names and
unambiguous partial names are supported. Missing/ambiguous groups or plug-ins
must not create a track. A group destination is supported for named plug-ins;
generic device categories do not select an arbitrary instrument.

## Clips and notes

- `launch clip 1 on track 2` / `stop clip 1 on track 2`
- `launch scene 2` / `stop this track clips`
- `turn clip loop on` / `turn clip loop off`
- `turn warp on` / `turn warp off`
- `transpose this clip up 12 semitones`
- `set this clip gain to -3 dB`
- Note transforms: quantize, legato, transpose, velocity, and duplicate loop.

These depend on Live's selected/open clip and supported clip type. If Talkback
needs clarification, choose an offered answer from its menu or repeat the full
command with an explicit target. Confirmations also appear in the menu and expire
after 20 seconds. Ambient replies do not answer old questions.

## Undo and multiple actions

`undo` restores the most recent supported change. Mixer toggles use verified
before/after values; structural edits use Live's undo stack. `redo` uses Live's
redo stack and is not guaranteed for value-restoration undo. A recorded take and
transport position are not erased/restored by changing the recording toggle.

Up to four compatible mixer, track, parameter, and recording operations can be
joined with `and`. All clauses are planned before writing. Runtime failures attempt
rollback and report any changes that could not be restored. Plug-in insertion and
clip launches are not supported inside these multi-action chains.

## Your own phrases

Edit Settings → Custom commands, one exact mapping per line:

```text
bring it forward => turn this track up 3 dB
quiet please => mute this track
my synth => throw Serum on a new track in Instruments
ready to go => arm this track and start recording
```

Matching ignores case, repeated spaces, and trailing periods/exclamation marks.
Lines beginning with `#` are comments. No regex, wildcard captures, recursion,
shell commands, Python, or generated code is run. The right-hand side must resolve
through the existing local controls; it never falls back to cloud interpretation.
Unknown commands do nothing and may request a clearer command.

The file is `~/Library/Application Support/Talkback/commands.txt`. It can also be
edited in a text editor; the daemon rereads it for each command. Settings validates
the list format, while action/target validity is checked against the current Live set.

The complete operation registry is `actions.py`; phrase parsers are `intent_en.py`
and `intent.py`. Adding a new kind of Live operation still requires code and tests.
