#!/usr/bin/env bash
set -euo pipefail

# User-facing lid-awake toggle. Enable is AC-only; logind still suspends on
# battery even while the toggle is on (HandleLidSwitch=suspend).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY="$SCRIPT_DIR/lid-keep-running-apply.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<EOF
Usage: lid-awake [toggle|on|off|status]

  toggle   Enable if off, disable if on (default)
  on       Keep running on lid-close while plugged in (errors on battery)
  off      Restore suspend-on-lid-close
  status   Print toggle, AC, and logind state
EOF
}

ac_required_error() {
  local msg
  msg="lid-awake: AC power required.

Refusing to enable while on battery. Plug in the charger and run: lid-awake on
Lid-close would still suspend on battery even if this were enabled."
  echo "$msg" >&2
  notify_lid critical "lid-awake needs AC power" \
    "Plug in the charger, then run lid-awake on. Lid-close still suspends on battery."
  exit 1
}

print_status() {
  local flag="off" ac="on battery" lid ext dropin="absent"
  lid_awake_flag_enabled && flag="on"
  is_on_ac && ac="plugged in"
  lid=$(logind_prop HandleLidSwitch)
  ext=$(logind_prop HandleLidSwitchExternalPower)
  [[ -f /etc/systemd/logind.conf.d/30-lid-keep-running.conf ]] && dropin="present"

  printf 'lid-awake: %s (%s)\n' "$flag" "$ac"
  printf '  HandleLidSwitch=%s\n' "${lid:-<default>}"
  printf '  HandleLidSwitchExternalPower=%s\n' "${ext:-<default>}"
  printf '  drop-in %s\n' "$dropin"
  if [[ $flag == on ]]; then
    echo "  lid-close keeps running on AC only; on battery it still suspends."
  fi
}

apply_state() {
  local action="$1"
  sudo "$APPLY" "$action"
  set_lid_awake_flag "$action"
}

verify_on() {
  local ext
  ext=$(logind_prop HandleLidSwitchExternalPower)
  if [[ $ext != ignore ]]; then
    echo "lid-awake: logind HandleLidSwitchExternalPower is '$ext', expected 'ignore'." >&2
    echo "The drop-in may not have been picked up. Try: sudo systemctl reload systemd-logind" >&2
    return 1
  fi
}

cmd_on() {
  if ! is_on_ac; then
    ac_required_error
  fi

  if lid_awake_flag_enabled; then
    local ext
    ext=$(logind_prop HandleLidSwitchExternalPower)
    if [[ $ext == ignore ]]; then
      echo "lid-awake: already on (lid-close keeps running on AC only)."
      print_status
      return 0
    fi
  fi

  apply_state on
  if ! verify_on; then
    apply_state off || true
    exit 1
  fi
  echo "lid-awake: on. Closing the lid on AC keeps the system running (session still locks)."
  echo "On battery, lid-close still suspends. Turn off with: lid-awake off"
  notify_lid normal "lid-awake on" \
    "Lid-close keeps running while plugged in. Still suspends on battery. A closed laptop in a bag can overheat — lid-awake off when done."
}

cmd_off() {
  if ! lid_awake_flag_enabled && [[ ! -f /etc/systemd/logind.conf.d/30-lid-keep-running.conf ]]; then
    echo "lid-awake: already off."
    return 0
  fi

  apply_state off
  echo "lid-awake: off. Lid-close suspends again (except when docked)."
  notify_lid low "lid-awake off" "Lid-close will suspend again."
}

cmd_toggle() {
  if lid_awake_flag_enabled; then
    cmd_off
  else
    cmd_on
  fi
}

case "${1:-toggle}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  toggle) cmd_toggle ;;
  on) cmd_on ;;
  off) cmd_off ;;
  status) print_status ;;
  *)
    usage >&2
    exit 2
    ;;
esac
