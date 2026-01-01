#!/usr/bin/env python3
"""Location receiver for Overland GPS data with history tracking."""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime
import os

STATE_DIR = os.path.expanduser("~/.claude-mind/state")
LOCATION_FILE = os.path.join(STATE_DIR, "location.json")
HISTORY_FILE = os.path.join(STATE_DIR, "location-history.jsonl")

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

                location_data = {
                    'timestamp': datetime.now().isoformat(),
                    'lon': coords[0] if len(coords) > 0 else None,
                    'lat': coords[1] if len(coords) > 1 else None,
                    'altitude': coords[2] if len(coords) > 2 else None,
                    'speed': props.get('speed'),
                    'battery': props.get('battery_level'),
                    'wifi': props.get('wifi'),
                    'motion': props.get('motion', []),
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

                print(f"[{location_data['timestamp']}] Location: {location_data['lat']}, {location_data['lon']}")
            
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
    server = HTTPServer(('0.0.0.0', 8081), LocationHandler)
    print("Location receiver running on port 8081")
    server.serve_forever()
