#!/bin/bash
# Autodim Configure - automatic touchscreen detection

set -e

CONF_PATH="$(dirname "$(realpath "$0")")/autodim.conf"
SERVICE_NAME="autodim.service"

echo "=================================="
echo " Autodim Touchscreen Configuration"
echo "=================================="
echo
echo "Please tap once on the touchscreen..."
echo "Waiting for touch input (CTRL+C to cancel)."
echo

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PIDS=()

# Monitor all input devices simultaneously
for dev in /dev/input/event*; do
    [ -e "$dev" ] || continue

    (
        sudo evtest "$dev" 2>/dev/null |
        while IFS= read -r line; do
            if [[ "$line" == *"BTN_TOUCH"* && "$line" == *"value 1"* ]] ||
               [[ "$line" == *"ABS_MT_TRACKING_ID"* && "$line" == *"value"* && "$line" != *"value -1"* ]]; then
                echo "$dev" > "$TMP_DIR/detected"
                exit 0
            fi
        done
    ) &

    PIDS+=($!)
done

# Wait until a device reports a touch
while [ ! -s "$TMP_DIR/detected" ]; do
    sleep 0.1
done

TOUCH_DEVICE=$(cat "$TMP_DIR/detected")

# Stop all monitors
kill "${PIDS[@]}" 2>/dev/null || true
wait 2>/dev/null || true

echo
echo "Touchscreen detected: $TOUCH_DEVICE"

# Update configuration
if grep -q '^device =' "$CONF_PATH"; then
    sed -i "s|^device =.*|device = $TOUCH_DEVICE|" "$CONF_PATH"
else
    echo "device = $TOUCH_DEVICE" >> "$CONF_PATH"
fi

echo "Configuration updated: $CONF_PATH"

echo
echo "Restarting autodim service..."
sudo systemctl restart "$SERVICE_NAME"

echo "Done!"
