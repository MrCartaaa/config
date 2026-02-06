#!/usr/bin/env bash
set -euo pipefail

# Self-elevate
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

# Source logger (resolve git root from script's location, not CWD)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir" && git rev-parse --show-toplevel)"
source "$repo_root/.util/log.sh"

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
cleanup() { unset BORG_PASSPHRASE; }
trap cleanup EXIT

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
  "/mnt/upload"
)

# Excludes that apply even in allowlist mode (subpaths inside included dirs)
# Here: exclude Neovim config.
extra_excludes=(
  --exclude "$home_dir/.gradle/daemon"
  --exclude "$home_dir/.gradle/caches/transforms-*"
  --exclude "$home_dir/.gradle/caches/journal-*"
  --exclude "$home_dir/.config/nvim"
)

# Optional: include Documents if it ever becomes non-empty and important
if [[ -d "$home_dir/Documents" ]]; then
  keep_paths+=("$home_dir/Documents")
fi

# Run a borg command, suppressing stdout but elevating errors
run_borg() {
  local desc="$1"
  shift

  local stderr_file
  stderr_file=$(mktemp)

  log_info "$desc"

  if ! "$@" >/dev/null 2>"$stderr_file"; then
    local err
    err=$(<"$stderr_file")
    rm -f "$stderr_file"
    log_error "$desc failed"
    [[ -n "$err" ]] && log_error "$err"
    return 1
  fi

  rm -f "$stderr_file"
  log_ok "$desc"
}

# -------------------------
# Primary: create + prune + check
# -------------------------
log_info "Backing up to primary repo: $PRIMARY_REPO"

pacman -Qqe | run_borg "Creating archive: $archive" \
  borg create \
  "${create_args[@]}" \
  "${extra_excludes[@]}" \
  "$PRIMARY_REPO::$archive" \
  "${keep_paths[@]}"

run_borg "Pruning primary repo" \
  borg prune --list "$PRIMARY_REPO" \
  --keep-daily="$KEEP_DAILY" \
  --keep-weekly="$KEEP_WEEKLY" \
  --keep-monthly="$KEEP_MONTHLY"

run_borg "Checking primary repo" \
  borg check "$PRIMARY_REPO"

log_ok "Primary backup complete"

# -------------------------
# External (optional): create + prune + check
# -------------------------
if mountpoint -q "$EXTERNAL_MOUNT" && [[ -d "$EXTERNAL_REPO" ]]; then
  log_info "External backup drive detected: $EXTERNAL_REPO"

  pacman -Qqe | run_borg "Creating external archive: $archive" \
    borg create \
    "${create_args[@]}" \
    "${extra_excludes[@]}" \
    "$EXTERNAL_REPO::$archive" \
    "${keep_paths[@]}"

  run_borg "Pruning external repo" \
    borg prune --list "$EXTERNAL_REPO" \
    --keep-daily="$KEEP_DAILY" \
    --keep-weekly="$KEEP_WEEKLY" \
    --keep-monthly="$KEEP_MONTHLY"

  run_borg "Checking external repo" \
    borg check "$EXTERNAL_REPO"

  log_ok "External backup complete"
else
  log_skip "External backup drive not mounted (or repo missing)"
fi

log_exit_ok "Backup complete: $archive"
