#!/usr/bin/env bash
set -euo pipefail

THEME_SCRIPT="${OMARCHY_THEME_CMD:-$HOME/.config/bash_custom/scripts/omarchy-random-theme.sh}"

while true; do
  # Sleep for random 5-10 hours (in seconds: 18000-36000)
  sleep_seconds=$((RANDOM % 18001 + 18000))
  sleep "$sleep_seconds"

  # Run the theme randomizer
  "$THEME_SCRIPT" || true
done
