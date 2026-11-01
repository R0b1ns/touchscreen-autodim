#!/bin/bash
# Autodim - Touchscreen brightness management + Brightness Menu
set -u
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_PATH="$SCRIPT_DIR/autodim.conf"

get_config() {
    awk -v key="$1" '
        /^\[autodim\]/ { section=1; next }
        /^\[/ { section=0 }
        section {
            pos=index($0, "=")
            if (!pos) next
            k=substr($0, 1, pos-1)
            v=substr($0, pos+1)
            gsub(/^[ \t]+|[ \t]+$/, "", k)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (k == key) { print v; exit }
        }
    ' "$CONFIG_PATH"
}

[[ -f "$CONFIG_PATH" ]] || { echo "ERROR: Configuration not found: $CONFIG_PATH"; exit 1; }

DEVICE_NAME=$(get_config device_name)
find_device() {
    local name="$1"
    for d in /dev/input/event*; do
        [[ -e "$d" ]] || continue
        local n=$(cat /sys/class/input/$(basename "$d")/device/name 2>/dev/null)
        [[ "$n" == "$name" ]] && { echo "$d"; return 0; }
    done
    return 1
}
DEVICE=$(find_device "$DEVICE_NAME") || {
    echo "ERROR: Touchscreen '$DEVICE_NAME' not found"
    exit 1
}

BRIGHTNESS_MAX=$(get_config brightness_max)
BRIGHTNESS_LOW=$(get_config brightness_low)
BRIGHTNESS_MIN=$(get_config brightness_min)
IDLE_DIM=$(get_config idle_dim)
IDLE_OFF=$(get_config idle_off)
BRIGHTNESS_PATH=$(get_config backlight_path)
NIGHT_START=$(get_config night_start)
NIGHT_END=$(get_config night_end)
NIGHT_IDLE_OFF=$(get_config night_idle_off)

for name in BRIGHTNESS_MAX BRIGHTNESS_LOW BRIGHTNESS_MIN IDLE_DIM IDLE_OFF NIGHT_START NIGHT_END NIGHT_IDLE_OFF; do
    [[ "${!name}" =~ ^[0-9]+$ ]] || { echo "ERROR: Invalid configuration value: $name"; exit 1; }
done
[[ -n "$DEVICE" && -n "$BRIGHTNESS_PATH" ]] || { echo "ERROR: Missing device or backlight_path."; exit 1; }
(( IDLE_DIM > 0 )) || { echo "ERROR: idle_dim must be > 0"; exit 1; }
(( NIGHT_START >= 0 && NIGHT_START <= 23 && NIGHT_END >= 0 && NIGHT_END <= 23 )) || { echo "ERROR: night_start/end must be 0-23"; exit 1; }
[[ -e "$DEVICE" ]] || { echo "ERROR: Input device not found: $DEVICE"; exit 1; }
[[ -w "$BRIGHTNESS_PATH" ]] || { echo "ERROR: Cannot write brightness: $BRIGHTNESS_PATH"; exit 1; }
command -v evtest >/dev/null 2>&1 || { echo "ERROR: evtest is not installed."; exit 1; }
command -v yad >/dev/null 2>&1 || { echo "ERROR: yad is not installed (sudo apt install yad)"; exit 1; }

CURRENT_BRIGHTNESS=$BRIGHTNESS_MAX

set_brightness() {
    printf '%s\n' "$1" > "$BRIGHTNESS_PATH"
    CURRENT_BRIGHTNESS=$1
}

fade_brightness() {
    local from=$1 to=$2 step
    (( from < to )) && step=1 || step=-1
    for ((val=from; ; val+=step)); do
        set_brightness "$val"
        (( val == to )) && break
        sleep 0.02
    done
}

show_brightness_menu() {
    local val
    val=$(yad --scale \
        --title="Helligkeit" \
        --text="Helligkeit einstellen" \
        --min-value="$BRIGHTNESS_MIN" \
        --max-value="$BRIGHTNESS_MAX" \
        --value="$CURRENT_BRIGHTNESS" \
        --step=1 \
        --button="OK:0" \
        --button="Abbrechen:1" \
        --width=400 --height=120 \
        --on-top --center 2>/dev/null) || return

    [[ -n "$val" ]] && set_brightness "$val"
}

# Return codes:
# 0 = normal touch
# 2 = long press (menu)
# 1 = timeout / error
wait_for_input() {
    local wait_seconds="${1:-}" grab="${2:-no}"
    local line pid fd
    local press_start=0
    local detected=1
    local -a args=()
    [[ "$grab" == "yes" ]] && args+=(--grab)

    coproc EVPROC { exec stdbuf -oL evtest "${args[@]}" "$DEVICE" 2>/dev/null; }
    pid=$EVPROC_PID
    fd=${EVPROC[0]}

    while true; do
        if [[ -n "$wait_seconds" ]]; then
            IFS= read -r -t "$wait_seconds" line <&"$fd" || break
        else
            IFS= read -r line <&"$fd" || break
        fi

        if [[ "$line" == Event:* ]]; then
            # BTN_TOUCH press
            if [[ "$line" == *"BTN_TOUCH"* && "$line" == *"value 1"* ]]; then
                press_start=$SECONDS
                detected=0
            # BTN_TOUCH release
            elif [[ "$line" == *"BTN_TOUCH"* && "$line" == *"value 0"* ]]; then
                if (( press_start > 0 && SECONDS - press_start >= 1 )); then
                    detected=2   # long press
                else
                    detected=0   # normal tap
                fi
                break
            # Fallback for devices without BTN_TOUCH
            elif [[ "$line" == *"ABS_MT_TRACKING_ID"* && "$line" != *"value -1"* ]]; then
                detected=0
                break
            fi
        fi
    done

    kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exec {fd}<&-
    return "$detected"
}

is_night() {
    local h=$(date +%H)
    h=$((10#$h))
    if (( NIGHT_START > NIGHT_END )); then
        (( h >= NIGHT_START || h < NIGHT_END ))
    else
        (( h >= NIGHT_START && h < NIGHT_END ))
    fi
}

echo "Autodim started"
echo "Device: $DEVICE"
echo "Brightness: $BRIGHTNESS_MAX"
set_brightness "$BRIGHTNESS_MAX"
LAST_EVENT=$SECONDS

while true; do
    NOW=$SECONDS
    IDLE_TIME=$((NOW - LAST_EVENT))

    handle_touch() {
        local rc=$1
        LAST_EVENT=$SECONDS
        if (( rc == 2 )); then
            echo "Long press → Brightness menu"
            show_brightness_menu
        else
            echo "Touch detected"
            (( CURRENT_BRIGHTNESS != BRIGHTNESS_MAX )) && fade_brightness "$CURRENT_BRIGHTNESS" "$BRIGHTNESS_MAX"
        fi
    }

    # 1. Noch aktiv
    if (( IDLE_TIME < IDLE_DIM )); then
        REMAINING=$((IDLE_DIM - IDLE_TIME))
        wait_for_input "$REMAINING" no
        rc=$?
        (( rc == 0 || rc == 2 )) && handle_touch $rc

    # 2. Nacht + Idle-Off erreicht → aus
    elif is_night && (( NIGHT_IDLE_OFF > 0 && IDLE_TIME >= NIGHT_IDLE_OFF )); then
        (( CURRENT_BRIGHTNESS != BRIGHTNESS_MIN )) && {
            echo "Night idle - brightness minimum"
            set_brightness "$BRIGHTNESS_MIN"
        }
        echo "Grab touchscreen - waiting for wake-up touch"
        wait_for_input "" yes
        rc=$?
        if (( rc == 0 || rc == 2 )); then
            echo "Wake-up touch detected"
            set_brightness "$BRIGHTNESS_MAX"
            LAST_EVENT=$SECONDS
            (( rc == 2 )) && show_brightness_menu
        else
            echo "WARNING: Input device stopped responding."
            sleep 2
        fi

    # 3. Dimmen
    else
        (( CURRENT_BRIGHTNESS != BRIGHTNESS_LOW )) && {
            echo "Fade to BRIGHTNESS_LOW"
            fade_brightness "$CURRENT_BRIGHTNESS" "$BRIGHTNESS_LOW"
        }

        if is_night && (( NIGHT_IDLE_OFF > 0 )); then
            REMAINING=$((NIGHT_IDLE_OFF - IDLE_TIME))
            (( REMAINING < 1 )) && REMAINING=1
            wait_for_input "$REMAINING" no
            rc=$?
            (( rc == 0 || rc == 2 )) && handle_touch $rc
        else
            wait_for_input "" no
            rc=$?
            (( rc == 0 || rc == 2 )) && handle_touch $rc
        fi
    fi
done
