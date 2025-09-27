#!/usr/bin/env python3
import evdev
import uinput
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
GRAB_EVENTS = cfg.getboolean('grab_events', fallback=True)  # neu: ob Events verschluckt werden

# --- Function to set backlight brightness ---
def set_brightness(value):
    subprocess.run(["sudo", "tee", BRIGHTNESS_PATH],
                   input=str(value), text=True, stdout=subprocess.DEVNULL)

# --- Function to fade brightness ---
def fade_brightness(from_value, to_value, step=1, delay=0.02):
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

# --- Open the input device ---
device = evdev.InputDevice(DEVICE)

# --- Optional: grab device to swallow events ---
if GRAB_EVENTS:
    device.grab()  # exklusiver Zugriff, OS bekommt keine Events direkt

# --- Create virtual device (clone of real device) ---
capabilities = device.capabilities()
ui = uinput.Device(capabilities)

while True:
    now = time.time()
    idle_time = now - last_event

    # --- Calculate timeout for select ---
    if idle_time < IDLE_DIM:
        timeout = IDLE_DIM - idle_time
        target_brightness = BRIGHTNESS_MAX
    elif idle_time < IDLE_OFF:
        timeout = IDLE_OFF - idle_time

        # Dim screen if needed
        if current_brightness != BRIGHTNESS_LOW:
            current_brightness = fade_brightness(current_brightness, BRIGHTNESS_LOW)
        target_brightness = BRIGHTNESS_LOW
    else:
        timeout = None  # Block indefinitely, screen off
        if current_brightness != BRIGHTNESS_MIN:
            set_brightness(BRIGHTNESS_MIN)
            current_brightness = BRIGHTNESS_MIN
        target_brightness = BRIGHTNESS_MIN

    # --- Wait for input event or timeout ---
    r, _, _ = select.select([device.fd], [], [], timeout)
    if r:
        for event in device.read():
            if current_brightness == BRIGHTNESS_MIN:
                # Bildschirm war aus → erster Klick nur zum Aufwecken
                set_brightness(BRIGHTNESS_MAX)
                current_brightness = BRIGHTNESS_MAX
                last_event = time.time()
                break
            else:
                # --- Alte Lösung, nur Python lesen ---
                # set_brightness(BRIGHTNESS_MAX)
                # current_brightness = BRIGHTNESS_MAX
                # last_event = time.time()
                # break

                # Neue Lösung: Events ans OS weiterleiten via uinput
                if event.type != evdev.ecodes.EV_SYN:
                    ui.emit(event.type, event.code, event.value)
                else:
                    ui.syn()

                # Reset brightness on input
                set_brightness(BRIGHTNESS_MAX)
                current_brightness = BRIGHTNESS_MAX
                last_event = time.time()
                break
