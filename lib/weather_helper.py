#!/usr/bin/env python3
"""
Weather helper for Claude's temporal awareness system.

Fetches weather data based on current location.
Uses Open-Meteo API (free, no API key required).

Usage:
    from weather_helper import WeatherHelper

    weather = WeatherHelper()
    current = weather.get_current_weather()
    summary = weather.get_weather_summary()
"""

import os
import json
import urllib.request
import urllib.error
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

MIND_PATH = Path(os.path.expanduser("~/.claude-mind"))
STATE_PATH = MIND_PATH / "state"
LOCATION_FILE = STATE_PATH / "location.json"
WEATHER_CACHE_FILE = STATE_PATH / "weather-cache.json"

# Open-Meteo API (free, no key required)
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

# Weather code descriptions (WMO codes)
WEATHER_CODES = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Foggy",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    66: "Light freezing rain",
    67: "Heavy freezing rain",
    71: "Slight snow",
    73: "Moderate snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Slight rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    85: "Slight snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm with slight hail",
    99: "Thunderstorm with heavy hail",
}


class WeatherHelper:
    """Fetches and analyzes weather data."""

    def __init__(self):
        self.cache_duration = timedelta(minutes=30)

    def get_current_weather(self) -> Optional[dict]:
        """
        Get current weather for the collaborator's location.

        Returns dict with temperature, conditions, etc.
        Uses cache if recent enough.
        """
        # Check cache first
        cached = self._load_cache()
        if cached:
            return cached

        # Get location
        location = self._get_location()
        if not location:
            return None

        lat = location.get("lat")
        lon = location.get("lon")
        if not lat or not lon:
            return None

        # Fetch weather
        weather = self._fetch_weather(lat, lon)
        if weather:
            self._save_cache(weather)

        return weather

    def get_weather_summary(self) -> str:
        """Get a human-readable weather summary for context."""
        weather = self.get_current_weather()
        if not weather:
            return "## Weather\nUnable to fetch weather data."

        lines = ["## Weather Context"]

        current = weather.get("current", {})
        temp = current.get("temperature")
        feels_like = current.get("feels_like")
        condition = current.get("condition")
        humidity = current.get("humidity")

        if temp is not None:
            temp_f = round(temp * 9/5 + 32)  # Convert to Fahrenheit
            feels_f = round(feels_like * 9/5 + 32) if feels_like else temp_f
            lines.append(f"**Now:** {temp_f}°F (feels like {feels_f}°F)")

        if condition:
            lines.append(f"**Conditions:** {condition}")

        # Precipitation forecast
        precip = weather.get("precipitation_next_hours")
        if precip:
            lines.append(f"**Next few hours:** {precip}")

        # Alerts or notable conditions
        alerts = self._check_notable_conditions(weather)
        if alerts:
            lines.append(f"**Note:** {'; '.join(alerts)}")

        return "\n".join(lines)

    def get_weather_triggers(self) -> list:
        """Get weather-based triggers for proactive engagement."""
        triggers = []
        weather = self.get_current_weather()

        if not weather:
            return triggers

        current = weather.get("current", {})
        hourly = weather.get("hourly", {})

        # Check for rain coming
        if hourly:
            precip_probs = hourly.get("precipitation_probability", [])[:6]  # Next 6 hours
            if any(p > 60 for p in precip_probs) and precip_probs[0] < 30:
                triggers.append({
                    "type": "weather",
                    "subtype": "rain_coming",
                    "confidence": 0.4,
                    "reason": "Rain likely in the next few hours",
                    "suggested_message": "Heads up - looks like rain is coming. Might want an umbrella if you're heading out."
                })

        # Check for extreme temperatures
        temp = current.get("temperature")
        if temp is not None:
            temp_f = temp * 9/5 + 32
            if temp_f > 95:
                triggers.append({
                    "type": "weather",
                    "subtype": "extreme_heat",
                    "confidence": 0.3,
                    "reason": f"Very hot today ({temp_f:.0f}°F)",
                    "suggested_message": None
                })
            elif temp_f < 20:
                triggers.append({
                    "type": "weather",
                    "subtype": "extreme_cold",
                    "confidence": 0.3,
                    "reason": f"Very cold today ({temp_f:.0f}°F)",
                    "suggested_message": None
                })

        # Check for storms
        weather_code = current.get("weather_code", 0)
        if weather_code >= 95:
            triggers.append({
                "type": "weather",
                "subtype": "storm",
                "confidence": 0.5,
                "reason": "Thunderstorm conditions",
                "suggested_message": None
            })

        return triggers

    def _fetch_weather(self, lat: float, lon: float) -> Optional[dict]:
        """Fetch weather from Open-Meteo API."""
        params = {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m",
            "hourly": "temperature_2m,precipitation_probability,weather_code",
            "forecast_days": 1,
            "timezone": "auto"
        }

        query_string = "&".join(f"{k}={v}" for k, v in params.items())
        url = f"{OPEN_METEO_URL}?{query_string}"

        try:
            with urllib.request.urlopen(url, timeout=10) as response:
                data = json.loads(response.read().decode())

            # Parse response
            current = data.get("current", {})
            hourly = data.get("hourly", {})

            weather_code = current.get("weather_code", 0)
            condition = WEATHER_CODES.get(weather_code, "Unknown")

            # Analyze precipitation for next few hours
            precip_probs = hourly.get("precipitation_probability", [])[:6]
            if any(p > 50 for p in precip_probs):
                precip_desc = "Rain likely"
            elif any(p > 20 for p in precip_probs):
                precip_desc = "Chance of rain"
            else:
                precip_desc = "Dry"

            return {
                "timestamp": datetime.now().isoformat(),
                "location": {"lat": lat, "lon": lon},
                "current": {
                    "temperature": current.get("temperature_2m"),
                    "feels_like": current.get("apparent_temperature"),
                    "humidity": current.get("relative_humidity_2m"),
                    "wind_speed": current.get("wind_speed_10m"),
                    "weather_code": weather_code,
                    "condition": condition
                },
                "hourly": {
                    "temperatures": hourly.get("temperature_2m", [])[:12],
                    "precipitation_probability": precip_probs,
                    "weather_codes": hourly.get("weather_code", [])[:12]
                },
                "precipitation_next_hours": precip_desc
            }

        except (urllib.error.URLError, json.JSONDecodeError, KeyError) as e:
            print(f"[WeatherHelper] Error fetching weather: {e}")
            return None

    def _check_notable_conditions(self, weather: dict) -> list:
        """Check for notable weather conditions worth mentioning."""
        alerts = []
        current = weather.get("current", {})

        # High wind
        wind = current.get("wind_speed", 0)
        if wind > 40:  # km/h
            alerts.append("Very windy")
        elif wind > 25:
            alerts.append("Breezy")

        # Low humidity (dry)
        humidity = current.get("humidity", 50)
        if humidity < 20:
            alerts.append("Very dry air")

        # Precipitation coming
        precip = weather.get("precipitation_next_hours", "")
        if "likely" in precip.lower():
            alerts.append("Rain expected")

        return alerts

    def _get_location(self) -> Optional[dict]:
        """Get current location from location file."""
        if not LOCATION_FILE.exists():
            return None

        try:
            with open(LOCATION_FILE) as f:
                return json.load(f)
        except:
            return None

    def _load_cache(self) -> Optional[dict]:
        """Load cached weather if still valid."""
        if not WEATHER_CACHE_FILE.exists():
            return None

        try:
            with open(WEATHER_CACHE_FILE) as f:
                cached = json.load(f)

            # Check if cache is still valid
            cached_time = datetime.fromisoformat(cached.get("timestamp", ""))
            if datetime.now() - cached_time < self.cache_duration:
                return cached

        except:
            pass

        return None

    def _save_cache(self, weather: dict):
        """Save weather to cache."""
        try:
            with open(WEATHER_CACHE_FILE, 'w') as f:
                json.dump(weather, f, indent=2)
        except:
            pass


def main():
    """CLI interface for weather helper."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: weather_helper.py <command>")
        print("Commands:")
        print("  current   - Get current weather")
        print("  summary   - Get weather summary")
        print("  triggers  - Get weather triggers")
        sys.exit(1)

    command = sys.argv[1]
    helper = WeatherHelper()

    if command == "current":
        weather = helper.get_current_weather()
        print(json.dumps(weather, indent=2, default=str))

    elif command == "summary":
        print(helper.get_weather_summary())

    elif command == "triggers":
        triggers = helper.get_weather_triggers()
        print(json.dumps(triggers, indent=2, default=str))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
