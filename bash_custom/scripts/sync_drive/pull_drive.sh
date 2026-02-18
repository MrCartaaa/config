#!/usr/bin/env bash
set -euo pipefail

# Source logger
source "/home/jaime/.config/.util/log.sh"

# Logger config (no timestamps, no JSON)
LOG_TS=0
LOG_JSON=0

REMOTE_ROOT="ProtonDrive:"
REMOTE_BASE="steele_company/clients"
LOCAL_ROOT="$HOME/ProtonDrive/steele_company/clients"
FILTER_DIR="$BASH_CUSTOM_DIR/scripts/sync_drive"

CLIENT=""
DIRECT_PATH=""
DRY_RUN=false
NO_FILTER=false

usage() {
  cat <<EOF
Usage:
  sync-drive -c <abbr> [-p <subpath/>] [--dry-run] [--no-filter]
  sync-drive -p <steele_company/clients/.../> [--dry-run]

Client Abbreviations:
  adc  -> armstrong/adc
  agf  -> armstrong/agf
  jk   -> kegel
  rh   -> houghton
  hvh  -> madigan
  ugb  -> pocock/UGB - Underground Bakeshop
EOF
  exit 1
}

# ---------------------------
# Argument Parsing
# ---------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--client)
      CLIENT="${2:-}"
      shift 2
      ;;
    -p|--path)
      DIRECT_PATH="${2:-}"
      shift 2
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-filter)
      NO_FILTER=true
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$CLIENT" && -z "$DIRECT_PATH" ]]; then
  usage
fi

# ---------------------------
# Client Mapping
# ---------------------------

CLIENT_PATH=""

if [[ -n "$CLIENT" ]]; then
  case "$CLIENT" in
    adc) CLIENT_PATH="armstrong/adc" ;;
    agf) CLIENT_PATH="armstrong/agf" ;;
    jk)  CLIENT_PATH="kegel" ;;
    rh)  CLIENT_PATH="houghton" ;;
    hvh) CLIENT_PATH="madigan" ;;
    ugb) CLIENT_PATH="pocock/UGB - Underground Bakeshop" ;;
    *)
      log_exit_bad "Invalid client abbreviation: $CLIENT"
      ;;
  esac
fi

# ---------------------------
# Normalize Path
# ---------------------------

normalize_path() {
  local path="$1"

  if [[ "$path" == /* ]]; then
    log_exit_bad "Path cannot begin with '/'"
  fi

  [[ "$path" != */ ]] && path="${path}/"
  echo "$path"
}

if [[ -n "$DIRECT_PATH" ]]; then
  DIRECT_PATH="$(normalize_path "$DIRECT_PATH")"
fi

# ---------------------------
# Enforce Clean Workspace
# ---------------------------

WORKSPACE_ROOT="$HOME/ProtonDrive"

if [[ ! -d "$WORKSPACE_ROOT" ]]; then
  mkdir -p $WORKSPACE_ROOT
fi

if [[ -n "$(ls -A "$WORKSPACE_ROOT" 2>/dev/null)" ]]; then
  log_error "Workspace not clean: $WORKSPACE_ROOT is not empty"
  log_exit_bad "Run teardown before starting a new session"
fi

# ---------------------------
# Resolve Paths
# ---------------------------

if [[ -n "$CLIENT_PATH" && -n "$DIRECT_PATH" ]]; then
  REMOTE_PATH="${REMOTE_ROOT}${REMOTE_BASE}/${CLIENT_PATH}/${DIRECT_PATH}"
  LOCAL_PATH="${LOCAL_ROOT}/${CLIENT_PATH}/${DIRECT_PATH}"
elif [[ -n "$CLIENT_PATH" ]]; then
  REMOTE_PATH="${REMOTE_ROOT}${REMOTE_BASE}/${CLIENT_PATH}/"
  LOCAL_PATH="${LOCAL_ROOT}/${CLIENT_PATH}/"
