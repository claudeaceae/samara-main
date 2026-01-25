import io
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

from service_test_utils import load_service_module


LOCATION_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "location-receiver",
    "server.py",
)


class LocationReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        state_dir = Path(self.mind_path) / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
        (state_dir / "places.json").write_text(json.dumps({
            "places": [
                {"name": "Home", "lat": 40.0, "lon": -73.0, "radius_m": 800},
                {"name": "Office", "lat": 40.006, "lon": -73.006, "radius_m": 800},
            ]
        }))
        (state_dir / "subway-stations.json").write_text(json.dumps({
            "stations": []
        }))

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_haversine_distance_zero_and_known_range(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            self.assertEqual(location.haversine_distance(0, 0, 0, 0), 0)
            distance = location.haversine_distance(0, 0, 1, 0)

        self.assertGreater(distance, 110000)
        self.assertLess(distance, 112500)

    def test_encode_polyline_matches_reference(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            coords = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
            encoded = location.encode_polyline(coords)

        self.assertEqual(encoded, "_p~iF~ps|U_ulLnnqC_mqNvxq`@")

    def test_douglas_peucker_simplifies_colinear_points(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            points = [
                {"lat": 0.0, "lon": 0.0},
                {"lat": 0.0001, "lon": 0.0001},
                {"lat": 0.0002, "lon": 0.0002},
            ]
            simplified = location.douglas_peucker(points, tolerance=50)

        self.assertEqual(len(simplified), 2)
        self.assertEqual(simplified[0], points[0])
        self.assertEqual(simplified[-1], points[-1])

    def test_trip_segmenter_completes_trip(self):
        base_time = datetime(2025, 1, 1, 9, 0, 0)

        def loc(ts, lat, lon, speed, motion):
            return {
                "timestamp": ts.isoformat(),
                "lat": lat,
                "lon": lon,
                "speed": speed,
                "motion": motion,
            }

        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            segmenter = location.TripSegmenter()
            segmenter.process_location(loc(base_time, 40.0, -73.0, 0, []))
            segmenter.process_location(loc(base_time + timedelta(minutes=1), 40.003, -73.003, 1.2, ["walking"]))
            segmenter.process_location(loc(base_time + timedelta(minutes=2), 40.006, -73.006, 1.3, ["walking"]))
            segmenter.process_location(loc(base_time + timedelta(minutes=10), 40.006, -73.006, 0, []))
            completed = segmenter.process_location(loc(base_time + timedelta(minutes=16), 40.006, -73.006, 0, []))

        self.assertIsNotNone(completed)
        self.assertEqual(completed["start_place"], "Home")
        self.assertEqual(completed["end_place"], "Office")
        self.assertGreaterEqual(completed["distance_m"], 200)
        self.assertEqual(completed["mode"], "walking")

    def test_write_sense_event_creates_event_file(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            location.write_sense_event(
                event_type="trip_completed",
                data={"from": "Home", "to": "Office", "distance_m": 500},
                priority="normal",
                suggested_prompt="Trip completed."
            )

            event_path = Path(location.LOCATION_EVENT_FILE)
            event = json.loads(event_path.read_text())

        self.assertEqual(event["sense"], "location")
        self.assertEqual(event["priority"], "normal")
        self.assertEqual(event["data"]["type"], "trip_completed")
        self.assertEqual(event["context"]["suggested_prompt"], "Trip completed.")

    def test_resolve_mind_dir_defaults(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            with mock.patch.dict(os.environ, {"HOME": "/tmp/home"}, clear=True):
                self.assertEqual(location.resolve_mind_dir(), "/tmp/home/.claude-mind")

    def test_perpendicular_distance_edge_cases(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            point = {"lat": 0.0, "lon": 0.0}
            line_start = {"lat": 0.0, "lon": 0.0}
            line_end = {"lat": 0.0, "lon": 0.0}
            self.assertEqual(
                location.perpendicular_distance(point, line_start, line_end),
                location.haversine_distance(0.0, 0.0, 0.0, 0.0),
            )
            line_start = {"lat": 0.0, "lon": 0.0}
            line_end = {"lat": 0.0, "lon": 1.0}
            point = {"lat": 0.0, "lon": 0.5}
            dist = location.perpendicular_distance(point, line_start, line_end)

        self.assertGreaterEqual(dist, 0.0)

    def test_douglas_peucker_short_and_recursive(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            points = [{"lat": 0.0, "lon": 0.0}, {"lat": 1.0, "lon": 1.0}]
            self.assertEqual(location.douglas_peucker(points, tolerance=5), points)

            points = [
                {"lat": 0.0, "lon": 0.0},
                {"lat": 0.0, "lon": 1.0},
                {"lat": 1.0, "lon": 1.0},
            ]
            simplified = location.douglas_peucker(points, tolerance=10)

        self.assertGreaterEqual(len(simplified), 3)

    def test_trip_segmenter_helpers(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            segmenter = location.TripSegmenter()
            segmenter.places = [{"name": "Home", "lat": 40.0, "lon": -73.0, "radius_m": 100}]
            self.assertIsNone(segmenter._find_place(0.0, 0.0))
            segmenter.subway_stations = [{"name": "Station", "lat": 40.0, "lon": -73.0}]
            waypoints = [{"lat": 40.0, "lon": -73.0}]
            self.assertEqual(segmenter._find_nearby_transit(waypoints), ["Station"])

            segmenter.current_trip = None
            self.assertIsNone(segmenter._finalize_trip())
            segmenter.current_trip = {"trip_id": "t1", "start_time": "t", "waypoints": [
                {"lat": 0.0, "lon": 0.0, "timestamp": "2025-01-01T00:00:00"},
                {"lat": 0.0, "lon": 0.0, "timestamp": "2025-01-01T00:00:01"},
            ]}
            self.assertIsNone(segmenter._finalize_trip())

    def test_process_location_missing_coords(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            segmenter = location.TripSegmenter()
            self.assertIsNone(segmenter.process_location({"lat": None, "lon": None}))

    def test_handler_post_and_get(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            location.trip_segmenter = location.TripSegmenter()
            payload = {
                "locations": [
                    {
                        "geometry": {"coordinates": [-73.0, 40.0, 0]},
                        "properties": {"speed": 0.4, "motion": ["walking"]},
                    }
                ]
            }
            body = json.dumps(payload).encode()

            class DummyHandler(location.LocationHandler):
                def __init__(self, body_bytes):
                    self.rfile = io.BytesIO(body_bytes)
                    self.wfile = io.BytesIO()
                    self.headers = {"Content-Length": str(len(body_bytes))}
                    self.response_code = None

                def send_response(self, code):
                    self.response_code = code

                def send_header(self, *args, **kwargs):
                    pass

                def end_headers(self):
                    pass

            handler = DummyHandler(body)
            handler.do_POST()
            self.assertEqual(handler.response_code, 200)

            handler_get = DummyHandler(b"")
            handler_get.do_GET()
            self.assertEqual(handler_get.response_code, 200)
            self.assertIn(b"Location receiver active", handler_get.wfile.getvalue())

            handler_get.log_message("test")

    def test_handler_post_handles_trip_and_invalid_json(self):
        with load_service_module(LOCATION_PATH, env={"SAMARA_MIND_PATH": self.mind_path}) as location:
            location.trip_segmenter = location.TripSegmenter()
            trip = {
                "start_place": "Home",
                "end_place": "Office",
                "distance_m": 500,
                "duration_s": 120,
                "mode": "walking",
            }

            class DummyHandler(location.LocationHandler):
                def __init__(self, body_bytes):
                    self.rfile = io.BytesIO(body_bytes)
                    self.wfile = io.BytesIO()
                    self.headers = {"Content-Length": str(len(body_bytes))}
                    self.response_code = None

                def send_response(self, code):
                    self.response_code = code

                def send_header(self, *args, **kwargs):
                    pass

                def end_headers(self):
                    pass

            payload = {
                "locations": [
                    {
                        "geometry": {"coordinates": [-73.0, 40.0, 0]},
                        "properties": {"speed": 0.4, "motion": ["walking"]},
                    }
                ]
            }
            body = json.dumps(payload).encode()
            handler = DummyHandler(body)
            with mock.patch.object(location.trip_segmenter, "process_location", return_value=trip):
                handler.do_POST()

            event_path = Path(self.mind_path) / "system" / "senses" / "location.event.json"
            self.assertTrue(event_path.exists())

            bad_handler = DummyHandler(b"{bad json}")
            bad_handler.do_POST()
            self.assertEqual(bad_handler.response_code, 500)
