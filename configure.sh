#!/bin/bash
# Autodim Configure - reliably detects the touchscreen input device

CONF_PATH="$(dirname "$(realpath "$0")")/autodim.conf"

echo "Please tap once on the touchscreen..."
echo "Press CTRL+C to cancel."

# --- List all event devices ---
DEVICES=$(ls /dev/input/event*)

TOUCH_DEVICE=""

# Loop until a device is detected from the touch input
while [ -z "$TOUCH_DEVICE" ]; do
    for DEV in $DEVICES; do
        # --- Check if device can provide events ---
        # Use evtest in non-blocking mode with timeout
        OUTPUT=$(sudo timeout 2 evtest "$DEV" 2>&1 | grep -m1 "EV_KEY\|EV_ABS")
        if [ ! -z "$OUTPUT" ]; then
            TOUCH_DEVICE="$DEV"
            break
        fi
    done
done

# --- Write detected device to .conf ---
sed -i "s|device = .*|device = $TOUCH_DEVICE|" "$CONF_PATH"

echo "Touchscreen device detected: $TOUCH_DEVICE"
echo "Autodim configuration updated."
