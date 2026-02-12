#!/usr/bin/env bash
set -euo pipefail
# check if the local machine has rsync
command -v rsync >/dev/null 2>&1 || {
  echo "ERROR: rsync not installed. Install with: sudo pacman -S --needed rsync"
  exit 127
}

DEBUG="${DEBUG:-0}"

if [[ "$DEBUG" == "1" ]]; then
  set -x
fi

# Self-elevate (preserve DEBUG across sudo)
# this is required becuase the /mnt/upload folder is locked down to root
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo --preserve-env=DEBUG -- "$0" "$@"
fi

# Source logger
source "/home/jaime/.config/.util/log.sh"

# Logger config
LOG_TS=1

# --------------------------
# CONFIG (DEV MACHINE)
# --------------------------

# Dict-style configuration
# All keys MUST match across arrays
declare -A SERVER_HOSTS=(
  ["main-server"]="192.168.2.17"
  # ["prod_server"]="10.0.0.5"
)

declare -A SERVER_USERS=(
  ["main-server"]="jared"
  # ["prod_server"]="backupuser"
)

REMOTE_PG_DIR="/mnt/backup/postgres"
# TODO: Implement configuration settings backups
REMOTE_CONFIG_DIR="/mnt/backup/config"
LOCAL_BASE_DIR="/mnt/upload"

[[ "$REMOTE_PG_DIR" != */ ]] || log_exit_bad "REMOTE_PG_DIR must NOT end with / (directory-itself semantics required)"

SSH_PORT=2222
SSH_KEY="/etc/backup/ssh/backup_servers_ed25519"

RSYNC_RSH="ssh -p ${SSH_PORT} -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes"

# Run a command, suppressing stdout but elevating errors
run_cmd() {
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

# --------------------------
# RUN
# --------------------------

log_hello "Starting server backup pull"

for SERVER_NAME in "${!SERVER_HOSTS[@]}"; do
  SERVER_HOST="${SERVER_HOSTS[$SERVER_NAME]}"
  SERVER_USER="${SERVER_USERS[$SERVER_NAME]}"

  [[ -n "$SERVER_USER" ]] || log_exit_bad "Missing SERVER_USER for ${SERVER_NAME}"

  LOCAL_DIR="${LOCAL_BASE_DIR}/${SERVER_NAME}/"
  # Safety: ensure trailing slash semantics
  [[ "$LOCAL_DIR" == */ ]] || log_exit_bad "LOCAL_DIR must end with /"

  log_info "Pulling from ${SERVER_HOST}:${REMOTE_PG_DIR} → ${LOCAL_DIR}"

  sudo mkdir -p "$LOCAL_DIR" >/dev/null || log_exit_bad "Failed to create $LOCAL_DIR"
  sudo chmod 750 "$LOCAL_DIR" >/dev/null || log_exit_bad "Failed to chmod $LOCAL_DIR"

  SRC="${SERVER_USER}@${SERVER_HOST}:${REMOTE_PG_DIR}"

  run_cmd "Syncing ${SERVER_NAME}" \
    rsync -a --delete \
    -e "${RSYNC_RSH}" \
    --rsync-path="sudo rsync" \
    "${SRC}" \
    "${LOCAL_DIR}"
done

log_exit_ok "All server pulls completed successfully"
