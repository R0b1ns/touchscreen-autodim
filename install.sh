#!/bin/bash
# Autodim Installer - pure installation

SCRIPT_PATH="$(realpath autodim.sh)"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SERVICE_NAME="autodim.service"
CONF_PATH="$SCRIPT_DIR/autodim.conf"

# --- Automatically detect backlight ---
BACKLIGHT_PATH=$(ls /sys/class/backlight | head -n1)
if [ -z "$BACKLIGHT_PATH" ]; then
    echo "No backlight device found!"
    exit 1
fi
BACKLIGHT_PATH="/sys/class/backlight/$BACKLIGHT_PATH/brightness"

# --- Create default .conf ---
cat << EOF > "$CONF_PATH"
[autodim]
device = /dev/input/eventX
brightness_max = 31
brightness_low = 5
brightness_min = 0
idle_dim = 10
idle_off = 0
night_start=22
night_end=6
night_idle_off=30
backlight_path = $BACKLIGHT_PATH
EOF

# --- Create systemd service ---

cat << EOF | sudo tee /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Autodim Touchscreen
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/bash $SCRIPT_PATH
Restart=always
RestartSec=3
User=root
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

sudo apt install yad

echo "Autodim installed, service started."
echo "Please run configure.sh to set up the touchscreen device."
