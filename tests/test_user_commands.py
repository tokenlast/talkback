import os
from unittest import TestCase, mock

from daemon import TalkbackService
from intent import Action, parse_local
from tests.support import StatefulLive, sample_snapshot
from user_commands import parse_commands, phrase_key, remove_wake_phrase


class UserCommandTests(TestCase):
    def test_plain_text_list(self):
        self.assertEqual(parse_commands("# comment\nQuiet please => mute this track\n"), {"quiet please": "mute this track"})
        self.assertEqual(phrase_key("  QUIET   please. "), "quiet please")
        for value in ("no arrow", "a =>", "=> mute", "a => b => c", "a => mute\nA. => solo", "a" * 65537):
            with self.subTest(value=value[:20]), self.assertRaises(ValueError):
                parse_commands(value)

    def test_recording_setting_and_explicit_override(self):
        with mock.patch.dict(os.environ, {"TALKBACK_RECORDING_MODE": "session"}):
            self.assertEqual(parse_local("start recording", sample_snapshot()).action, Action.SESSION_RECORD_ON)
            self.assertEqual(parse_local("stop recording", sample_snapshot()).action, Action.SESSION_RECORD_OFF)
            self.assertEqual(parse_local("start arrangement recording", sample_snapshot()).action, Action.RECORD_ON)
            self.assertEqual(parse_local("録音開始", sample_snapshot()).action, Action.SESSION_RECORD_ON)
            self.assertEqual(parse_local("録音停止", sample_snapshot()).action, Action.SESSION_RECORD_OFF)

    def test_opening_phrase(self):
        self.assertEqual(remove_wake_phrase("Studio, mute this track.", "studio"), "mute this track.")
        self.assertIsNone(remove_wake_phrase("mute this track", "studio"))
        self.assertIsNone(remove_wake_phrase("studiox mute this track", "studio"))

    def test_custom_phrase_is_local_even_when_cloud_enabled(self):
        bridge = StatefulLive(selected=1)
        requester = mock.Mock(side_effect=AssertionError("No network for aliases"))
        service = TalkbackService(bridge=bridge, snapshot=sample_snapshot(), key="test-key", requester=requester)
        with mock.patch("daemon.load_commands", return_value={"quiet please": "mute this track", "vibe": "make everything cosmic"}):
            result = service.process({"id": "test", "source": "voice", "text": "Quiet please."})
            self.assertEqual(result["kind"], "result", result)
            self.assertTrue(bridge.state[(1, "mute")])
            self.assertEqual(service.key, "test-key")
            service.process({"id": "test2", "source": "voice", "text": "vibe"})
        requester.assert_not_called()

    def test_bad_list_and_wrong_opening_phrase_cannot_write(self):
        bridge = mock.Mock()
        service = TalkbackService(bridge=bridge, snapshot=sample_snapshot())
        with mock.patch("daemon.load_commands", side_effect=ValueError("bad line")):
            self.assertEqual(service.process({"id": "x", "text": "mute this track"})["kind"], "error")
        with mock.patch.dict(os.environ, {"TALKBACK_WAKE_PHRASE": "studio"}):
            self.assertTrue(service.process({"id": "x", "source": "voice", "text": "mute this track"})["ignored"])
        self.assertEqual(bridge.mock_calls, [])
