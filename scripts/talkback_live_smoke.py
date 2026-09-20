#!/usr/bin/env python3
"""Opt-in writes to the named disposable QA set. Never run in a music project."""
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ["TALKBACK_LOCAL_ONLY"] = "1"
os.environ["TALKBACK_LANG"] = "en"

import plugin_script
from daemon import TalkbackService
from script_bridge_client import ScriptBridgeClient


def main():
    bridge = ScriptBridgeClient()
    service = TalkbackService(bridge=bridge)
    service.start()
    initial, _ = bridge.read_snapshot()
    names = [track.name for track in initial.tracks]
    assert names.count("LJ-TEST") == 1 and "LJ-OTHER" in names and "Instruments" in names
    assert len(names) == 12, "Unexpected test set structure"
    assert not initial.playing and not any(track.arm or track.clips for track in initial.tracks)
    target = next(track for track in initial.tracks if track.name == "LJ-OTHER")

    def command(text, *, expect="result", voice=True):
        reply = service.process({"id": "qa", "text": text, **({"source": "voice"} if voice else {})})
        print(text, "=>", reply.get("kind"), reply.get("line"), flush=True)
        assert reply.get("kind") == expect, reply
        return reply

    try:
        command("Set track 6 volume to minus twelve dB")
        command("Turn trakt six up ten decibels.")
        after, _ = bridge.read_snapshot()
        assert after.tracks[5].volume_display == "-2.0 dB", after.tracks[5].volume_display
        command("set track 6 volume to 0 dB")

        command("Start recording arm LJ-OTHER")
        after, _ = bridge.read_snapshot()
        # Respect Live's own count-in (up to four bars at this fixture's tempo).
        for _ in range(240):
            if after.playing:
                break
            time.sleep(0.05)
            after, _ = bridge.read_snapshot()
        assert after.song.get("record_mode") and after.playing, after.song
        assert after.tracks[target.index].arm
        assert not after.song.get("session_record")
        command("stop recording")
        command("stop")
        command("disarm LJ-OTHER")
        print("PASS Arrangement record, transport, and track arm", flush=True)

        before_count = len(bridge.read_snapshot()[0].tracks)
        command("Throw Serum on a new track in MissingGroupForTalkbackQA", expect="error")
        assert len(bridge.read_snapshot()[0].tracks) == before_count
        command("Throw Serum on a new track in Instruments")
        after, _ = bridge.read_snapshot()
        assert len(after.tracks) == before_count + 1
        group = next(track.index for track in after.tracks if track.name == "Instruments")
        assert any("serum" in device.name.lower() for device in after.tracks[group + 1].devices)
        print("PASS Serum loaded immediately after the Instruments group; script verified group ownership", flush=True)
        command("undo")
        assert len(bridge.read_snapshot()[0].tracks) == before_count
        print("PASS grouped track undo", flush=True)
    finally:
        # Never leave the disposable set recording after an assertion failure.
        for text in ("stop arrangement recording", "stop session recording", "stop", "disarm LJ-OTHER", "set track 6 volume to 0 dB"):
            service.process({"id": "cleanup", "text": text})
        service.close()


if __name__ == "__main__":
    main()
