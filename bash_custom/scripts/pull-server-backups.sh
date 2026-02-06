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

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*"; }

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

[[ "$REMOTE_PG_DIR" != */ ]] || {
  echo "REMOTE_PG_DIR must NOT end with / (directory-itself semantics required)"
  exit 1
}

SSH_PORT=2222
SSH_KEY="/etc/backup/ssh/backup_servers_ed25519"

RSYNC_RSH="ssh -p ${SSH_PORT} -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes"

# --------------------------
# RUN
# --------------------------

for SERVER_NAME in "${!SERVER_HOSTS[@]}"; do
  SERVER_HOST="${SERVER_HOSTS[$SERVER_NAME]}"
  SERVER_USER="${SERVER_USERS[$SERVER_NAME]}"

  if [[ -z "$SERVER_USER" ]]; then
    echo "Missing SERVER_USER for ${SERVER_NAME}"
    exit 1
  fi

  LOCAL_DIR="${LOCAL_BASE_DIR}/${SERVER_NAME}/"
  # Safety: ensure trailing slash semantics
[[ "$LOCAL_DIR" == */ ]] || {
  echo "LOCAL_DIR must end with /"
  exit 1
}

  log "Pulling PG artifacts from ${SERVER_HOST}:${REMOTE_PG_DIR}"
  log "→ Local destination: ${LOCAL_DIR}"

  sudo mkdir -p "$LOCAL_DIR"
  sudo chmod 750 "$LOCAL_DIR"

SRC="${SERVER_USER}@${SERVER_HOST}:${REMOTE_PG_DIR}"

rsync -av --delete \
  -e "${RSYNC_RSH}" \
  --rsync-path="sudo rsync" \
  "${SRC}" \
  "${LOCAL_DIR}"

  log "Pull complete for ${SERVER_NAME}"
done

log "All server pulls completed successfully"
