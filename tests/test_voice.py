import os
import unittest
from unittest import mock

from daemon import TalkbackService, read_key
from intent import Action, extract_plugin_request, parse_local, plugin_intent, split_compound
from tests.support import StatefulLive, sample_snapshot
from voice_gate import admit_voice


class VoiceTests(unittest.TestCase):
    def test_polite_requests_accept_dictated_question_marks(self):
        for prefix in ("Can you", "Could you", "Would you", "Okay, can you", "Please, can you"):
            for ending in ("", ".", "?"):
                text = prefix + " start a new track in instruments" + ending
                with self.subTest(text=text):
                    value = admit_voice(text)
                    self.assertEqual(value, "start a new track in instruments")
                    intent = parse_local(value, sample_snapshot())
                    self.assertEqual(intent.action, Action.ADD_MIDI_TRACK)
                    self.assertEqual(intent.group_name, "instruments")
                    self.assertIsNone(extract_plugin_request(value, sample_snapshot()))

    def test_questions_and_negated_polite_requests_stay_blocked(self):
        for text in ("How do I create a new track?", "Can you tell me how to create a track?",
                     "Can you not start a new track?", "Could you create a track later?",
                     "Can you? Start a new track", "Mute this track?", 'Can you say "mute this track"?'):
            with self.subTest(text=text):
                self.assertIsNone(admit_voice(text))

    def test_plain_track_creation_is_not_a_plugin(self):
        for text, kind, group in (("Create a new MIDI track", "midi", None),
                                  ("Start a new track", "midi", None),
                                  ("Create a new MIDI track in Instruments", "midi", "instruments"),
                                  ("Add an audio track inside the group Drums", "audio", "drums")):
            with self.subTest(text=text):
                intent = parse_local(text, sample_snapshot())
                self.assertEqual(intent.track_kind, kind)
                self.assertEqual(intent.group_name, group)
                self.assertIsNone(extract_plugin_request(text, sample_snapshot()))
        self.assertIsNone(parse_local("start track", sample_snapshot()))

    def test_spoken_group_track_creation_reaches_script_without_cloud(self):
        snapshot = sample_snapshot()
        bridge = mock.Mock()
        requester = mock.Mock(side_effect=AssertionError("Network must not be used"))
        service = TalkbackService(bridge=bridge, snapshot=snapshot, requester=requester)
        service.reader = mock.Mock()
        service.reader.read.return_value = (snapshot, 0)
        with mock.patch("daemon.plugin_script.ping", return_value=True), \
             mock.patch("daemon.plugin_script.add_track", return_value={"ok": True}) as add, \
             mock.patch("daemon.plugin_script.list_plugins", side_effect=AssertionError("Not a plugin request")):
            reply = service.process({"id": "test", "source": "voice", "text": "Can you start a new track in instruments?"})
        self.assertEqual(reply["kind"], "result", reply)
        add.assert_called_once_with("midi", None, None, group_name="instruments")
        requester.assert_not_called()
        self.assertEqual(bridge.mock_calls, [])

    def test_group_track_creation_never_falls_back_to_ungrouped_creation(self):
        bridge = mock.Mock()
        service = TalkbackService(bridge=bridge, snapshot=sample_snapshot())
        with mock.patch("daemon.plugin_script.ping", return_value=False), \
             mock.patch("daemon.plugin_script.add_track") as add:
            reply = service.process({"id": "test", "source": "voice", "text": "Can you start a new track in instruments?"})
        self.assertEqual(reply["kind"], "error", reply)
        add.assert_not_called()
        self.assertEqual(bridge.mock_calls, [])

    def test_recording_modes_and_transport_order(self):
        from dataclasses import replace
        from actions import ACTIONS
        from bridge_client import validate_arguments
        snapshot = replace(sample_snapshot(), playing=False)
        intent = parse_local("start recording", snapshot)
        batches = ACTIONS[intent.action].apply(snapshot, intent)
        self.assertIn("record_mode", batches[0])
        self.assertIn("continue_playing", batches[1])
        for batch in batches:
            validate_arguments(batch)
        self.assertFalse(any("continue_playing" in b for b in ACTIONS[intent.action].apply(replace(snapshot, playing=True), intent)))
        self.assertEqual(parse_local("start session recording", snapshot).action, Action.SESSION_RECORD_ON)
        self.assertEqual(parse_local("stop session recording", snapshot).action, Action.SESSION_RECORD_OFF)

    def test_natural_numeric_commands(self):
        cases = {
            "Okay, turn that one up three decibels.": (Action.VOLUME, "selected", 3),
            "Turn trakt two up ten dB": (Action.VOLUME, 1, 10),
            "Please turn this one down 3 dB": (Action.VOLUME, "selected", -3),
            "Set this track volume to minus twelve decibels": (Action.VOLUME, "selected", -12),
        }
        for text, (action, track, number) in cases.items():
            with self.subTest(text=text):
                value = admit_voice(text)
                self.assertIsNotNone(value)
                intent = parse_local(value, sample_snapshot())
                self.assertIsNotNone(intent)
                self.assertEqual(intent.action, action)
                self.assertEqual(intent.track, track)
                self.assertEqual(abs(intent.number.value), abs(number))

    def test_operator_on_new_track_voice_request(self):
        value = admit_voice("Add Operator to a new track.")
        self.assertIsNotNone(value)
        intent = parse_local(value, sample_snapshot())
        self.assertEqual(intent.action, Action.ADD_TRACK_WITH_DEVICE)
        self.assertEqual(intent.native_device, "Operator")
        self.assertEqual(intent.track_kind, "midi")

    def test_conversation_never_reaches_jev_or_live(self):
        bridge = mock.Mock()
        requester = mock.Mock(side_effect=AssertionError("Network must not be used"))
        service = TalkbackService(bridge=bridge, snapshot=sample_snapshot(), key="test-only", requester=requester)
        for text in (
            "I said turn that one up three decibels", "How do I mute this track?",
            "Don't mute this track", "Please do not start recording", "Maybe mute it",
            "Mute it later", "Mute it if the chorus starts", "Mute it but not yet",
            'He said "mute it"', "I'm making tea", "Yes", "Okay", "", "a" * 501,
        ):
            with self.subTest(text=text):
                self.assertIsNone(admit_voice(text))
                self.assertTrue(service.process({"id": "test", "source": "voice", "text": text})["ignored"])
        requester.assert_not_called()
        self.assertEqual(bridge.mock_calls, [])

    def test_local_command_uses_current_selection_and_no_network(self):
        bridge = StatefulLive(selected=1)
        requester = mock.Mock(side_effect=AssertionError("Network must not be used"))
        service = TalkbackService(bridge=bridge, snapshot=sample_snapshot(), requester=requester)
        reply = service.process({"id": "test", "source": "voice", "text": "Mute this track."})
        self.assertEqual(reply["kind"], "result", reply)
        self.assertTrue(bridge.state[(1, "mute")])
        self.assertFalse(bridge.state[(0, "mute")])
        requester.assert_not_called()

    def test_offline_mode_does_not_read_shell_secrets(self):
        with mock.patch.dict(os.environ, {"TALKBACK_LOCAL_ONLY": "1", "TYPESAFE_API_KEY": "test-only"}), mock.patch("daemon.Path.home", side_effect=AssertionError("No shell reads")):
            self.assertIsNone(read_key())
            self.assertIsNone(read_key("GEMINI_API_KEY"))

    def test_arm_precedes_recording(self):
        text = admit_voice("Start recording arm this track")
        clauses = split_compound(text, sample_snapshot())
        self.assertEqual([parse_local(clause, sample_snapshot()).action for clause in clauses], [Action.ARM, Action.RECORD_ON])

    def test_group_target_survives_plugin_resolution(self):
        request = extract_plugin_request("Throw Serum on a new track in Instruments", sample_snapshot())
        self.assertEqual(request.raw_name, "serum")
        self.assertEqual(request.group_name, "instruments")
        intent = plugin_intent(request, "Serum 2")
        self.assertEqual(intent.group_name, "instruments")
        self.assertEqual(intent.action, Action.ADD_TRACK_WITH_PLUGIN)
