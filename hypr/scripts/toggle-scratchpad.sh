#!/bin/bash
# Toggle a scratchpad - spawns if not running, toggles visibility otherwise
#
# Usage: toggle-scratchpad.sh --name <name> [--size <W% H%>] [--cmd <command>]
#
# Examples:
#   toggle-scratchpad.sh --name alacritty
#   toggle-scratchpad.sh --name editor --size "100% 100%" --cmd "nvim"

set -euo pipefail

# Defaults
NAME=""
SIZE="80% 70%"
CMD=""
OPACITY="0.35"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            NAME="$2"
            shift 2
            ;;
        --size)
            SIZE="$2"
            shift 2
            ;;
        --cmd)
            CMD="$2"
            shift 2
            ;;
        --opacity)
            OPACITY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$NAME" ]]; then
    echo "Error: --name is required" >&2
    exit 1
fi

# Derive class and workspace from name
SCRATCHPAD_CLASS="${NAME^}-scratchpad"  # Capitalize first letter
SPECIAL_WS="special:${NAME}"
WS_NAME="${NAME}"

# Build the launch command
if [[ -n "$CMD" ]]; then
    LAUNCH_CMD="alacritty --class $SCRATCHPAD_CLASS -e $CMD"
else
    LAUNCH_CMD="alacritty --class $SCRATCHPAD_CLASS"
fi

resize_and_center() {
    local window_addr="$1"
    hyprctl --batch "
        dispatch setfloating address:$window_addr;
        dispatch resizewindowpixel exact $SIZE,address:$window_addr;
        dispatch centerwindow
    "
}

is_scratchpad_visible() {
    hyprctl monitors -j | jq -e ".[] | select(.focused == true and .specialWorkspace.name == \"$SPECIAL_WS\")" > /dev/null 2>&1
}

# Check if scratchpad is running
if ! hyprctl clients -j | jq -e ".[] | select(.class == \"$SCRATCHPAD_CLASS\")" > /dev/null 2>&1; then
    # Not running, spawn it
    uwsm-app -- $LAUNCH_CMD &

    # Wait for the window to appear (up to 2 seconds)
    for i in {1..20}; do
        sleep 0.1
        if hyprctl clients -j | jq -e ".[] | select(.class == \"$SCRATCHPAD_CLASS\")" > /dev/null 2>&1; then
            break
        fi
    done

    sleep 0.1

    # Get window address
    WINDOW_ADDR=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$SCRATCHPAD_CLASS\") | .address")

    # Move to special workspace and set opacity
    hyprctl dispatch movetoworkspacesilent "$SPECIAL_WS,address:$WINDOW_ADDR"
    hyprctl setprop "address:$WINDOW_ADDR" opacity "$OPACITY" "$OPACITY" override

    # Show the special workspace
    hyprctl dispatch togglespecialworkspace "$WS_NAME"
    sleep 0.05

    # Resize and center
    hyprctl dispatch focuswindow "address:$WINDOW_ADDR"
    resize_and_center "$WINDOW_ADDR"

    exit 0
fi

# Scratchpad exists - check if visible
if is_scratchpad_visible; then
    # Already visible, hide it
    hyprctl dispatch togglespecialworkspace "$WS_NAME"
    exit 0
fi

# Hidden, show it and resize/center
WINDOW_ADDR=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$SCRATCHPAD_CLASS\") | .address")

hyprctl dispatch togglespecialworkspace "$WS_NAME"
sleep 0.05

hyprctl dispatch focuswindow "address:$WINDOW_ADDR"
resize_and_center "$WINDOW_ADDR"
