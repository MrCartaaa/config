#!/usr/bin/env bash
set -euo pipefail

THEME_DIR="$HOME/.local/share/omarchy/themes"
STATE_DIR="$HOME/.local/state/omarchy"
LAST_THEME_FILE="$STATE_DIR/last_theme"

mkdir -p "$STATE_DIR"

###############################################################################
# 1. Denylist logic (skip light themes at night)
###############################################################################

hour="$(date +%H)"
is_night=true

# Simple heuristic:
# - themes containing "light", "day", or "latte" are considered light themes
is_denied() {
  local name="$1"

  if $is_night && [[ "$name" =~ (light|day|latte) ]]; then
    return 0
  fi

  return 1
}

###############################################################################
# 2. Gate on active display / idle state
###############################################################################

# Require an active Wayland session
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  exit 0
fi

# If hypridle is running, skip changes while idle
if command -v hyprctl >/dev/null 2>&1; then
  if hyprctl monitors -j | grep -q '"dpmsStatus":false'; then
    # Displays are asleep → do not change theme
    exit 0
  fi
fi

###############################################################################
# 3. Collect eligible themes
###############################################################################

mapfile -t themes < <(
  find "$THEME_DIR" -maxdepth 1 -type d \
    ! -path "$THEME_DIR" \
    -printf '%f\n'
)

if ((${#themes[@]} == 0)); then
  exit 1
fi

last_theme=""
if [[ -f "$LAST_THEME_FILE" ]]; then
  last_theme="$(<"$LAST_THEME_FILE")"
fi

eligible=()
for theme in "${themes[@]}"; do
  is_denied "$theme" && continue
  [[ "$theme" == "$last_theme" ]] && continue
  eligible+=("$theme")
done

# Fallback: if everything was filtered out, allow repeats but keep denylist
if ((${#eligible[@]} == 0)); then
  for theme in "${themes[@]}"; do
    is_denied "$theme" && continue
    eligible+=("$theme")
  done
fi

((${#eligible[@]} == 0)) && exit 0

###############################################################################
# 4. Pick and apply
###############################################################################

selected="$(printf '%s\n' "${eligible[@]}" | shuf -n 1)"
echo "$selected"
omarchy-theme-set "$selected"
echo "$selected" >"$LAST_THEME_FILE"
