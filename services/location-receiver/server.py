#!/usr/bin/env python3
"""Location receiver for Overland GPS data with trip segmentation and history tracking."""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any, Tuple
import os
import math


def resolve_mind_dir() -> str:
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return os.path.expanduser(override)
    return os.path.expanduser("~/.claude-mind")


MIND_DIR = resolve_mind_dir()
STATE_DIR = os.path.join(MIND_DIR, "state")
SENSES_DIR = os.path.join(MIND_DIR, "senses")
PORT = int(os.environ.get("SAMARA_LOCATION_PORT", "8081"))
LOCATION_FILE = os.path.join(STATE_DIR, "location.json")
HISTORY_FILE = os.path.join(STATE_DIR, "location-history.jsonl")
TRIPS_FILE = os.path.join(STATE_DIR, "trips.jsonl")
PLACES_FILE = os.path.join(STATE_DIR, "places.json")
SUBWAY_FILE = os.path.join(STATE_DIR, "subway-stations.json")
LOCATION_EVENT_FILE = os.path.join(SENSES_DIR, "location.event.json")

# Trip segmentation constants
STATIONARY_THRESHOLD_M = 50  # Movement less than this = stationary
STATIONARY_TIME_S = 300  # 5 minutes stationary = trip boundary
MIN_TRIP_DISTANCE_M = 200  # Ignore micro-trips shorter than this
SIMPLIFICATION_TOLERANCE_M = 20  # Douglas-Peucker tolerance


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance in meters between two lat/lon points."""
    R = 6371000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1-a))


def encode_polyline(coords: List[Tuple[float, float]], precision: int = 5) -> str:
    """Encode list of (lat, lon) tuples into Google polyline format."""
    result = []
    prev_lat, prev_lon = 0, 0

    for lat, lon in coords:
        lat_int = round(lat * (10 ** precision))
        lon_int = round(lon * (10 ** precision))

        d_lat = lat_int - prev_lat
        d_lon = lon_int - prev_lon

        for v in [d_lat, d_lon]:
            v = ~(v << 1) if v < 0 else (v << 1)
            while v >= 0x20:
                result.append(chr((0x20 | (v & 0x1f)) + 63))
                v >>= 5
            result.append(chr(v + 63))

        prev_lat, prev_lon = lat_int, lon_int

    return ''.join(result)


def perpendicular_distance(point: Dict, line_start: Dict, line_end: Dict) -> float:
    """Calculate perpendicular distance from point to line segment."""
    if line_start['lat'] == line_end['lat'] and line_start['lon'] == line_end['lon']:
        return haversine_distance(point['lat'], point['lon'], line_start['lat'], line_start['lon'])

    # Use cross-track distance formula (simplified for short distances)
    d1 = haversine_distance(line_start['lat'], line_start['lon'], point['lat'], point['lon'])
    d2 = haversine_distance(line_end['lat'], line_end['lon'], point['lat'], point['lon'])
    d3 = haversine_distance(line_start['lat'], line_start['lon'], line_end['lat'], line_end['lon'])

    if d3 == 0:
        return d1

    # Heron's formula for triangle area, then height = 2*area/base
    s = (d1 + d2 + d3) / 2
    area_sq = s * (s - d1) * (s - d2) * (s - d3)
    if area_sq <= 0:
        return min(d1, d2)
    return 2 * math.sqrt(area_sq) / d3


def douglas_peucker(points: List[Dict], tolerance: float) -> List[Dict]:
    """Simplify path using Douglas-Peucker algorithm."""
    if len(points) <= 2:
        return points

    # Find point with maximum distance from line between first and last
    max_dist = 0
    max_idx = 0

    for i in range(1, len(points) - 1):
        dist = perpendicular_distance(points[i], points[0], points[-1])
        if dist > max_dist:
            max_dist = dist
            max_idx = i

    # If max distance > tolerance, recursively simplify
    if max_dist > tolerance:
        left = douglas_peucker(points[:max_idx + 1], tolerance)
        right = douglas_peucker(points[max_idx:], tolerance)
        return left[:-1] + right
    else:
        return [points[0], points[-1]]


class TripSegmenter:
    """Segments continuous location stream into discrete trips."""

    def __init__(self):
        self.current_trip: Optional[Dict] = None
        self.last_location: Optional[Dict] = None
        self.stationary_since: Optional[datetime] = None
        self.places: List[Dict] = []
        self.subway_stations: List[Dict] = []
        self._load_reference_data()

    def _load_reference_data(self):
        """Load places and subway station data."""
        try:
            if os.path.exists(PLACES_FILE):
                with open(PLACES_FILE) as f:
                    data = json.load(f)
                    self.places = data.get('places', [])
        except Exception as e:
            print(f"Warning: Could not load places: {e}")

        try:
            if os.path.exists(SUBWAY_FILE):
                with open(SUBWAY_FILE) as f:
                    data = json.load(f)
                    self.subway_stations = data.get('stations', [])
        except Exception as e:
            print(f"Warning: Could not load subway stations: {e}")

    def _find_place(self, lat: float, lon: float) -> Optional[str]:
        """Find named place within radius of coordinates."""
        for place in self.places:
            dist = haversine_distance(lat, lon, place['lat'], place['lon'])
            if dist <= place.get('radius_m', 100):
                return place['name']
        return None

    def _find_nearby_transit(self, waypoints: List[Dict]) -> List[str]:
        """Find subway stations near any waypoint in the trip."""
        nearby = set()
        for wp in waypoints:
            for station in self.subway_stations:
                dist = haversine_distance(wp['lat'], wp['lon'], station['lat'], station['lon'])
                if dist <= 100:  # Within 100m
                    nearby.add(station['name'])
        return sorted(list(nearby))

    def _calculate_trip_distance(self, waypoints: List[Dict]) -> float:
        """Calculate total distance of trip in meters."""
        total = 0
        for i in range(1, len(waypoints)):
            total += haversine_distance(
                waypoints[i-1]['lat'], waypoints[i-1]['lon'],
                waypoints[i]['lat'], waypoints[i]['lon']
            )
        return total

    def _finalize_trip(self) -> Optional[Dict]:
        """Finalize and return current trip."""
        if not self.current_trip or len(self.current_trip['waypoints']) < 2:
            self.current_trip = None
            return None

        waypoints = self.current_trip['waypoints']

        # Calculate total distance
        distance = self._calculate_trip_distance(waypoints)

        # Skip micro-trips
        if distance < MIN_TRIP_DISTANCE_M:
            self.current_trip = None
            return None

        # Simplify waypoints
        simplified = douglas_peucker(waypoints, SIMPLIFICATION_TOLERANCE_M)

        # Encode as polyline
        coords = [(wp['lat'], wp['lon']) for wp in simplified]
        polyline = encode_polyline(coords)

        # Find start/end places
        first, last = waypoints[0], waypoints[-1]
        start_place = self._find_place(first['lat'], first['lon']) or "unknown"
        end_place = self._find_place(last['lat'], last['lon']) or "unknown"

        # Detect motion mode (most common)
        motion_counts: Dict[str, int] = {}
        for wp in waypoints:
            for m in wp.get('motion', []):
                motion_counts[m] = motion_counts.get(m, 0) + 1
        mode = max(motion_counts.items(), key=lambda x: x[1])[0] if motion_counts else "unknown"

        # Find nearby transit
        transit_near = self._find_nearby_transit(waypoints)

        # Build trip record
        trip = {
            'trip_id': self.current_trip['trip_id'],
            'start_time': self.current_trip['start_time'],
            'end_time': waypoints[-1]['timestamp'],
            'start_place': start_place,
            'end_place': end_place,
            'mode': mode,
            'waypoints': [{'lat': wp['lat'], 'lon': wp['lon'], 'time': wp['timestamp']}
                          for wp in simplified],
            'polyline': polyline,
            'distance_m': round(distance),
            'duration_s': round((datetime.fromisoformat(waypoints[-1]['timestamp']) -
                                datetime.fromisoformat(waypoints[0]['timestamp'])).total_seconds()),
            'transit_near': transit_near
        }

        self.current_trip = None
        return trip

    def process_location(self, location: Dict) -> Optional[Dict]:
        """
        Process incoming location update.
        Returns completed trip if one just ended, otherwise None.
        """
        if location.get('lat') is None or location.get('lon') is None:
            return None

        timestamp = datetime.fromisoformat(location['timestamp'])
        completed_trip = None

        # Check if we've moved significantly
        is_moving = False
        if self.last_location:
            dist = haversine_distance(
                location['lat'], location['lon'],
                self.last_location['lat'], self.last_location['lon']
            )
            speed = location.get('speed') or 0
            motion = location.get('motion', [])

            # Consider moving if: distance > threshold OR speed > 0.5 m/s OR motion != stationary
            is_moving = (dist > STATIONARY_THRESHOLD_M or
                        speed > 0.5 or
                        (motion and 'stationary' not in motion))

        if is_moving:
            self.stationary_since = None

            # Start new trip if not in one
            if not self.current_trip:
                trip_id = f"{timestamp.strftime('%Y-%m-%dT%H:%M:%S')}-{os.getpid() % 1000:03d}"
                self.current_trip = {
                    'trip_id': trip_id,
                    'start_time': location['timestamp'],
                    'waypoints': []
                }
                # Include last stationary location as trip start
                if self.last_location:
                    self.current_trip['waypoints'].append({
                        'lat': self.last_location['lat'],
                        'lon': self.last_location['lon'],
                        'timestamp': self.last_location['timestamp'],
                        'motion': self.last_location.get('motion', [])
                    })

            # Add waypoint to current trip
            self.current_trip['waypoints'].append({
                'lat': location['lat'],
                'lon': location['lon'],
                'timestamp': location['timestamp'],
                'motion': location.get('motion', [])
            })
        else:
            # Stationary
            if self.stationary_since is None:
                self.stationary_since = timestamp

            stationary_duration = (timestamp - self.stationary_since).total_seconds()

            # If stationary long enough and we have an active trip, end it
            if self.current_trip and stationary_duration >= STATIONARY_TIME_S:
                # Add final location to trip
                self.current_trip['waypoints'].append({
                    'lat': location['lat'],
                    'lon': location['lon'],
                    'timestamp': location['timestamp'],
                    'motion': location.get('motion', [])
                })
                completed_trip = self._finalize_trip()

        self.last_location = location
        return completed_trip


# Global trip segmenter instance
trip_segmenter = TripSegmenter()


def load_places() -> List[Dict]:
    """Load places from places.json."""
    try:
        if os.path.exists(PLACES_FILE):
            with open(PLACES_FILE) as f:
                data = json.load(f)
                return data.get('places', [])
    except Exception as e:
        print(f"Warning: Could not load places: {e}")
    return []


def find_matched_place(lat: float, lon: float, wifi: Optional[str] = None) -> Optional[Dict]:
    """
    Find a matching place by WiFi (preferred) or coordinates.
    Returns dict with name, label, type, and match_method.
    """
    places = load_places()

    # First try WiFi match (most reliable for indoors)
    if wifi:
        for place in places:
            wifi_hints = place.get('wifi_hints', [])
            if wifi in wifi_hints:
                return {
                    'name': place['name'],
                    'label': place.get('label', place['name']),
                    'type': place.get('type'),
                    'match_method': 'wifi'
                }

    # Fall back to coordinate match
    if lat is not None and lon is not None:
        for place in places:
            dist = haversine_distance(lat, lon, place['lat'], place['lon'])
            if dist <= place.get('radius_m', 100):
                return {
                    'name': place['name'],
                    'label': place.get('label', place['name']),
                    'type': place.get('type'),
                    'match_method': 'coordinates',
                    'distance_m': round(dist)
                }

    return None


def write_sense_event(event_type: str, data: Dict, priority: str = "normal", suggested_prompt: str = None):
    """Write a sense event in the canonical format for Samara's SenseDirectoryWatcher."""
    os.makedirs(SENSES_DIR, exist_ok=True)

    event = {
        "sense": "location",
        "timestamp": datetime.now().isoformat(),
        "priority": priority,
        "data": {
            "type": event_type,
            **data
        },
        "auth": {
            "source_id": "location-receiver"
        }
    }

    if suggested_prompt:
        event["context"] = {
            "suggested_prompt": suggested_prompt
        }

    with open(LOCATION_EVENT_FILE, 'w') as f:
        json.dump(event, f, indent=2)

class LocationHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
            locations = data.get('locations', [])

            if locations:
                latest = locations[-1]
                coords = latest.get('geometry', {}).get('coordinates', [])
                props = latest.get('properties', {})

                lat = coords[1] if len(coords) > 1 else None
                lon = coords[0] if len(coords) > 0 else None
                wifi = props.get('wifi')

                # Find matched place by WiFi or coordinates
                matched_place = find_matched_place(lat, lon, wifi)

                location_data = {
                    'timestamp': datetime.now().isoformat(),
                    'lon': lon,
                    'lat': lat,
                    'altitude': coords[2] if len(coords) > 2 else None,
                    'speed': props.get('speed'),
                    'battery': props.get('battery_level'),
                    'wifi': wifi,
                    'motion': props.get('motion', []),
                    'matched_place': matched_place,
                    'raw': latest
                }

                os.makedirs(STATE_DIR, exist_ok=True)

                # Save latest location (for quick access)
                with open(LOCATION_FILE, 'w') as f:
                    json.dump(location_data, f, indent=2)

                # Append to history (for pattern analysis)
                history_entry = {
                    'timestamp': location_data['timestamp'],
                    'lat': location_data['lat'],
                    'lon': location_data['lon'],
                    'speed': location_data['speed'],
                    'battery': location_data['battery'],
                    'wifi': location_data['wifi'],
                    'motion': location_data['motion']
                }
                with open(HISTORY_FILE, 'a') as f:
                    f.write(json.dumps(history_entry) + '\n')

                # Process through trip segmenter
                completed_trip = trip_segmenter.process_location(history_entry)
                if completed_trip:
                    with open(TRIPS_FILE, 'a') as f:
                        f.write(json.dumps(completed_trip) + '\n')
                    print(f"[TRIP] {completed_trip['start_place']} → {completed_trip['end_place']} "
                          f"({completed_trip['distance_m']}m, {completed_trip['duration_s']}s)")

                    # Write trip completion as a sense event
                    write_sense_event(
                        event_type="trip_completed",
                        data={
                            "from": completed_trip['start_place'],
                            "to": completed_trip['end_place'],
                            "distance_m": completed_trip['distance_m'],
                            "duration_s": completed_trip['duration_s'],
                            "mode": completed_trip['mode']
                        },
                        priority="normal",
                        suggested_prompt=f"A trip just completed: {completed_trip['start_place']} → {completed_trip['end_place']} ({completed_trip['distance_m']}m in {completed_trip['duration_s']}s). Consider if this is notable or if any context is relevant."
                    )

                place_str = f" @ {matched_place['name']}" if matched_place else ""
                trip_str = " [in trip]" if trip_segmenter.current_trip else ""
                print(f"[{location_data['timestamp']}] Location: {location_data['lat']}, {location_data['lon']}{place_str}{trip_str}")

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"result": "ok"}).encode())

        except Exception as e:
            print(f"Error: {e}")
            self.send_response(500)
            self.end_headers()
    
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Location receiver active")
    
    def log_message(self, format, *args):
        pass  # Suppress default logging

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', PORT), LocationHandler)
    print(f"Location receiver running on port {PORT}")
    server.serve_forever()
