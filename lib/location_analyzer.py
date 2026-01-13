#!/usr/bin/env python3
"""
Location Analyzer for Claude's temporal awareness system.

Provides location-aware context for proactive engagement:
- Place detection (home, office, etc.)
- Arrival/departure detection
- Movement patterns
- Location-based triggers

Uses data from Overland GPS tracker via location-receiver.

Usage:
    from location_analyzer import LocationAnalyzer

    analyzer = LocationAnalyzer()
    current = analyzer.get_current_location()
    triggers = analyzer.get_location_triggers()
"""

import os
import json
import math
from datetime import datetime, timedelta
from pathlib import Path
from mind_paths import get_mind_path
from typing import Optional

MIND_PATH = get_mind_path()
STATE_PATH = MIND_PATH / "state"
LOCATION_FILE = STATE_PATH / "location.json"
HISTORY_FILE = STATE_PATH / "location-history.jsonl"
PLACES_FILE = STATE_PATH / "places.json"
LOCATION_STATE_FILE = STATE_PATH / "location-state.json"


class LocationAnalyzer:
    """Analyzes location data for proactive engagement."""

    def __init__(self):
        self.places = self._load_places()
        self.previous_state = self._load_previous_state()

    def get_current_location(self) -> Optional[dict]:
        """Get the most recent location data."""
        if not LOCATION_FILE.exists():
            return None

        try:
            with open(LOCATION_FILE) as f:
                return json.load(f)
        except:
            return None

    def get_location_history(self, hours: int = 24) -> list:
        """Get location history for the last N hours."""
        if not HISTORY_FILE.exists():
            return []

        cutoff = datetime.now() - timedelta(hours=hours)
        history = []

        try:
            with open(HISTORY_FILE) as f:
                for line in f:
                    if not line.strip():
                        continue
                    entry = json.loads(line)
                    try:
                        ts = datetime.fromisoformat(entry.get("timestamp", ""))
                        if ts >= cutoff:
                            history.append(entry)
                    except:
                        pass
        except:
            pass

        return history

    def detect_place(self, lat: float, lon: float) -> Optional[dict]:
        """
        Match coordinates to a known place.

        Returns place dict if within radius, None otherwise.
        """
        if not lat or not lon:
            return None

        for place in self.places:
            place_lat = place.get("lat")
            place_lon = place.get("lon")
            radius = place.get("radius_m", 100)

            if place_lat and place_lon:
                distance = self._haversine_distance(lat, lon, place_lat, place_lon)
                if distance <= radius:
                    return place

        return None

    def detect_place_by_wifi(self, wifi: str) -> Optional[dict]:
        """Match WiFi network name to a known place."""
        if not wifi:
            return None

        for place in self.places:
            wifi_hints = place.get("wifi_hints", [])
            if wifi in wifi_hints:
                return place

        return None

    def get_current_place(self) -> Optional[dict]:
        """Get the place for the current location."""
        location = self.get_current_location()
        if not location:
            return None

        # Try WiFi first (more reliable indoors)
        wifi = location.get("wifi")
        if wifi:
            place = self.detect_place_by_wifi(wifi)
            if place:
                return place

        # Fall back to coordinates
        lat = location.get("lat")
        lon = location.get("lon")
        return self.detect_place(lat, lon)

    def detect_state_change(self) -> Optional[dict]:
        """
        Detect arrival/departure from places.

        Compares current state to previous state.
        Returns dict with change info, or None if no significant change.
        """
        current_location = self.get_current_location()
        if not current_location:
            return None

        current_place = self.get_current_place()
        current_place_name = current_place.get("name") if current_place else None

        previous_place_name = self.previous_state.get("place_name")
        previous_timestamp = self.previous_state.get("timestamp")

        # Check for stale data (no update in 30+ minutes)
        if current_location.get("timestamp"):
            try:
                last_update = datetime.fromisoformat(current_location["timestamp"])
                if datetime.now() - last_update > timedelta(minutes=30):
                    return {
                        "type": "stale_data",
                        "message": "Location data is stale (>30 min old)",
                        "last_update": current_location["timestamp"]
                    }
            except:
                pass

        # Detect state change
        change = None
        if current_place_name != previous_place_name:
            if current_place_name and not previous_place_name:
                # Arrived at a known place
                change = {
                    "type": "arrived",
                    "place": current_place_name,
                    "place_label": current_place.get("label", current_place_name),
                    "place_type": current_place.get("type", "unknown")
                }
            elif previous_place_name and not current_place_name:
                # Departed from a known place
                change = {
                    "type": "departed",
                    "place": previous_place_name,
                    "place_label": self.previous_state.get("place_label", previous_place_name)
                }
            elif current_place_name and previous_place_name:
                # Moved between known places
                change = {
                    "type": "moved",
                    "from_place": previous_place_name,
                    "to_place": current_place_name,
                    "to_place_label": current_place.get("label", current_place_name)
                }

        # Update stored state
        new_state = {
            "timestamp": datetime.now().isoformat(),
            "place_name": current_place_name,
            "place_label": current_place.get("label") if current_place else None,
            "lat": current_location.get("lat"),
            "lon": current_location.get("lon")
        }
        self._save_state(new_state)
        self.previous_state = new_state

        return change

    def is_moving(self) -> bool:
        """Check if the collaborator appears to be in motion."""
        location = self.get_current_location()
        if not location:
            return False

        # Check speed
        speed = location.get("speed", 0)
        if speed and speed > 1:  # More than 1 m/s (walking pace)
            return True

        # Check motion state from Overland
        motion = location.get("motion", [])
        if "walking" in motion or "running" in motion or "automotive" in motion or "cycling" in motion:
            return True

        return False

    def get_battery_level(self) -> Optional[float]:
        """Get current battery level (0.0 - 1.0) from location data."""
        location = self.get_current_location()
        if not location:
            return None
        return location.get("battery")

    def get_battery_triggers(self) -> list:
        """Get battery-based triggers."""
        triggers = []
        battery = self.get_battery_level()

        if battery is None:
            return triggers

        battery_pct = int(battery * 100)

        if battery < 0.10:
            triggers.append({
                "type": "battery",
                "subtype": "critical",
                "confidence": 0.6,
                "reason": f"Phone battery is critical ({battery_pct}%)",
                "suggested_message": f"Your phone's at {battery_pct}% - anything urgent before it dies?",
                "suppress_non_urgent": True
            })
        elif battery < 0.20:
            triggers.append({
                "type": "battery",
                "subtype": "low",
                "confidence": 0.3,
                "reason": f"Phone battery is low ({battery_pct}%)",
                "suggested_message": None,
                "suppress_non_urgent": True
            })

        return triggers

    def get_location_triggers(self) -> list:
        """
        Get location-based triggers for proactive engagement.

        Returns list of trigger dicts with confidence scores.
        """
        triggers = []
        now = datetime.now()
        hour = now.hour

        # Check for state change
        state_change = self.detect_state_change()

        if state_change:
            change_type = state_change.get("type")

            if change_type == "arrived":
                place = state_change.get("place")
                place_type = state_change.get("place_type")

                if place == "home":
                    # Arrived home
                    if 17 <= hour <= 21:
                        # Evening arrival - higher confidence
                        triggers.append({
                            "type": "location",
                            "subtype": "arrived_home_evening",
                            "confidence": 0.65,
                            "reason": "Just got home (evening)",
                            "suggested_message": "How was your day?"
                        })
                    else:
                        triggers.append({
                            "type": "location",
                            "subtype": "arrived_home",
                            "confidence": 0.4,
                            "reason": "Arrived home",
                            "suggested_message": None
                        })
                else:
                    # Arrived at other known place
                    triggers.append({
                        "type": "location",
                        "subtype": "arrived_place",
                        "confidence": 0.3,
                        "reason": f"Arrived at {state_change.get('place_label', place)}",
                        "suggested_message": None
                    })

            elif change_type == "departed":
                place = state_change.get("place")

                if place == "home":
                    if 6 <= hour <= 10:
                        # Morning departure - good for briefing
                        triggers.append({
                            "type": "location",
                            "subtype": "left_home_morning",
                            "confidence": 0.5,
                            "reason": "Left home (morning)",
                            "suggested_message": "Good morning! Anything I can help with today?"
                        })
                    else:
                        triggers.append({
                            "type": "location",
                            "subtype": "left_home",
                            "confidence": 0.3,
                            "reason": "Left home",
                            "suggested_message": None
                        })

            elif change_type == "stale_data":
                # Don't trigger on stale data, but log it
                triggers.append({
                    "type": "location",
                    "subtype": "stale",
                    "confidence": 0.0,
                    "reason": state_change.get("message"),
                    "suggested_message": None
                })

        # Check if moving (suppress proactive messages while in transit)
        if self.is_moving():
            triggers.append({
                "type": "location",
                "subtype": "in_motion",
                "confidence": 0.0,  # Zero confidence = don't engage
                "reason": "In motion (suppress proactive messages)",
                "suggested_message": None,
                "suppress_engagement": True
            })

        return triggers

    def get_location_summary(self) -> str:
        """Get a human-readable location summary for context."""
        location = self.get_current_location()
        if not location:
            return "Location: Unknown (no recent data)"

        lines = ["## Location Context"]

        # Current place
        place = self.get_current_place()
        if place:
            lines.append(f"**Current location:** {place.get('label', place.get('name'))}")
        else:
            lat = location.get("lat")
            lon = location.get("lon")
            if lat and lon:
                lines.append(f"**Current location:** {lat:.4f}, {lon:.4f} (unknown place)")
            else:
                lines.append("**Current location:** Unknown")

        # Motion state
        if self.is_moving():
            motion = location.get("motion", [])
            lines.append(f"**Status:** In motion ({', '.join(motion) if motion else 'moving'})")
        else:
            lines.append("**Status:** Stationary")

        # Battery
        battery = location.get("battery")
        if battery:
            lines.append(f"**Battery:** {int(battery * 100)}%")

        # Last update
        timestamp = location.get("timestamp")
        if timestamp:
            try:
                ts = datetime.fromisoformat(timestamp)
                ago = datetime.now() - ts
                if ago.total_seconds() < 60:
                    ago_str = "just now"
                elif ago.total_seconds() < 3600:
                    ago_str = f"{int(ago.total_seconds() / 60)} min ago"
                else:
                    ago_str = f"{int(ago.total_seconds() / 3600)} hours ago"
                lines.append(f"**Last update:** {ago_str}")
            except:
                pass

        return "\n".join(lines)

    def get_daily_movement_summary(self) -> dict:
        """
        Get a summary of today's movement (daily scope for check-ins).

        Returns dict with:
            - today_locations: list of distinct places visited today
            - time_at_current: hours at current location TODAY (not cumulative)
            - has_left_home: whether they've left home today
            - most_recent_trip: info about last non-home location if any
        """
        now = datetime.now()
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

        history = self.get_location_history(hours=24)

        # Filter to just today
        today_history = []
        for entry in history:
            try:
                ts = datetime.fromisoformat(entry.get("timestamp", ""))
                if ts >= today_start:
                    today_history.append(entry)
            except:
                pass

        if not today_history:
            return {
                "today_locations": [],
                "time_at_current": 0,
                "has_left_home": False,
                "most_recent_trip": None,
                "summary": "No location data for today yet."
            }

        # Identify distinct locations visited today
        home_coords = None
        for place in self.places:
            if place.get("name") == "home":
                home_coords = (place.get("lat"), place.get("lon"))
                break

        today_locations = []
        has_left_home = False
        most_recent_trip = None

        for entry in today_history:
            lat, lon = entry.get("lat"), entry.get("lon")
            if lat and lon:
                place = self.detect_place(lat, lon)
                place_name = place.get("name") if place else "unknown"

                if place_name != "home":
                    has_left_home = True
                    most_recent_trip = {
                        "lat": lat,
                        "lon": lon,
                        "time": entry.get("timestamp"),
                        "place": place.get("label") if place else None
                    }

                if place_name not in today_locations:
                    today_locations.append(place_name)

        # Calculate time at current location TODAY
        current_place = self.get_current_place()
        current_place_name = current_place.get("name") if current_place else "unknown"

        time_at_current = 0
        last_arrival = None

        for entry in today_history:
            lat, lon = entry.get("lat"), entry.get("lon")
            if lat and lon:
                place = self.detect_place(lat, lon)
                place_name = place.get("name") if place else "unknown"

                if place_name == current_place_name:
                    if last_arrival is None:
                        try:
                            last_arrival = datetime.fromisoformat(entry.get("timestamp", ""))
                        except:
                            pass
                else:
                    # Left current place, reset
                    if last_arrival:
                        try:
                            departed = datetime.fromisoformat(entry.get("timestamp", ""))
                            time_at_current += (departed - last_arrival).total_seconds() / 3600
                        except:
                            pass
                    last_arrival = None

        # Add time from last arrival to now
        if last_arrival:
            time_at_current += (now - last_arrival).total_seconds() / 3600

        # Generate human-readable summary
        if not has_left_home:
            summary = f"Home all day so far ({time_at_current:.1f}h today)."
        elif len(today_locations) > 1:
            summary = f"Been to {len(today_locations)} places today. Currently at {current_place_name} ({time_at_current:.1f}h)."
        else:
            summary = f"At {current_place_name} ({time_at_current:.1f}h today)."

        return {
            "today_locations": today_locations,
            "time_at_current": round(time_at_current, 1),
            "has_left_home": has_left_home,
            "most_recent_trip": most_recent_trip,
            "summary": summary
        }

    def _load_places(self) -> list:
        """Load known places from registry."""
        if not PLACES_FILE.exists():
            return []

        try:
            with open(PLACES_FILE) as f:
                data = json.load(f)
                return data.get("places", [])
        except:
            return []

    def _load_previous_state(self) -> dict:
        """Load previous location state."""
        if not LOCATION_STATE_FILE.exists():
            return {}

        try:
            with open(LOCATION_STATE_FILE) as f:
                return json.load(f)
        except:
            return {}

    def _save_state(self, state: dict):
        """Save current location state."""
        try:
            with open(LOCATION_STATE_FILE, 'w') as f:
                json.dump(state, f, indent=2)
        except:
            pass

    def _haversine_distance(self, lat1: float, lon1: float,
                            lat2: float, lon2: float) -> float:
        """
        Calculate distance between two points in meters.

        Uses Haversine formula for spherical Earth.
        """
        R = 6371000  # Earth's radius in meters

        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)

        a = (math.sin(delta_phi / 2) ** 2 +
             math.cos(phi1) * math.cos(phi2) *
             math.sin(delta_lambda / 2) ** 2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

        return R * c


def main():
    """CLI interface for location analyzer."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: location_analyzer.py <command>")
        print("Commands:")
        print("  current   - Get current location")
        print("  place     - Get current place")
        print("  triggers  - Get location triggers")
        print("  summary   - Get location summary")
        print("  history   - Get recent location history")
        print("  daily     - Get daily movement summary (for check-ins)")
        sys.exit(1)

    command = sys.argv[1]
    analyzer = LocationAnalyzer()

    if command == "current":
        location = analyzer.get_current_location()
        print(json.dumps(location, indent=2, default=str))

    elif command == "place":
        place = analyzer.get_current_place()
        if place:
            print(json.dumps(place, indent=2))
        else:
            print("Not at a known place")

    elif command == "triggers":
        triggers = analyzer.get_location_triggers()
        print(json.dumps(triggers, indent=2, default=str))

    elif command == "summary":
        print(analyzer.get_location_summary())

    elif command == "daily":
        daily = analyzer.get_daily_movement_summary()
        print(json.dumps(daily, indent=2, default=str))

    elif command == "history":
        hours = int(sys.argv[2]) if len(sys.argv) > 2 else 24
        history = analyzer.get_location_history(hours)
        print(f"Found {len(history)} location records in last {hours} hours")
        for entry in history[-5:]:  # Last 5
            print(json.dumps(entry))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
