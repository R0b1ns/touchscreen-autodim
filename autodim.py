#!/usr/bin/env python3
import evdev
import subprocess
import time
import configparser
import os
import select

# --- Config laden ---
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, 'autodim.conf')

config = configparser.ConfigParser()
config.read(CONFIG_PATH)
cfg = config['autodim']

DEVICE = cfg.get('device')
BRIGHTNESS_MAX = int(cfg.get('brightness_max'))
BRIGHTNESS_LOW = int(cfg.get('brightness_low'))
BRIGHTNESS_MIN = int(cfg.get('brightness_min'))
IDLE_DIM = int(cfg.get('idle_dim'))
IDLE_OFF = int(cfg.get('idle_off'))
BRIGHTNESS_PATH = cfg.get('backlight_path')

def set_brightness(value):
    subprocess.run(["sudo", "tee", BRIGHTNESS_PATH],
                   input=str(value), text=True, stdout=subprocess.DEVNULL)

# --- Initial ---
set_brightness(BRIGHTNESS_MAX)
current_brightness = BRIGHTNESS_MAX
last_event = time.time()

device = evdev.InputDevice(DEVICE)

while True:
    now = time.time()
    idle_time = now - last_event

    # Berechne Timeout für select
    if idle_time < IDLE_DIM:
        timeout = IDLE_DIM - idle_time
        target_brightness = BRIGHTNESS_MAX
    elif idle_time < IDLE_OFF:
        timeout = IDLE_OFF - idle_time
        if current_brightness != BRIGHTNESS_LOW:
            set_brightness(BRIGHTNESS_LOW)
            current_brightness = BRIGHTNESS_LOW
        target_brightness = BRIGHTNESS_LOW
    else:
        timeout = None  # unendlich blockieren, Bildschirm aus
        if current_brightness != BRIGHTNESS_MIN:
            set_brightness(BRIGHTNESS_MIN)
            current_brightness = BRIGHTNESS_MIN
        target_brightness = BRIGHTNESS_MIN

    # Blockierend auf Input warten
    r, _, _ = select.select([device.fd], [], [], timeout)
    if r:
        for event in device.read():
            set_brightness(BRIGHTNESS_MAX)
            current_brightness = BRIGHTNESS_MAX
            last_event = time.time()
            break
