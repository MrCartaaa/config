#!/usr/bin/env bash
set -euo pipefail

# Root-only. Installs or removes the logind drop-in that makes lid-close
# ignore the switch on AC. Called via sudo from lid-keep-running.sh.

DROPIN="/etc/systemd/logind.conf.d/30-lid-keep-running.conf"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "lid-keep-running-apply.sh must run as root (use: sudo $0 on|off)" >&2
  exit 1
fi

usage() {
  echo "Usage: lid-keep-running-apply.sh on|off" >&2
  exit 1
}

case "${1:-}" in
  on)
    mkdir -p /etc/systemd/logind.conf.d
    umask 022
    cat >"$DROPIN" <<'EOF'
# Managed by lid-awake (~/.config/bash_custom/scripts/lid/).
# Lid-close still suspends on battery. On AC, logind ignores the lid so the
# session keeps running (Omarchy still locks / clamshell via Hyprland).
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
EOF
    ;;
  off)
    rm -f "$DROPIN"
    ;;
  *)
    usage
    ;;
esac

systemctl reload systemd-logind
