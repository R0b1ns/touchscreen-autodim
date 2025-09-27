#!/bin/bash
# Autodim Configure - reliably detects the touchscreen

CONF_PATH="$(dirname "$(realpath "$0")")/autodim.conf"

echo "Please tap once on the touchscreen..."
echo "Press CTRL+C to cancel."

python3 << EOF
import evdev, select, os

CONF_PATH = "$CONF_PATH"

# List all event devices
devices = [evdev.InputDevice(d) for d in evdev.list_devices()]
fds = {dev.fd: dev for dev in devices}

# Wait for the first event
while True:
    r, _, _ = select.select(fds.keys(), [], [])
    for fd in r:
        dev = fds[fd]
        for event in dev.read():
            # Found first input event
            touch_device = dev.path
            with open(CONF_PATH, 'r') as f:
                lines = f.readlines()
            with open(CONF_PATH, 'w') as f:
                for line in lines:
                    if line.startswith('device ='):
                        f.write(f'device = {touch_device}\n')
                    else:
                        f.write(line)
            print(f"Touchscreen device detected: {touch_device}")
            exit(0)
EOF
