#!/bin/bash
# Toggle Alacritty scratchpad - spawns if not running, toggles visibility otherwise

SCRATCHPAD_CLASS="Alacritty-scratchpad"
SPECIAL_WS="special:alacritty"

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
    hyprctl monitors -j | jq -e '.[] | select(.focused == true and .specialWorkspace.name == "special:alacritty")' > /dev/null 2>&1
}

# Check if scratchpad alacritty is running
if ! hyprctl clients -j | jq -e ".[] | select(.class == \"$SCRATCHPAD_CLASS\")" > /dev/null 2>&1; then
    # Not running, spawn it
    uwsm-app -- alacritty --class "$SCRATCHPAD_CLASS" &

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
    # Set opacity (0.35 = 35% opacity - very transparent)
    # hyprctl keyword windowrulev2 "opacity 0.35 0.35,class:$SCRATCHPAD_CLASS"

    # Show the special workspace
    hyprctl dispatch togglespecialworkspace alacritty
    sleep 0.05

    # Now resize and center on the current monitor
    hyprctl dispatch focuswindow address:$WINDOW_ADDR
    resize_and_center "$WINDOW_ADDR"

    exit 0
fi

# Scratchpad exists - check if it's currently visible on the focused monitor
if is_scratchpad_visible; then
    # Already visible, just hide it
    hyprctl dispatch togglespecialworkspace alacritty
    exit 0
fi

# Hidden, so show it and resize/center for current monitor
WINDOW_ADDR=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$SCRATCHPAD_CLASS\") | .address")

# Show the special workspace
hyprctl dispatch togglespecialworkspace alacritty
sleep 0.05

# Focus and resize/center for the current monitor's dimensions
hyprctl dispatch focuswindow address:$WINDOW_ADDR
resize_and_center "$WINDOW_ADDR"
