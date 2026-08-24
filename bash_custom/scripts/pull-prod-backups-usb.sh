#!/usr/bin/env bash
# One-way: hetzner:statbook-prod-backups → USB. Never rclone toward the remote.
set -euo pipefail

source "/home/jaime/.config/.util/log.sh"
LOG_TS=1

EXTERNAL_MOUNT="${EXTERNAL_MOUNT:-/mnt/ext_backup}"
DEST="${PROD_BACKUP_USB:-$EXTERNAL_MOUNT/statbook-prod-backups}"
REMOTE_BUCKET="${PROD_BACKUP_BUCKET:-statbook-prod-backups}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/home/jaime/.config/rclone/rclone.conf}"
export RCLONE_CONFIG

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo --preserve-env=RCLONE_CONFIG,EXTERNAL_MOUNT,PROD_BACKUP_USB,PROD_BACKUP_BUCKET -- "$0" "$@"
fi

command -v rclone >/dev/null 2>&1 || log_exit_bad "rclone not found"
[[ -f "$RCLONE_CONFIG" ]] || log_exit_bad "rclone config missing: $RCLONE_CONFIG"

if ! mountpoint -q "$EXTERNAL_MOUNT"; then
  log_skip "USB not mounted at $EXTERNAL_MOUNT — no prod-backup pull"
  exit 0
fi

log_hello "Pulling hetzner:${REMOTE_BUCKET} → ${DEST} (USB, one-way)"
mkdir -p "$DEST"
# sync USB to match the cloud repo (follows cluster prune). Never the reverse.
rclone sync "hetzner:${REMOTE_BUCKET}" "$DEST" --fast-list
log_exit_ok "USB prod-backup mirror updated: $DEST"
