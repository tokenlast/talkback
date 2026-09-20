import importlib
from types import ModuleType, SimpleNamespace
from unittest import TestCase, mock


class GroupCreationTests(TestCase):
    @classmethod
    def setUpClass(cls):
        framework = ModuleType("_Framework.ControlSurface")
        framework.ControlSurface = object
        with mock.patch.dict("sys.modules", {"Live": ModuleType("Live"), "_Framework": ModuleType("_Framework"), "_Framework.ControlSurface": framework}):
            cls.surface_type = importlib.import_module("remote_script.Talkback.Talkback").Talkback

    def surface(self, *, missing_plugin=False, misplaced=False, duplicate=False):
        group = SimpleNamespace(name="Instruments", is_foldable=True, devices=[])
        selected = SimpleNamespace(name="Original", is_foldable=False, devices=[])
        song = SimpleNamespace(tracks=[selected, group], view=SimpleNamespace(selected_track=selected))
        if duplicate:
            song.tracks.append(SimpleNamespace(name="Instruments", is_foldable=True, devices=[]))
        song.begin_undo_step = mock.Mock()
        song.end_undo_step = mock.Mock()
        def create(index):
            track = SimpleNamespace(name="MIDI", devices=[], group_track=None if misplaced else group)
            if index == -1:
                song.tracks.append(track)
            else:
                song.tracks.insert(index, track)
            return track
        song.create_midi_track = mock.Mock(side_effect=create)
        song.delete_track = mock.Mock(side_effect=lambda index: song.tracks.pop(index))
        browser = SimpleNamespace(hotswap_target=None)
        browser.load_item = mock.Mock(side_effect=lambda item: song.view.selected_track.devices.append(SimpleNamespace(name="Serum")))
        surface = self.surface_type.__new__(self.surface_type)
        surface.song = lambda: song
        surface._browser = lambda: browser
        surface._find_item = lambda *args: None if missing_plugin else {"name": "Serum", "uri": "test"}
        surface._resolve_browser_item = lambda entry: object()
        surface.log_message = lambda text: None
        return surface, song, selected, browser

    def test_missing_or_duplicate_group_never_creates_a_track(self):
        for name, duplicate in (("Missing", False), ("Instruments", True)):
            surface, song, _, _ = self.surface(duplicate=duplicate)
            reply = surface._add_track({"device": "Serum", "group_name": name})
            self.assertEqual(reply["error"], "group_not_found")
            song.create_midi_track.assert_not_called()

    def test_missing_plugin_never_creates_a_track(self):
        surface, song, _, _ = self.surface(missing_plugin=True)
        self.assertEqual(surface._add_track({"device": "Missing", "group_name": "Instruments"})["error"], "plugin_not_found")
        song.create_midi_track.assert_not_called()

    def test_misplacement_removes_only_new_empty_track(self):
        surface, song, selected, browser = self.surface(misplaced=True)
        before = list(song.tracks)
        reply = surface._add_track({"device": "Serum", "group_name": "Instruments"})
        self.assertEqual(reply["error"], "group_placement_failed")
        self.assertEqual(song.tracks, before)
        self.assertIs(song.view.selected_track, selected)
        browser.load_item.assert_not_called()
        song.end_undo_step.assert_called_once()

    def test_valid_group_is_checked_before_loading(self):
        surface, song, _, browser = self.surface()
        reply = surface._add_track({"device": "Serum", "group_name": "instruments"})
        self.assertTrue(reply["ok"])
        self.assertEqual(reply["devices_after"], ["Serum"])
        self.assertIs(song.tracks[reply["track_index"]].group_track, song.tracks[1])
        browser.load_item.assert_called_once()
        song.end_undo_step.assert_called_once()

    def test_resume_does_not_interrupt_record_count_in_or_playback(self):
        for playing, counting, should_call in ((False, True, False), (True, False, False), (False, False, True)):
            with self.subTest(playing=playing, counting=counting):
                surface, song, _, _ = self.surface()
                song.is_playing = playing
                song.is_counting_in = counting
                song.continue_playing = mock.Mock(return_value=None)
                reply = surface._execute_lom("lom_call", {"path": "live_set", "method": "continue_playing", "args": []})
                self.assertTrue(reply["ok"])
                self.assertEqual(song.continue_playing.call_count, int(should_call))
