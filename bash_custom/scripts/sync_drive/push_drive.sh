#!/usr/bin/env bash
set -euo pipefail

# Source logger
source "/home/jaime/.config/.util/log.sh"

# Logger config (no timestamps, no JSON)
LOG_TS=0
LOG_JSON=0

REMOTE_ROOT="ProtonDrive:"
REMOTE_BASE="steele_company/clients"
ARCHIVE_BASE="steele_company/_archive"
WORKSPACE_ROOT="$HOME/ProtonDrive"
LOCAL_ROOT="$HOME/ProtonDrive/steele_company/clients"

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      log_error "Usage: push-drive [--dry-run]"
      exit 1
      ;;
  esac
done

SESSION_FILE="$WORKSPACE_ROOT/.session"

if [[ ! -f "$SESSION_FILE" ]]; then
  log_exit_ok "No active session. Nothing to push."
fi

source "$SESSION_FILE"

if [[ -z "$(ls -A "$WORKSPACE_ROOT" 2>/dev/null)" ]]; then
  log_exit_ok "Workspace empty. Nothing to push."
fi

# Detect if systemd is running:
if [[ -z "${INVOCATION_ID:-}" ]]; then
  INTERACTIVE=true
  LOG_TS=1
else
  INTERACTIVE=false
fi

if [[ -n "$DIRECT_PATH" ]]; then
  REMOTE_PATH="${REMOTE_ROOT}${REMOTE_BASE}/${CLIENT_PATH}/${DIRECT_PATH}"
  LOCAL_PATH="${LOCAL_ROOT}/${CLIENT_PATH}/${DIRECT_PATH}"
  ARCHIVE_PATH="${REMOTE_ROOT}${ARCHIVE_BASE}/${CLIENT}/${DIRECT_PATH}"
else
  REMOTE_PATH="${REMOTE_ROOT}${REMOTE_BASE}/${CLIENT_PATH}/"
  LOCAL_PATH="${LOCAL_ROOT}/${CLIENT_PATH}/"
  ARCHIVE_PATH="${REMOTE_ROOT}${ARCHIVE_BASE}/${CLIENT}/"
fi

log_info "Remote:  $REMOTE_PATH"
log_info "Archive: $ARCHIVE_PATH"
log_info "Local:   $LOCAL_PATH"

$DRY_RUN && log_dryrun "Mode: DRY RUN"

RCLONE_FLAGS=(
  sync
  "$LOCAL_PATH"
  "$REMOTE_PATH"
  --fast-list
  --delete-during
  --track-renames
  --backup-dir "$ARCHIVE_PATH"
)

if $INTERACTIVE; then
  RCLONE_FLAGS+=(--progress --stats 500ms)
else
  RCLONE_FLAGS+=(--stats 30s --stats-one-line)
fi

if [[ "$NO_FILTER" = false && -n "$FILTER_FILE" ]]; then
  RCLONE_FLAGS+=(--filter-from "$FILTER_FILE")
fi

$DRY_RUN && RCLONE_FLAGS+=(--dry-run)

log_info "Pushing Drive..."

set +e
# Add newlines before rclone output
rclone "${RCLONE_FLAGS[@]}"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  log_error "Push failed (exit $RC)"

  if ! rclone about ProtonDrive: >/dev/null 2>&1; then
    log_error "Authentication failure detected"
    log_error "Run: rclone config reconnect ProtonDrive:"
    exit 2
  fi

  exit $RC
fi

log_ok "Push complete"