else
  DIRECT_PATH="$(normalize_path "$DIRECT_PATH")"

  if [[ "$DIRECT_PATH" != ${REMOTE_BASE}/* ]]; then
    log_exit_bad "Direct path must begin with '${REMOTE_BASE}/'"
  fi

  REMOTE_PATH="${REMOTE_ROOT}${DIRECT_PATH}"
  RELATIVE_PATH="${DIRECT_PATH#${REMOTE_BASE}/}"
  LOCAL_PATH="${LOCAL_ROOT}/${RELATIVE_PATH}"
fi

CREATED_LOCAL_PATH=false
if [[ ! -d "$LOCAL_PATH" ]]; then
  mkdir -p "$LOCAL_PATH"
  CREATED_LOCAL_PATH=true
fi

# ---------------------------
# Filter Resolution
# ---------------------------

FILTER_FILE=""

if [[ -n "$CLIENT" && "$NO_FILTER" = false ]]; then
  FILTER_FILE="${FILTER_DIR}/${CLIENT}.filter"

  if [[ ! -f "$FILTER_FILE" ]]; then
    log_exit_bad "Missing filter file: $FILTER_FILE"
  fi
elif [[ -z "$CLIENT" && "$NO_FILTER" = false ]]; then
  # Use base filter when no client specified
  FILTER_FILE="${FILTER_DIR}/base.filter"

  if [[ ! -f "$FILTER_FILE" ]]; then
    # If base.filter doesn't exist, don't use any filter
    FILTER_FILE=""
  fi
fi

log_info "Remote: $REMOTE_PATH"
log_info "Local:  $LOCAL_PATH"

if [[ "$NO_FILTER" = true ]]; then
  log_info "Filter:  DISABLED (--no-filter)"
elif [[ -n "$FILTER_FILE" ]]; then
  log_info "Filter:  $FILTER_FILE"
fi

$DRY_RUN && log_dryrun "Mode:    DRY RUN"

# ---------------------------
# Remote Existence Check
# ---------------------------

if ! rclone lsf "$REMOTE_PATH" >/dev/null 2>&1; then
  log_error "Remote path inaccessible"

  if ! rclone about ProtonDrive: >/dev/null 2>&1; then
    log_error "Authentication failure detected"
    log_error "Run: rclone config reconnect ProtonDrive:"
    exit 2
  fi

  exit 1
fi

log_info "Writing Session..."

SESSION_FILE="$HOME/ProtonDrive/.session"

cat > "$SESSION_FILE" <<EOF
CLIENT="$CLIENT"
CLIENT_PATH="$CLIENT_PATH"
DIRECT_PATH="$DIRECT_PATH"
FILTER_FILE="$FILTER_FILE"
NO_FILTER=$NO_FILTER
EOF

log_info "Pulling Drive..."

# ---------------------------
# Sync Execution
# ---------------------------

RCLONE_FLAGS=(
  sync
  "$REMOTE_PATH"
  "$LOCAL_PATH"
  --fast-list
  --update
  --progress
  --stats 500ms
)

[[ -n "$FILTER_FILE" ]] && RCLONE_FLAGS+=(--filter-from "$FILTER_FILE")
$DRY_RUN && RCLONE_FLAGS+=(--dry-run)

set +e
# Add newlines before rclone output
rclone "${RCLONE_FLAGS[@]}"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  log_error "Sync failed with exit code $RC"

  # Basic auth re-check
  if ! rclone about ProtonDrive: >/dev/null 2>&1; then
    log_error "Authentication failure detected"
    log_error "Run: rclone config reconnect ProtonDrive:"
    exit 2
  fi

  exit $RC
fi

# ---------------------------
# Dry Run Cleanup
# ---------------------------

if $DRY_RUN && $CREATED_LOCAL_PATH; then
  log_info "Cleaning up dry-run directory: $LOCAL_PATH"
  rm -rf "$LOCAL_PATH"
fi

log_ok "Sync completed successfully"
