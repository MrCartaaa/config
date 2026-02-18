#!/usr/bin/env bash
set -euo pipefail

# Pull Storj buckets to local workspace via rclone.
#
# Local buckets live in ~/Storj/<bucket>/.
# This pulls only buckets that already exist locally.
#
# Safety rule (safe-practical):
# - If local has changes vs remote, the pull aborts (no partial pulls).
# - Remote-only changes are allowed and will be pulled.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

REMOTE="storj"
BASE_DIR="$HOME/Storj"

DRY_RUN=false
VERBOSE=false
RCLONE_VERBOSE_FLAGS=()
INTERACTIVE=true
RCLONE_QUIET_FLAGS=()
PARALLEL=false

# -- help --
usage() {
  cat <<EOF
Usage: storj -p [-n|--dry-run] [-f|--parallel] [-vv|--verbose]

Options:
  -n, --dry-run    Preview sync without transferring
  -f, --parallel   Pull all buckets concurrently
  -vv, --verbose   Show rclone progress and live stats
  -h, --help       Show this help message
EOF
  exit 0
}

# -- parse args --
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -f|--parallel)
      PARALLEL=true
      shift
      ;;
    -vv|--verbose)
      VERBOSE=true
      RCLONE_VERBOSE_FLAGS=(-vv)
      shift
      ;;
    *)
      log_error "Unknown flag: $1"
      usage
      ;;
  esac
done

# -- validate base dir --
if [[ ! -d "$BASE_DIR" ]]; then
  log_exit_bad "Storj workspace not found: $BASE_DIR"
fi

# -- collect local buckets --
BUCKETS=()
for dir in "$BASE_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  BUCKETS+=("$(basename "$dir")")
done

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  log_exit_ok "No local buckets found in $BASE_DIR — nothing to pull"
fi

log_info "Pulling from Storj..."
log_info "Buckets to sync: ${BUCKETS[*]}"
$DRY_RUN && log_dryrun "Dry run enabled — no changes will be made"
$VERBOSE && log_info "Verbose mode enabled"
$PARALLEL && log_info "Parallel mode enabled"

if ! $VERBOSE; then
  RCLONE_QUIET_FLAGS=(-q)
fi

# -- detect systemd (for log-friendly rclone stats) --
if [[ -n "${INVOCATION_ID:-}" ]]; then
  INTERACTIVE=false
fi

# -- preflight check (local changes block pull) --
log_info "Preflight check: local changes block pull"

PRECHECK_FAILED=0

check_bucket() {
  local bucket="$1"
  local local_path="$BASE_DIR/$bucket/"
  local remote_path="$REMOTE:$bucket/"

  log_info "[$bucket] Checking local changes..."

  local err_file
  err_file=$(mktemp)
  set +e
  rclone check --one-way --fast-list "$local_path" "$remote_path" "${RCLONE_VERBOSE_FLAGS[@]}" >"$err_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    log_error "[$bucket] Local changes detected — pull blocked"
    if $VERBOSE; then
      log_error "[$bucket] rclone check output:"
      log_error "$(cat "$err_file")"
    else
      log_info "[$bucket] Run with -vv to see rclone check output"
    fi
    rm -f "$err_file"
    return 1
  fi

  rm -f "$err_file"
  log_ok "[$bucket] Clean"
  return 0
}

if $PARALLEL; then
  PIDS=()
  for bucket in "${BUCKETS[@]}"; do
    check_bucket "$bucket" &
    PIDS+=($!)
  done

  for pid in "${PIDS[@]}"; do
    wait "$pid" || PRECHECK_FAILED=1
  done
else
  for bucket in "${BUCKETS[@]}"; do
    printf "\n"
    check_bucket "$bucket" || PRECHECK_FAILED=1
  done

  printf "\n"
fi

if [[ $PRECHECK_FAILED -ne 0 ]]; then
  log_exit_bad "Preflight failed — pull aborted"
fi

# -- sync all buckets (mirror remote -> local) --
sync_bucket() {
  local bucket="$1"
  local local_path="$BASE_DIR/$bucket/"
  local remote_path="$REMOTE:$bucket/"

  log_info "[$bucket] Syncing $remote_path -> $local_path"

  local flags=(
    sync
    "$remote_path"
    "$local_path"
    --fast-list
    --create-empty-src-dirs
  )

  if $VERBOSE; then
    flags+=(--progress --stats 500ms)
  elif ! $INTERACTIVE; then
    flags+=(--stats-one-line --stats 30s)
  fi

  $DRY_RUN && flags+=(--dry-run)

  set +e
  rclone "${flags[@]}" "${RCLONE_QUIET_FLAGS[@]}"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    log_error "[$bucket] Sync failed (exit $rc)"
    return $rc
  fi

  log_ok "[$bucket] Sync complete"
  return 0
}

SYNC_FAILED=0

if $PARALLEL; then
  PIDS=()
  for bucket in "${BUCKETS[@]}"; do
    sync_bucket "$bucket" &
    PIDS+=($!)
  done

  for pid in "${PIDS[@]}"; do
    wait "$pid" || ((SYNC_FAILED++))
  done
else
  for bucket in "${BUCKETS[@]}"; do
    printf "\n"
    sync_bucket "$bucket" || ((SYNC_FAILED++))
  done

  printf "\n"
fi

if [[ $SYNC_FAILED -gt 0 ]]; then
  log_error "$SYNC_FAILED bucket(s) failed to sync"
  exit 1
fi
log_ok "All ${#BUCKETS[@]} bucket(s) pulled"
