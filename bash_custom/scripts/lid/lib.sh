# Shared helpers for lid-awake. Sourced by user-session scripts only
# (not by the root apply helper).

FLAG_NAME="lid-keep-running"
FLAG_PATH="${HOME}/.local/state/omarchy/toggles/${FLAG_NAME}"
POWER_SUPPLY_DIR="${LIDAWAKE_POWER_SUPPLY_DIR:-/sys/class/power_supply}"

is_on_ac() {
  local psy
  for psy in "$POWER_SUPPLY_DIR"/*; do
    [[ -r $psy/type && -r $psy/online ]] || continue
    [[ $(<"$psy/type") == "Mains" ]] || continue
    [[ $(<"$psy/online") == "1" ]] && return 0
  done
  return 1
}

lid_awake_flag_enabled() {
  [[ -f $FLAG_PATH ]]
}

set_lid_awake_flag() {
  case "$1" in
    on) omarchy-toggle "$FLAG_NAME" on ;;
    off) omarchy-toggle "$FLAG_NAME" off ;;
    *)
      echo "set_lid_awake_flag: expected on|off" >&2
      return 1
      ;;
  esac
}

# Prints the dbus string value, or empty if unset / unreadable.
logind_prop() {
  local raw
  raw=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager "$1" 2>/dev/null) || true
  raw=${raw#s }
  raw=${raw#\"}
  raw=${raw%\"}
  printf '%s\n' "$raw"
}

notify_lid() {
  local urgency="$1" headline="$2" body="${3:-}"
  omarchy-notification-send -u "$urgency" -g "󰌾" "$headline" "$body" >/dev/null 2>&1 || true
}
