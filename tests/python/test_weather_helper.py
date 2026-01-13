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

WEATHER_HELPER_PATH = os.path.join(LIB_DIR, "weather_helper.py")


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload))


class WeatherHelperTests(unittest.TestCase):
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

    def test_get_current_weather_uses_cache(self):
        cached = {
            "timestamp": datetime.now().isoformat(),
            "current": {"temperature": 20, "feels_like": 19, "condition": "Clear sky"},
        }
        write_json(self.mind_path / "state" / "weather-cache.json", cached)

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            with mock.patch.object(module.WeatherHelper, "_fetch_weather", side_effect=AssertionError("fetch called")):
                current = helper.get_current_weather()

        self.assertEqual(current, cached)

    def test_get_current_weather_returns_none_without_location(self):
        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            current = helper.get_current_weather()

        self.assertIsNone(current)

    def test_get_current_weather_returns_none_without_coordinates(self):
        write_json(self.mind_path / "state" / "location.json", {"lat": 47.0})

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            current = helper.get_current_weather()

        self.assertIsNone(current)

    def test_fetch_weather_parses_response_and_caches(self):
        location = {"lat": 47.0, "lon": -122.0}
        write_json(self.mind_path / "state" / "location.json", location)

        sample = {
            "current": {
                "temperature_2m": 30,
                "relative_humidity_2m": 10,
                "apparent_temperature": 28,
                "weather_code": 95,
                "wind_speed_10m": 45,
            },
            "hourly": {
                "temperature_2m": [30, 29],
                "precipitation_probability": [10, 70, 80],
                "weather_code": [95, 95],
            },
        }

        class DummyResponse:
            def __init__(self, data):
                self.data = data

            def read(self):
                return json.dumps(self.data).encode()

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            with mock.patch.object(module.urllib.request, "urlopen", return_value=DummyResponse(sample)):
                current = helper.get_current_weather()

        self.assertEqual(current["current"]["condition"], "Thunderstorm")
        self.assertEqual(current["precipitation_next_hours"], "Rain likely")
        self.assertTrue((self.mind_path / "state" / "weather-cache.json").exists())

    def test_fetch_weather_handles_url_error(self):
        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            with mock.patch.object(
                module.urllib.request,
                "urlopen",
                side_effect=module.urllib.error.URLError("down"),
            ):
                current = helper._fetch_weather(47.0, -122.0)

        self.assertIsNone(current)

    def test_weather_summary_includes_alerts_and_precip(self):
        cached = {
            "timestamp": datetime.now().isoformat(),
            "current": {
                "temperature": 10,
                "feels_like": 5,
                "condition": "Overcast",
                "humidity": 10,
                "wind_speed": 50,
            },
            "precipitation_next_hours": "Rain likely",
        }
        write_json(self.mind_path / "state" / "weather-cache.json", cached)

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            summary = helper.get_weather_summary()

        self.assertIn("## Weather Context", summary)
        self.assertIn("**Now:**", summary)
        self.assertIn("**Conditions:** Overcast", summary)
        self.assertIn("**Next few hours:** Rain likely", summary)
        self.assertIn("Very windy", summary)
        self.assertIn("Very dry air", summary)
        self.assertIn("Rain expected", summary)

    def test_weather_triggers_from_cached_conditions(self):
        cached = {
            "timestamp": datetime.now().isoformat(),
            "current": {
                "temperature": 36,
                "weather_code": 95,
            },
            "hourly": {
                "precipitation_probability": [10, 70, 80],
            },
        }
        write_json(self.mind_path / "state" / "weather-cache.json", cached)

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            triggers = helper.get_weather_triggers()

        subtypes = {t.get("subtype") for t in triggers}
        self.assertIn("rain_coming", subtypes)
        self.assertIn("extreme_heat", subtypes)
        self.assertIn("storm", subtypes)

    def test_weather_triggers_extreme_cold(self):
        cached = {
            "timestamp": datetime.now().isoformat(),
            "current": {
                "temperature": -10,
                "weather_code": 1,
            },
            "hourly": {"precipitation_probability": [70, 80]},
        }
        write_json(self.mind_path / "state" / "weather-cache.json", cached)

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            triggers = helper.get_weather_triggers()

        subtypes = {t.get("subtype") for t in triggers}
        self.assertIn("extreme_cold", subtypes)
        self.assertNotIn("rain_coming", subtypes)

    def test_load_cache_stale_returns_none(self):
        cached = {
            "timestamp": (datetime.now() - timedelta(hours=2)).isoformat(),
            "current": {"temperature": 20},
        }
        write_json(self.mind_path / "state" / "weather-cache.json", cached)

        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            helper = module.WeatherHelper()
            self.assertIsNone(helper._load_cache())

    def test_main_usage_summary_and_unknown(self):
        with load_service_module(WEATHER_HELPER_PATH, env=self.env) as module:
            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["weather_helper.py"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Usage: weather_helper.py <command>", buf.getvalue())

            buf = io.StringIO()
            with (
                mock.patch.object(sys, "argv", ["weather_helper.py", "summary"]),
                mock.patch.object(module.WeatherHelper, "get_weather_summary", return_value="Summary"),
                contextlib.redirect_stdout(buf),
            ):
                module.main()
            self.assertEqual(buf.getvalue().strip(), "Summary")

            buf = io.StringIO()
            with mock.patch.object(sys, "argv", ["weather_helper.py", "unknown"]), contextlib.redirect_stdout(buf):
                with self.assertRaises(SystemExit):
                    module.main()
            self.assertIn("Unknown command: unknown", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
