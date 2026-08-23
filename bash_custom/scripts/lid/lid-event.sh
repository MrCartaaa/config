#!/usr/bin/env bash
set -euo pipefail

# Hyprland lid-switch wrapper. Always runs the stock Omarchy handlers, then
# DPMS-offs the (only) panel when lid-awake is on, we are on AC, and there is
# no external monitor. Docked clamshell is left to omarchy-hyprland-monitor-clamshell.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Usage: lid-event.sh close|open" >&2
  exit 1
}

keep_running_active() {
  lid_awake_flag_enabled && is_on_ac
}

case "${1:-}" in
  close)
    omarchy-system-lid-close
    if keep_running_active && ! omarchy-hw-external-monitors; then
      hyprctl dispatch dpms off >/dev/null 2>&1 || true
    fi
    ;;
  open)
    omarchy-hyprland-monitor-clamshell
    if lid_awake_flag_enabled; then
      hyprctl dispatch dpms on >/dev/null 2>&1 || true
    fi
    ;;
  *)
    usage
    ;;
esac
