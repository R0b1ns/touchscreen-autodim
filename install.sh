#!/bin/bash
# Autodim Installer mit automatischer Erkennung von Backlight & Input Device

SCRIPT_PATH="$(realpath autodim.py)"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SERVICE_NAME="autodim.service"
VENV_DIR="$SCRIPT_DIR/.venv"

# --- Backlight automatisch erkennen ---
BACKLIGHT_PATH=$(ls /sys/class/backlight | head -n1)
if [ -z "$BACKLIGHT_PATH" ]; then
    echo "Kein Backlight Device gefunden!"
    exit 1
fi
BACKLIGHT_PATH="/sys/class/backlight/$BACKLIGHT_PATH/brightness"

# --- Input Device automatisch erkennen ---
# erstes eventX, das kein mouse device ist
INPUT_DEVICE=$(ls /dev/input/event* | head -n1)
if [ -z "$INPUT_DEVICE" ]; then
    echo "Kein Input Device gefunden!"
    exit 1
fi

# --- .conf anpassen ---
CONF_PATH="$SCRIPT_DIR/autodim.conf"
cat << EOF > "$CONF_PATH"
[autodim]
device = $INPUT_DEVICE
brightness_max = 31
brightness_low = 5
brightness_min = 0
idle_dim = 10
idle_off = 3600
backlight_path = $BACKLIGHT_PATH
EOF

# --- VENV erstellen ---
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install evdev
deactivate

# --- Systemd-Service erstellen ---
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

# --- Systemd aktivieren & starten ---
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

echo "Autodim installiert, .venv erstellt, Backlight und Input Device automatisch erkannt."
