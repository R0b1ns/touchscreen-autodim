#!/bin/bash
# Autodim Configure - reliably detects the touchscreen input device using actual input events

CONF_PATH="$(dirname "$(realpath "$0")")/autodim.conf"

echo "Please tap once on the touchscreen..."
echo "Press CTRL+C to cancel."

# --- List all event devices ---
DEVICES=$(ls /dev/input/event*)

# --- Python one-liner to detect the first device producing events ---
TOUCH_DEVICE=$(python3 <<EOF
import evdev, select

devices = [evdev.InputDevice(d) for d in "$DEVICES".split()]
fds = {dev.fd: dev for dev in devices}

# Wait for the first event
while True:
    r, _, _ = select.select(fds.keys(), [], [])
    for fd in r:
        dev = fds[fd]
        for event in dev.read():
            print(dev.path)
            exit(0)
EOF
)

# --- Write detected device to .conf ---
sed -i "s|device = .*|device = $TOUCH_DEVICE|" "$CONF_PATH"

echo "Touchscreen device detected: $TOUCH_DEVICE"
echo "Autodim configuration updated."
