#!/usr/bin/env bash
set -euo pipefail

# Self-elevate
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

# Source logger (resolve git root from script's location, not CWD)
source "/home/jaime/.config/.util/log.sh"

# Logger config
LOG_TS=1

PRIMARY_REPO="${PRIMARY_REPO:-/mnt/backup/borg}"
EXTERNAL_MOUNT="${EXTERNAL_MOUNT:-/mnt/ext_backup}"
EXTERNAL_REPO="${EXTERNAL_REPO:-$EXTERNAL_MOUNT/borg}"

# Retention (override via env if desired)
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"

# real_user="${SUDO_USER:-$USER}"
home_dir="/home/jaime"

log_hello "Starting Borg backup"

if [[ ! -d "$PRIMARY_REPO" ]]; then
  log_exit_bad "Primary Borg repo not found at: $PRIMARY_REPO"
fi

# if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
#   log_exit_bad "Could not resolve home directory for user: $real_user"
# fi

# Prompt once for Borg passphrase
# Assumes both repos share the same passphrase; if not, Borg may prompt again.
if [[ -z "${BORG_PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter Borg passphrase: " BORG_PASSPHRASE
  echo
  export BORG_PASSPHRASE
fi

# One package list for every repo, so a later failure cannot skip it.
pkglist_file=$(mktemp)
warnings=0
failures=0
cleanup() {
  unset BORG_PASSPHRASE
  rm -f "$pkglist_file"
}
trap cleanup EXIT
pacman -Qqe >"$pkglist_file"

archive="omarchy-$(date -Is)"

create_args=(
  --exclude-caches
  --stdin-name "pkglist.txt"
)

# Explicit KEEP paths
# - Keep general config, but exclude nvim by *not* including ~/.config/nvim directly.
# - For ~/.config, we include it but add an explicit exclude for nvim.
keep_paths=(
  "/etc"
  "$home_dir/Work"
  "$home_dir/.ssh"
  "$home_dir/.gnupg"
  "$home_dir/.config"
  "$home_dir/.local/share/keyrings"
  "$home_dir/.local/share/fonts"
  "$home_dir/.local/share/applications"
  "/opt/android-sdk"
  "$home_dir/.android"
  "$home_dir/.android/avd"
  "$home_dir/.gradle/wrapper"
  "$home_dir/.gradle/caches/modules-2"
  "$home_dir/.local/share/flutter"
  "$home_dir/.borg-keys"
  "/etc/systemd/system"
  "/mnt/upload"
  "$home_dir/bucket"
)

# Excludes that apply inside the included trees.
extra_excludes=(
  --exclude "$home_dir/.gradle/daemon"
  --exclude "$home_dir/.gradle/caches/transforms-*"
  --exclude "$home_dir/.gradle/caches/journal-*"
  # Brave/Chromium replace profile files by writing .org.chromium.Chromium.<random>
  # and renaming it into place. That temp vanishes between scandir and stat.
  # Singleton* are the live profile lock, socket, and cookie — not data.
  --exclude '*/.org.chromium.Chromium.*'
  --exclude '*/SingletonLock'
  --exclude '*/SingletonSocket'
  --exclude '*/SingletonCookie'
)

# Optional: include Documents if it ever becomes non-empty and important
if [[ -d "$home_dir/Documents" ]]; then
  keep_paths+=("$home_dir/Documents")
fi

# Run a borg command. Stdout is dropped; stderr is logged on any problem.
# Borg exit 0 is success. Exit 1 (legacy) and 100-127 (BORG_EXIT_CODES=modern)
# are warnings: the command finished, and `borg create` has already saved the
# archive. Exit 2-99 and 128+ mean it did not finish.
# Always returns 0. Hard failures increment `failures` and the script keeps
# going so a vanished file cannot skip prune, check, or the other repo.
run_borg() {
  local desc="$1"
  shift

  local stderr_file rc err
  stderr_file=$(mktemp)
  log_info "$desc"

  rc=0
  "$@" >/dev/null 2>"$stderr_file" || rc=$?
  err=$(<"$stderr_file")
  rm -f "$stderr_file"

  if [[ "$rc" -eq 0 ]]; then
    log_ok "$desc"
    return 0
  fi

  if [[ "$rc" -eq 1 ]] || [[ "$rc" -ge 100 && "$rc" -le 127 ]]; then
    log_warn "$desc finished with warnings (borg exit ${rc})"
    [[ -n "$err" ]] && log_warn "$err"
    warnings=$((warnings + 1))
    return 0
  fi

  log_error "$desc failed (borg exit ${rc})"
  [[ -n "$err" ]] && log_error "$err"
  failures=$((failures + 1))
  return 0
}

# -------------------------
# Primary: create + prune + check
# -------------------------
log_info "Backing up to primary repo: $PRIMARY_REPO"
failures_before=$failures

# Redirect, not a pipe: run_borg must stay in this shell so `failures` sticks.
run_borg "Creating archive: $archive" \
  borg create \
  "${create_args[@]}" \
  "${extra_excludes[@]}" \
  "$PRIMARY_REPO::$archive" \
  "${keep_paths[@]}" \
  <"$pkglist_file"

run_borg "Pruning primary repo" \
  borg prune --list "$PRIMARY_REPO" \
  --keep-daily="$KEEP_DAILY" \
  --keep-weekly="$KEEP_WEEKLY" \
  --keep-monthly="$KEEP_MONTHLY"

run_borg "Checking primary repo" \
  borg check "$PRIMARY_REPO"

if [[ "$failures" -eq "$failures_before" ]]; then
  log_ok "Primary backup complete"
else
  log_error "Primary backup incomplete"
fi

# -------------------------
# External (optional): create + prune + check
# -------------------------
if mountpoint -q "$EXTERNAL_MOUNT" && [[ -d "$EXTERNAL_REPO" ]]; then
  log_info "External backup drive detected: $EXTERNAL_REPO"
  failures_before=$failures

  run_borg "Creating external archive: $archive" \
    borg create \
    "${create_args[@]}" \
    "${extra_excludes[@]}" \
    "$EXTERNAL_REPO::$archive" \
    "${keep_paths[@]}" \
    <"$pkglist_file"

  run_borg "Pruning external repo" \
    borg prune --list "$EXTERNAL_REPO" \
    --keep-daily="$KEEP_DAILY" \
    --keep-weekly="$KEEP_WEEKLY" \
    --keep-monthly="$KEEP_MONTHLY"

  run_borg "Checking external repo" \
    borg check "$EXTERNAL_REPO"

  if [[ "$failures" -eq "$failures_before" ]]; then
    log_ok "External backup complete"
  else
    log_error "External backup incomplete"
  fi
else
  log_skip "External backup drive not mounted (or repo missing)"
fi

# Prod DB Borg lives in object storage. USB gets a one-way copy; never ~/bucket.
if mountpoint -q "$EXTERNAL_MOUNT"; then
  log_info "Mirroring hetzner:statbook-prod-backups onto USB"
  if ! /home/jaime/.config/bash_custom/scripts/pull-prod-backups-usb.sh; then
    log_error "prod-backup USB pull failed (local Borg already done)"
    failures=$((failures + 1))
  fi
else
  log_skip "USB not mounted — skipping prod-backup pull"
fi

if [[ "$failures" -gt 0 ]]; then
  log_exit_bad "Backup incomplete: $archive (${failures} error(s), ${warnings} warning(s))"
fi
if [[ "$warnings" -gt 0 ]]; then
  log_exit_ok "Backup complete with warnings: $archive"
fi
log_exit_ok "Backup complete: $archive"
