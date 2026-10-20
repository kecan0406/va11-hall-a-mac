import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "verify"))
import scenario  # noqa: E402


class CompileScenario(unittest.TestCase):
    def test_click_presses_then_releases(self):
        rec = scenario.compile_scenario("10 move 640 336\n12 click left\n")
        self.assertEqual(rec["10"]["mouse"]["x"], 640.0)
        self.assertEqual(rec["10"]["mouse"]["y"], 336.0)
        self.assertEqual(rec["12"]["mouse"]["pressed"], [1])
        self.assertEqual(rec["15"]["mouse"]["released"], [1])

    def test_cursor_is_pinned_at_frame_zero(self):
        rec = scenario.compile_scenario("5 click")
        self.assertEqual((rec["0"]["mouse"]["x"], rec["0"]["mouse"]["y"]), (0.0, 0.0))

    def test_explicit_first_move_wins(self):
        rec = scenario.compile_scenario("0 move 7 8")
        self.assertEqual((rec["0"]["mouse"]["x"], rec["0"]["mouse"]["y"]), (7.0, 8.0))

    def test_repeat_range(self):
        rec = scenario.compile_scenario("100..200/50 click left")
        self.assertEqual([f for f, e in rec.items() if e.get("mouse", {}).get("pressed")], ["100", "150", "200"])

    def test_key_combo_presses_all_and_releases_all(self):
        rec = scenario.compile_scenario("30 key alt+enter")
        self.assertEqual(sorted(rec["30"]["keysPressed"]), [13, 18])
        self.assertEqual(sorted(rec["33"]["keysReleased"]), [13, 18])

    def test_key_names(self):
        self.assertEqual(scenario.key_code("z"), 90)
        self.assertEqual(scenario.key_code("f11"), 122)
        self.assertEqual(scenario.key_code("pageup"), 33)

    def test_warp_names_a_room(self):
        rec = scenario.compile_scenario("40 warp shooting_room")
        self.assertEqual(rec["40"]["warp"], "shooting_room")

    def test_directives_are_ignored(self):
        rec = scenario.compile_scenario("@exit 100\n@shot 50 label\n5 click\n")
        self.assertEqual(sorted(rec), ["0", "5", "8"])

    def test_bad_input_names_the_line(self):
        with self.assertRaises(SystemExit) as raised:
            scenario.compile_scenario("5 click\n6 explode\n")
        self.assertIn("line 2", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
