#!/bin/bash
# Toggle editor scratchpad - spawns if not running, toggles visibility otherwise

SCRATCHPAD_CLASS="Editor-scratchpad"
SPECIAL_WS="special:editor"

# Function to make window fullscreen
make_fullscreen() {
    local window_addr="$1"
    hyprctl --batch "
        dispatch setfloating address:$window_addr;
        dispatch resizewindowpixel exact 99% 99%,address:$window_addr;
        dispatch centerwindow
    "
}

# Check if the special workspace is currently visible on the focused monitor
is_scratchpad_visible() {
    hyprctl monitors -j | jq -e '.[] | select(.focused == true and .specialWorkspace.name == "special:editor")' > /dev/null 2>&1
}

# Check if scratchpad editor is running
if ! hyprctl clients -j | jq -e ".[] | select(.class == \"$SCRATCHPAD_CLASS\")" > /dev/null 2>&1; then
    # Not running, spawn it
    # Use Alacritty directly so the Hypr "class" matches SCRATCHPAD_CLASS.
    # (xdg-terminal-exec --app-id only works if the chosen terminal supports it; in your case it still came up as class "Alacritty".)
    uwsm-app -- alacritty --class "$SCRATCHPAD_CLASS" -e nvim &

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
    hyprctl dispatch togglespecialworkspace editor
    sleep 0.05

    # Make it fullscreen
    hyprctl dispatch focuswindow address:$WINDOW_ADDR
    make_fullscreen "$WINDOW_ADDR"

    exit 0
fi

# Scratchpad exists - check if it's currently visible on the focused monitor
if is_scratchpad_visible; then
    # Already visible, just hide it
    hyprctl dispatch togglespecialworkspace editor
    exit 0
fi

# Hidden, so show it and make fullscreen
WINDOW_ADDR=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$SCRATCHPAD_CLASS\") | .address")

# Show the special workspace
hyprctl dispatch togglespecialworkspace editor
sleep 0.05

# Focus and make fullscreen
hyprctl dispatch focuswindow address:$WINDOW_ADDR
make_fullscreen "$WINDOW_ADDR"
