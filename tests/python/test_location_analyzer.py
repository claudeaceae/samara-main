import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

TESTS_DIR = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, TESTS_DIR)
LIB_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "lib"))
sys.path.insert(0, LIB_DIR)

from service_test_utils import load_service_module

LOCATION_ANALYZER_PATH = os.path.join(LIB_DIR, "location_analyzer.py")


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload))


class LocationAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = Path(self.temp_dir.name) / ".claude-mind"
        (self.mind_path / "state").mkdir(parents=True, exist_ok=True)
        self.env = {
            "SAMARA_MIND_PATH": str(self.mind_path),
            "MIND_PATH": str(self.mind_path),
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_get_current_place_prefers_wifi(self):
        places = {
            "places": [
                {
                    "name": "home",
                    "label": "Home",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                    "wifi_hints": ["HomeWiFi"],
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {
                "wifi": "HomeWiFi",
                "lat": 37.0,
                "lon": -122.0,
                "timestamp": datetime.now().isoformat(),
            },
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            place = analyzer.get_current_place()

        self.assertIsNotNone(place)
        self.assertEqual(place.get("name"), "home")

    def test_detect_state_change_arrival_updates_state(self):
        places = {
            "places": [
                {
                    "name": "home",
                    "label": "Home",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {
                "lat": 37.0,
                "lon": -122.0,
                "timestamp": datetime.now().isoformat(),
            },
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            change = analyzer.detect_state_change()

        state_path = self.mind_path / "state" / "location-state.json"
        state = json.loads(state_path.read_text())

        self.assertEqual(change.get("type"), "arrived")
        self.assertEqual(state.get("place_name"), "home")

    def test_detect_state_change_stale_data_short_circuits(self):
        stale_timestamp = (datetime.now() - timedelta(hours=1)).isoformat()
        state_path = self.mind_path / "state" / "location-state.json"
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 0.0, "lon": 0.0, "timestamp": stale_timestamp},
        )
        write_json(state_path, {"place_name": "home"})

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            change = analyzer.detect_state_change()

        self.assertEqual(change.get("type"), "stale_data")
        self.assertEqual(json.loads(state_path.read_text()).get("place_name"), "home")

    def test_is_moving_detects_speed(self):
        write_json(
            self.mind_path / "state" / "location.json",
            {"speed": 1.2, "timestamp": datetime.now().isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertTrue(analyzer.is_moving())

    def test_get_battery_triggers_critical(self):
        write_json(
            self.mind_path / "state" / "location.json",
            {"battery": 0.09, "timestamp": datetime.now().isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_battery_triggers()

        self.assertEqual(len(triggers), 1)
        self.assertEqual(triggers[0].get("subtype"), "critical")
        self.assertTrue(triggers[0].get("suppress_non_urgent"))

    def test_get_location_triggers_in_motion(self):
        places = {
            "places": [
                {
                    "name": "home",
                    "label": "Home",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {
                "lat": 37.0,
                "lon": -122.0,
                "speed": 2.0,
                "timestamp": datetime.now().isoformat(),
            },
        )
        write_json(
            self.mind_path / "state" / "location-state.json",
            {"place_name": "home", "timestamp": datetime.now().isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_location_triggers()

        motion = [t for t in triggers if t.get("subtype") == "in_motion"]
        self.assertTrue(motion)
        self.assertTrue(motion[0].get("suppress_engagement"))

    def test_get_location_summary_includes_battery(self):
        write_json(
            self.mind_path / "state" / "location.json",
            {
                "lat": 10.0,
                "lon": 20.0,
                "battery": 0.55,
                "timestamp": datetime.now().isoformat(),
            },
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_location_summary()

        self.assertIn("## Location Context", summary)
        self.assertIn("Battery", summary)

    def test_detect_place_by_coordinates(self):
        places = {
            "places": [
                {
                    "name": "office",
                    "label": "Office",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            place = analyzer.detect_place(37.0005, -122.0005)

        self.assertEqual(place.get("name"), "office")

    def test_get_location_history_filters_hours(self):
        history_path = self.mind_path / "state" / "location-history.jsonl"
        recent = (datetime.now() - timedelta(hours=1)).isoformat()
        old = (datetime.now() - timedelta(hours=30)).isoformat()
        history_path.write_text(
            "\n".join(
                [
                    json.dumps({"timestamp": old, "lat": 1.0, "lon": 1.0}),
                    json.dumps({"timestamp": recent, "lat": 2.0, "lon": 2.0}),
                ]
            )
            + "\n"
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            recent_history = analyzer.get_location_history(hours=24)

        self.assertEqual(len(recent_history), 1)
        self.assertEqual(recent_history[0].get("lat"), 2.0)

    def test_get_location_triggers_arrived_home_evening(self):
        fixed_now = datetime(2025, 1, 1, 19, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        places = {
            "places": [
                {
                    "name": "home",
                    "label": "Home",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 37.0, "lon": -122.0, "timestamp": fixed_now.isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_location_triggers()

        arrived = [t for t in triggers if t.get("subtype") == "arrived_home_evening"]
        self.assertTrue(arrived)

    def test_get_location_triggers_left_home_morning(self):
        fixed_now = datetime(2025, 1, 2, 8, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        places = {
            "places": [
                {
                    "name": "home",
                    "label": "Home",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 38.0, "lon": -123.0, "timestamp": fixed_now.isoformat()},
        )
        write_json(
            self.mind_path / "state" / "location-state.json",
            {"place_name": "home", "timestamp": fixed_now.isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_location_triggers()

        left_home = [t for t in triggers if t.get("subtype") == "left_home_morning"]
        self.assertTrue(left_home)

    def test_get_daily_movement_summary(self):
        now = datetime.now()
        places = {
            "places": [
                {
                    "name": "home",
                    "label": "Home",
                    "lat": 37.0,
                    "lon": -122.0,
                    "radius_m": 200,
                }
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 37.0, "lon": -122.0, "timestamp": now.isoformat()},
        )
        history_path = self.mind_path / "state" / "location-history.jsonl"
        history_entries = [
            {"timestamp": (now - timedelta(hours=2)).isoformat(), "lat": 37.0, "lon": -122.0},
            {"timestamp": (now - timedelta(hours=1)).isoformat(), "lat": 38.0, "lon": -123.0},
        ]
        history_path.write_text("\n".join(json.dumps(e) for e in history_entries) + "\n")

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_daily_movement_summary()

        self.assertTrue(summary.get("has_left_home"))
        self.assertIn("summary", summary)

    def test_get_location_summary_when_missing(self):
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_location_summary()

        self.assertIn("Location: Unknown", summary)

    def test_get_current_location_invalid_json(self):
        location_path = self.mind_path / "state" / "location.json"
        location_path.write_text("{bad json}")

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertIsNone(analyzer.get_current_location())

    def test_get_location_history_handles_missing_and_invalid(self):
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertEqual(analyzer.get_location_history(hours=1), [])

        history_path = self.mind_path / "state" / "location-history.jsonl"
        history_path.write_text(
            "\n".join(
                [
                    "{bad json}",
                ]
            )
            + "\n"
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            history = analyzer.get_location_history(hours=24)

        self.assertEqual(history, [])

        recent = (datetime.now() - timedelta(hours=1)).isoformat()
        history_path.write_text(
            "\n".join(
                [
                    json.dumps({"timestamp": "not-a-time", "lat": 1.0, "lon": 1.0}),
                    json.dumps({"timestamp": recent, "lat": 2.0, "lon": 2.0}),
                ]
            )
            + "\n"
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            history = analyzer.get_location_history(hours=24)

        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["lat"], 2.0)

    def test_detect_place_by_wifi_returns_none(self):
        places = {"places": [{"name": "office", "wifi_hints": ["OfficeWiFi"]}]}
        write_json(self.mind_path / "state" / "places.json", places)

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertIsNone(analyzer.detect_place_by_wifi(None))
            self.assertIsNone(analyzer.detect_place_by_wifi("OtherWiFi"))

    def test_get_current_place_no_location(self):
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertIsNone(analyzer.get_current_place())

    def test_detect_state_change_moved_and_departed(self):
        places = {
            "places": [
                {"name": "home", "label": "Home", "lat": 37.0, "lon": -122.0, "radius_m": 200},
                {"name": "office", "label": "Office", "lat": 38.0, "lon": -123.0, "radius_m": 200},
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location-state.json",
            {"place_name": "home", "place_label": "Home"},
        )
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 38.0, "lon": -123.0, "timestamp": "bad-timestamp"},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            change = analyzer.detect_state_change()

        self.assertEqual(change.get("type"), "moved")
        self.assertEqual(change.get("from_place"), "home")

        write_json(
            self.mind_path / "state" / "location-state.json",
            {"place_name": "home", "place_label": "Home"},
        )
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 0.0, "lon": 0.0, "timestamp": datetime.now().isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            change = analyzer.detect_state_change()

        self.assertEqual(change.get("type"), "departed")

    def test_is_moving_motion_state_and_no_location(self):
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertFalse(analyzer.is_moving())

        write_json(
            self.mind_path / "state" / "location.json",
            {"motion": ["walking"], "timestamp": datetime.now().isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertTrue(analyzer.is_moving())

    def test_get_battery_triggers_low(self):
        write_json(
            self.mind_path / "state" / "location.json",
            {"battery": 0.15, "timestamp": datetime.now().isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_battery_triggers()

        self.assertEqual(triggers[0].get("subtype"), "low")

    def test_get_location_triggers_arrived_home_and_place_and_left_home(self):
        fixed_now = datetime(2025, 1, 3, 13, 0, 0)

        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return fixed_now if tz is None else fixed_now.replace(tzinfo=tz)

        places = {
            "places": [
                {"name": "home", "label": "Home", "lat": 37.0, "lon": -122.0, "radius_m": 200},
                {"name": "office", "label": "Office", "lat": 38.0, "lon": -123.0, "radius_m": 200},
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 37.0, "lon": -122.0, "timestamp": fixed_now.isoformat()},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_location_triggers()

        self.assertTrue(any(t.get("subtype") == "arrived_home" for t in triggers))

        state_path = self.mind_path / "state" / "location-state.json"
        if state_path.exists():
            state_path.unlink()
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 38.0, "lon": -123.0, "timestamp": fixed_now.isoformat()},
        )
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_location_triggers()

        self.assertTrue(any(t.get("subtype") == "arrived_place" for t in triggers))

        write_json(
            self.mind_path / "state" / "location-state.json",
            {"place_name": "home", "place_label": "Home"},
        )
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 0.0, "lon": 0.0, "timestamp": fixed_now.isoformat()},
        )
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            module.datetime = FixedDatetime
            analyzer = module.LocationAnalyzer()
            triggers = analyzer.get_location_triggers()

        self.assertTrue(any(t.get("subtype") == "left_home" for t in triggers))

    def test_get_location_summary_motion_and_coords(self):
        now = datetime.now().isoformat()
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 10.0, "lon": 20.0, "motion": ["walking"], "timestamp": now},
        )

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_location_summary()

        self.assertIn("unknown place", summary)
        self.assertIn("In motion", summary)
        self.assertIn("Last update", summary)

    def test_get_daily_movement_summary_no_data_and_home(self):
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_daily_movement_summary()

        self.assertIn("No location data", summary.get("summary", ""))

        now = datetime.now()
        places = {
            "places": [
                {"name": "home", "label": "Home", "lat": 37.0, "lon": -122.0, "radius_m": 200},
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 37.0, "lon": -122.0, "timestamp": now.isoformat()},
        )
        history_path = self.mind_path / "state" / "location-history.jsonl"
        history_entries = [
            {"timestamp": (now - timedelta(hours=1)).isoformat(), "lat": 37.0, "lon": -122.0},
        ]
        history_path.write_text("\n".join(json.dumps(e) for e in history_entries) + "\n")

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_daily_movement_summary()

        self.assertFalse(summary.get("has_left_home"))
        self.assertIn("Home all day", summary.get("summary", ""))

    def test_get_daily_movement_summary_single_non_home(self):
        now = datetime.now()
        places = {
            "places": [
                {"name": "office", "label": "Office", "lat": 38.0, "lon": -123.0, "radius_m": 200},
            ]
        }
        write_json(self.mind_path / "state" / "places.json", places)
        write_json(
            self.mind_path / "state" / "location.json",
            {"lat": 38.0, "lon": -123.0, "timestamp": now.isoformat()},
        )
        history_path = self.mind_path / "state" / "location-history.jsonl"
        history_entries = [
            {"timestamp": (now - timedelta(hours=1)).isoformat(), "lat": 38.0, "lon": -123.0},
        ]
        history_path.write_text("\n".join(json.dumps(e) for e in history_entries) + "\n")

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            summary = analyzer.get_daily_movement_summary()

        self.assertTrue(summary.get("has_left_home"))
        self.assertIn("at office", summary.get("summary", "").lower())

    def test_load_places_and_state_handle_bad_json(self):
        write_json(self.mind_path / "state" / "places.json", {"places": []})
        write_json(self.mind_path / "state" / "location-state.json", {"place_name": "home"})
        self.mind_path.joinpath("state", "places.json").write_text("{bad json}")
        self.mind_path.joinpath("state", "location-state.json").write_text("{bad json}")

        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            analyzer = module.LocationAnalyzer()
            self.assertEqual(analyzer.places, [])
            self.assertEqual(analyzer.previous_state, {})

    def test_main_commands(self):
        with load_service_module(LOCATION_ANALYZER_PATH, env=self.env) as module:
            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["location_analyzer.py"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Usage: location_analyzer.py <command>", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["location_analyzer.py", "place"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn("Not at a known place", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["location_analyzer.py", "summary"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn("Location: Unknown", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["location_analyzer.py", "daily"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn("No location data", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["location_analyzer.py", "history", "1"]), contextlib.redirect_stdout(buf):
                module.main()
            self.assertIn("Found 0 location records", buf.getvalue())

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["location_analyzer.py", "unknown"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Unknown command", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
