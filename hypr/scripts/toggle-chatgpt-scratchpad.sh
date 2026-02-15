#!/bin/bash
# Toggle ChatGPT scratchpad - spawns if not running, toggles visibility otherwise

SCRATCHPAD_CLASS="brave-chatgpt.com__-Default"
SPECIAL_WS="special:chatgpt"

# Function to resize and center the scratchpad on current monitor
resize_and_center() {
    local window_addr="$1"
    hyprctl --batch "
        dispatch setfloating address:$window_addr;
        dispatch resizewindowpixel exact 80% 70%,address:$window_addr;
        dispatch centerwindow
    "
}

# Check if the special workspace is currently visible on the focused monitor
is_scratchpad_visible() {
    hyprctl monitors -j | jq -e '.[] | select(.focused == true and .specialWorkspace.name == "special:chatgpt")' > /dev/null 2>&1
}

# Check if scratchpad ChatGPT is running
if ! hyprctl clients -j | jq -e ".[] | select(.class == \"$SCRATCHPAD_CLASS\")" > /dev/null 2>&1; then
    # Not running, spawn it
    # Use chromium with --app flag (chromium auto-generates class name from URL)
    uwsm-app -- brave-nightly --app="https://chatgpt.com/" &

    # Wait for the window to actually appear (up to 2 seconds)
    for i in {1..20}; do
        sleep 0.1
        if hyprctl clients -j | jq -e ".[] | select(.class == \"$SCRATCHPAD_CLASS\")" > /dev/null 2>&1; then
            break
        fi
    done

    # Give it a moment to settle
    sleep 0.1

    # Get window address for targeted commands
    WINDOW_ADDR=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$SCRATCHPAD_CLASS\") | .address")

    # Move to special workspace first
    hyprctl dispatch movetoworkspacesilent $SPECIAL_WS,address:$WINDOW_ADDR
    hyprctl setprop address:$WINDOW_ADDR opacity 0.35 0.35 override

    # Show the special workspace
    hyprctl dispatch togglespecialworkspace chatgpt
    sleep 0.05

    # Now resize and center on the current monitor
    hyprctl dispatch focuswindow address:$WINDOW_ADDR
    resize_and_center "$WINDOW_ADDR"

    exit 0
fi

# Scratchpad exists - check if it's currently visible on the focused monitor
if is_scratchpad_visible; then
    # Already visible, just hide it
    hyprctl dispatch togglespecialworkspace chatgpt
    exit 0
fi

# Hidden, so show it and resize/center for current monitor
WINDOW_ADDR=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$SCRATCHPAD_CLASS\") | .address")

# Show the special workspace
hyprctl dispatch togglespecialworkspace chatgpt
sleep 0.05

# Focus and resize/center for the current monitor's dimensions
hyprctl dispatch focuswindow address:$WINDOW_ADDR
resize_and_center "$WINDOW_ADDR"
