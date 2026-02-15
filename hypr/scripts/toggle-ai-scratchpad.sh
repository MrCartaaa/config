#!/bin/bash
# Toggle AI scratchpad - spawns if not running, toggles visibility otherwise

SPECIAL_WS="special:chatgpt"
LOCK_FILE="/tmp/ai-scratchpad-launching"
SPAWN_TIMEOUT_SECONDS=8
DEFAULT_CLASS="brave-chatgpt.com__-Default"
APPS=(
    "http://192.168.2.15:8080/|brave-192.168.2.15__-Default|Local"
    "https://chatgpt.com/|brave-chatgpt.com__-Default|ChatGPT"
    "https://grok.com/|brave-grok.com__-Default|Grok"
    "https://www.perplexity.ai/|brave-www.perplexity.ai__-Default|Perplexity"
)

# Function to resize and center the scratchpad on current monitor
resize_and_center() {
    local window_addr="$1"
    hyprctl --batch "
        dispatch focuswindow address:$window_addr;
        dispatch setfloating address:$window_addr;
        dispatch resizewindowpixel exact 80% 70%,address:$window_addr;
        dispatch centerwindow
    "
}

# Check if the special workspace is currently visible on the focused monitor
is_scratchpad_visible() {
    hyprctl monitors -j | jq -e '.[] | select(.focused == true and .specialWorkspace.name == "special:chatgpt")' > /dev/null 2>&1
}

window_exists() {
    local class="$1"
    hyprctl clients -j | jq -e ".[] | select(.class == \"$class\")" > /dev/null 2>&1
}

get_window_addr() {
    local class="$1"
    hyprctl clients -j | jq -r ".[] | select(.class == \"$class\") | .address" | head -n 1
}

ensure_app() {
    local url="$1"
    local class="$2"

    if ! window_exists "$class"; then
        uwsm-app -- brave-nightly --app="$url" &

        for i in {1..80}; do
            sleep 0.1
            if window_exists "$class"; then
                break
            fi
        done
    fi
}

wait_for_all_apps() {
    local tries=$((SPAWN_TIMEOUT_SECONDS * 10))
    for ((i=0; i<tries; i++)); do
        local missing=false
        for app in "${APPS[@]}"; do
            IFS="|" read -r _url class _label <<< "$app"
            if ! window_exists "$class"; then
                missing=true
                break
            fi
        done

        if [ "$missing" = false ]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

ensure_all_apps() {
    if [ -f "$LOCK_FILE" ]; then
        return 0
    fi

    touch "$LOCK_FILE"
    for app in "${APPS[@]}"; do
        IFS="|" read -r url class _label <<< "$app"
        ensure_app "$url" "$class"
    done
    wait_for_all_apps
    rm -f "$LOCK_FILE"
}

move_all_to_scratchpad() {
    for app in "${APPS[@]}"; do
        IFS="|" read -r _url class _label <<< "$app"
        local addr
        addr=$(get_window_addr "$class")
        if [ -n "$addr" ] && [ "$addr" != "null" ]; then
            hyprctl dispatch movetoworkspacesilent $SPECIAL_WS,address:$addr
            hyprctl setprop address:$addr opacity 0.35 0.35 override
        fi
    done
}

resize_all_windows() {
    for app in "${APPS[@]}"; do
        IFS="|" read -r _url class _label <<< "$app"
        local addr
        addr=$(get_window_addr "$class")
        if [ -n "$addr" ] && [ "$addr" != "null" ]; then
            resize_and_center "$addr"
        fi
    done
}

default_or_first_class() {
    if window_exists "$DEFAULT_CLASS"; then
        echo "$DEFAULT_CLASS"
        return 0
    fi

    for app in "${APPS[@]}"; do
        IFS="|" read -r _url class _label <<< "$app"
        if window_exists "$class"; then
            echo "$class"
            return 0
        fi
    done
    return 1
}

next_class() {
    local active_class="$1"
    local found_active=false
    local first_class=""

    for app in "${APPS[@]}"; do
        IFS="|" read -r _url class _label <<< "$app"
        if window_exists "$class"; then
            if [ -z "$first_class" ]; then
                first_class="$class"
            fi
            if $found_active; then
                echo "$class"
                return 0
            fi
            if [ "$class" = "$active_class" ]; then
                found_active=true
            fi
        fi
    done

    if [ -n "$first_class" ]; then
        echo "$first_class"
        return 0
    fi

    return 1
}

focus_and_resize() {
    local class="$1"
    local addr
    addr=$(get_window_addr "$class")
    if [ -n "$addr" ] && [ "$addr" != "null" ]; then
        hyprctl dispatch focuswindow address:$addr
        resize_and_center "$addr"
        return 0
    fi
    return 1
}

if [ "$1" = "--cycle" ]; then
    ensure_all_apps
    move_all_to_scratchpad

    if ! is_scratchpad_visible; then
        hyprctl dispatch togglespecialworkspace chatgpt
        sleep 0.05
    fi

    focus_and_resize "$DEFAULT_CLASS"
    resize_all_windows

    active_class=$(hyprctl activewindow -j | jq -r '.class // empty')
    target_class=$(next_class "$active_class")
    if [ -n "$target_class" ]; then
        focus_and_resize "$target_class"
    fi
    exit 0
fi
if [ -f "$LOCK_FILE" ]; then
    hyprctl dispatch togglespecialworkspace chatgpt
    exit 0
fi

ensure_all_apps
wait_for_all_apps
move_all_to_scratchpad

# Scratchpad exists - check if it's currently visible on the focused monitor
if is_scratchpad_visible; then
    # Already visible, just hide it
    hyprctl dispatch togglespecialworkspace chatgpt
    exit 0
fi

# Hidden, so show it and resize/center for current monitor
FIRST_CLASS=$(default_or_first_class)

hyprctl dispatch togglespecialworkspace chatgpt
sleep 0.05

if [ -n "$FIRST_CLASS" ]; then
    focus_and_resize "$FIRST_CLASS"
fi
resize_all_windows
