#!/bin/bash
# Autodim Installer - pure installation

SCRIPT_PATH="$(realpath autodim.py)"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SERVICE_NAME="autodim.service"
VENV_DIR="$SCRIPT_DIR/.venv"
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
idle_off = 3600
backlight_path = $BACKLIGHT_PATH
EOF

# --- Create Python virtual environment ---
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install evdev
deactivate

# --- Create systemd service ---
cat << EOF | sudo tee /etc/systemd/system/$SERVICE_NAME
[Unit]
Description=Autodim Raspberry Pi Touchscreen
After=multi-user.target

[Service]
Type=simple
ExecStart=$VENV_DIR/bin/python $SCRIPT_PATH
Restart=always
User=pi
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

echo "Autodim installed, .venv created and service started."
echo "Please run configure.sh to set up the touchscreen device."
