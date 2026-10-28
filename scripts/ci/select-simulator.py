"""Select an installed iPhone simulator, preferring the newest iOS runtime."""
import json
import re
import sys

with open(sys.argv[1]) as source:
    devices = json.load(source)["devices"]
candidates = []
for runtime, entries in devices.items():
    version = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if version:
        for device in entries:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append((tuple(map(int, version[1].split("-"))), device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator found in the selected Xcode environment")
print(f"SIMULATOR_ID={max(candidates)[1]}")
