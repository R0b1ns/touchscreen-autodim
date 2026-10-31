#!/bin/bash
# Autodim - Touchscreen brightness management
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

DEVICE=$(get_config device)
BRIGHTNESS_MAX=$(get_config brightness_max)
BRIGHTNESS_LOW=$(get_config brightness_low)
BRIGHTNESS_MIN=$(get_config brightness_min)
IDLE_DIM=$(get_config idle_dim)
IDLE_OFF=$(get_config idle_off)
BRIGHTNESS_PATH=$(get_config backlight_path)

for name in BRIGHTNESS_MAX BRIGHTNESS_LOW BRIGHTNESS_MIN IDLE_DIM IDLE_OFF; do
    [[ "${!name}" =~ ^[0-9]+$ ]] || { echo "ERROR: Invalid configuration value: $name"; exit 1; }
done
[[ -n "$DEVICE" && -n "$BRIGHTNESS_PATH" ]] || { echo "ERROR: Missing device or backlight_path."; exit 1; }
(( IDLE_DIM < IDLE_OFF )) || { echo "ERROR: idle_dim must be smaller than idle_off."; exit 1; }
[[ -e "$DEVICE" ]] || { echo "ERROR: Input device not found: $DEVICE"; exit 1; }
[[ -w "$BRIGHTNESS_PATH" ]] || { echo "ERROR: Cannot write brightness: $BRIGHTNESS_PATH"; exit 1; }
command -v evtest >/dev/null 2>&1 || { echo "ERROR: evtest is not installed."; exit 1; }

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

wait_for_input() {
    local wait_seconds="${1:-}" grab="${2:-no}" line pid fd detected=1
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
        [[ "$line" == Event:* ]] && { detected=0; break; }
    done

    kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exec {fd}<&-
    return "$detected"
}

echo "Autodim started"
echo "Device: $DEVICE"
echo "Brightness: $BRIGHTNESS_MAX"
set_brightness "$BRIGHTNESS_MAX"
LAST_EVENT=$SECONDS

while true; do
    NOW=$SECONDS
    IDLE_TIME=$((NOW - LAST_EVENT))

    if (( IDLE_TIME < IDLE_DIM )); then
        REMAINING=$((IDLE_DIM - IDLE_TIME))
        if wait_for_input "$REMAINING" no; then
            LAST_EVENT=$SECONDS
            echo "Touch detected"
            (( CURRENT_BRIGHTNESS != BRIGHTNESS_MAX )) && fade_brightness "$CURRENT_BRIGHTNESS" "$BRIGHTNESS_MAX"
        fi

    elif (( IDLE_TIME < IDLE_OFF )); then
        (( CURRENT_BRIGHTNESS != BRIGHTNESS_LOW )) && {
            echo "Fade to BRIGHTNESS_LOW"
            fade_brightness "$CURRENT_BRIGHTNESS" "$BRIGHTNESS_LOW"
        }
        NOW=$SECONDS
        IDLE_TIME=$((NOW - LAST_EVENT))
        REMAINING=$((IDLE_OFF - IDLE_TIME))
        if (( REMAINING > 0 )) && wait_for_input "$REMAINING" no; then
            LAST_EVENT=$SECONDS
            echo "Touch detected"
            fade_brightness "$CURRENT_BRIGHTNESS" "$BRIGHTNESS_MAX"
        fi

    else
        (( CURRENT_BRIGHTNESS != BRIGHTNESS_MIN )) && {
            echo "Screen idle - brightness minimum"
            set_brightness "$BRIGHTNESS_MIN"
        }
        echo "Grab touchscreen - waiting for wake-up touch"
        if wait_for_input "" yes; then
            echo "Wake-up touch detected"
            set_brightness "$BRIGHTNESS_MAX"
            LAST_EVENT=$SECONDS
            echo "Brightness restored"
            echo "Touchscreen released"
        else
            echo "WARNING: Input device stopped responding."
            sleep 2
        fi
    fi
done
