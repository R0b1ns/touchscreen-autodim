#!/usr/bin/env python3
import evdev
import subprocess
import time
import configparser
import os
import select

# --- Load configuration ---
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

# --- Function to set screen brightness ---
def set_brightness(value: int):
    print(f"set_brightness({value})")
    """Set the backlight brightness to the specified value."""
    subprocess.run(["sudo", "tee", BRIGHTNESS_PATH],
                   input=str(value), text=True, stdout=subprocess.DEVNULL)

# --- Function to fade brightness smoothly ---
def fade_brightness(from_value: int, to_value: int, step: int = 1, delay: float = 0.02) -> int:
    """Smoothly fade brightness from from_value to to_value."""
    if from_value < to_value:
        rng = range(from_value, to_value + 1, step)
    else:
        rng = range(from_value, to_value - 1, -step)
    for val in rng:
        set_brightness(val)
        time.sleep(delay)
    return to_value

# --- Initial setup ---
set_brightness(BRIGHTNESS_MAX)
current_brightness = BRIGHTNESS_MAX
last_event = time.time()
swallow_first_event = False  # Flag for first input after screen is off

# --- Open the input device ---
device = evdev.InputDevice(DEVICE)

while True:
    now = time.time()
    idle_time = now - last_event

    # --- Determine screen state and target brightness ---
    if idle_time < IDLE_DIM:
        timeout = IDLE_DIM - idle_time
    elif idle_time < IDLE_OFF:
        timeout = IDLE_OFF - idle_time
        if current_brightness != BRIGHTNESS_LOW:
            print("Fade to BRIGHTNESS_LOW")
            current_brightness = fade_brightness(current_brightness, BRIGHTNESS_LOW)
    else:
        timeout = None  # Wait indefinitely, screen is off
        if current_brightness != BRIGHTNESS_MIN:
            set_brightness(BRIGHTNESS_MIN)
            current_brightness = BRIGHTNESS_MIN
            swallow_first_event = True
            print("Grab Device")
            device.grab()  # Temporarily grab device to block OS events

    # --- Wait for input or timeout ---
    r, _, _ = select.select([device.fd], [], [], timeout)
    if r:
        for event in device.read():
            # --- Handle first input after screen off ---
            # event.type most likely EV_ABS
            if swallow_first_event:
                print("swallow_first_event")
                set_brightness(BRIGHTNESS_MAX)  # Restore screen brightness
                current_brightness = BRIGHTNESS_MAX
                last_event = time.time()
                swallow_first_event = False
                print("Ungrab Device")
                device.ungrab()  # Release device so OS receives further events
                break  # Only affects Python loop, not OS event handling

            # --- Normal input processing ---
            last_event = time.time()
            if current_brightness != BRIGHTNESS_MAX:
                print("Normal input processing")
                set_brightness(BRIGHTNESS_MAX)
                current_brightness = BRIGHTNESS_MAX
            break
