#!/usr/bin/env bash
set -euo pipefail

# Push local workspace to Hetzner Object Storage buckets via rclone.
#
# Each top-level directory in ~/bucket/ is treated as a remote bucket.
# New buckets are created with versioning enabled (for future conflict resolution).
#
# ⚠️  WARNING: This uses `rclone sync` which OVERRIDES the remote.
# This is safe ONLY when a single device is pushing.
# If multiple devices need to push, switch to `rclone copy` or
# implement conflict resolution. You've been warned.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

REMOTE="hetzner"
BASE_DIR="$HOME/bucket"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bucket-sync"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
PARALLEL=false
FORCE=false
TARGET_CLIENT=""
VERBOSE=false
INTERACTIVE=true
RCLONE_QUIET_FLAGS=()
DIR_MARKER=".statbook-dir"

# -- help --
usage() {
  cat <<EOF
Usage: bucket -u [-c <bucket>] [-n|--dry-run] [-f|--parallel] [-F|--force] [-vv|--verbose]

Options:
  -c, --client <name>   Push only this bucket (matches dir name in ~/bucket/)
  -n, --dry-run         Preview sync without transferring
  -f, --parallel        Sync all buckets concurrently
  -F, --force           Sync even if no local changes since last successful push
  -vv, --verbose        Show rclone progress and live stats
  -h, --help            Show this help message
EOF
  exit 0
}

# -- parse args --
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--client)
      TARGET_CLIENT="${2:-}"
      [[ -z "$TARGET_CLIENT" ]] && log_exit_bad "-c requires a bucket name"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -vv|--verbose)
      VERBOSE=true
      shift
      ;;
    -f|--parallel)
      PARALLEL=true
      shift
      ;;
    -F|--force)
      FORCE=true
      shift
      ;;
    *)
      log_error "Unknown flag: $1"
      usage
      ;;
  esac
done

# -- validate base dir exists and has content --
if [[ ! -d "$BASE_DIR" ]]; then
  log_exit_bad "Workspace not found: $BASE_DIR"
fi

# -- collect bucket directories --
BUCKETS=()

if [[ -n "$TARGET_CLIENT" ]]; then
  # Single bucket mode — validate it exists locally
  if [[ ! -d "$BASE_DIR/$TARGET_CLIENT" ]]; then
    log_exit_bad "Bucket dir not found: $BASE_DIR/$TARGET_CLIENT"
  fi
  BUCKETS+=("$TARGET_CLIENT")
else
  # All buckets — every top-level dir in ~/bucket/
  for dir in "$BASE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    BUCKETS+=("$(basename "$dir")")
  done
fi

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  log_exit_ok "No buckets found in $BASE_DIR — nothing to push"
fi

# -- inputs resolved, announce the push --
log_info "Pushing to Hetzner..."
log_info "Buckets to consider: ${BUCKETS[*]}"
$DRY_RUN && log_dryrun "Dry run enabled — no changes will be made"
$PARALLEL && log_info "Parallel mode enabled"
$FORCE && log_info "Force enabled — ignoring local change stamps"
$VERBOSE && log_info "Verbose mode enabled"

if ! $VERBOSE; then
  RCLONE_QUIET_FLAGS=(-q)
fi

# -- detect systemd (for log-friendly rclone stats) --
if [[ -n "${INVOCATION_ID:-}" ]]; then
  INTERACTIVE=false
fi

mkdir -p "$STATE_DIR"

# -- skip buckets with no local changes since last successful push --
# rclone sync already only uploads diffs; this avoids listing the remote at all
# when the local tree has not changed (hourly timer / lock-screen idle runs).
stamp_path() {
  printf '%s/%s.stamp\n' "$STATE_DIR" "$1"
}

bucket_has_local_changes() {
  local bucket="$1"
  local local_path="$BASE_DIR/$bucket"
  local stamp
  stamp="$(stamp_path "$bucket")"

  if [[ ! -f "$stamp" ]]; then
    return 0
  fi

  # Files, dirs, and deletes (parent dir mtime) all show up as -newer.
  [[ -n "$(find "$local_path" -newer "$stamp" -print -quit 2>/dev/null)" ]]
}

SYNC_BUCKETS=()
SKIPPED=0

for bucket in "${BUCKETS[@]}"; do
  if $FORCE || bucket_has_local_changes "$bucket"; then
    SYNC_BUCKETS+=("$bucket")
  else
    log_ok "[$bucket] No local changes — skip"
    ((SKIPPED++)) || true
  fi
done

if [[ ${#SYNC_BUCKETS[@]} -eq 0 ]]; then
  log_ok "All ${#BUCKETS[@]} bucket(s) unchanged — nothing to push"
  exit 0
fi

log_info "Buckets to sync: ${SYNC_BUCKETS[*]}"

# -- fetch existing remote buckets once (only if we actually need rclone) --
EXISTING_BUCKETS=$(rclone lsd "${REMOTE}:" 2>/dev/null | awk '{print $NF}' || true)

# -- check if a bucket exists on the remote --
bucket_exists() {
  local name="$1"
  echo "$EXISTING_BUCKETS" | grep -qx "$name"
}

# -- enable versioning on a bucket via the S3 remote --
enable_versioning() {
  local bucket="$1"

  log_info "[$bucket] Enabling versioning..."

  local status
  status=$(rclone backend versioning "${REMOTE}:${bucket}" Enabled 2>&1) || {
    log_error "[$bucket] Failed to enable versioning: $status"
    return 1
  }

  log_ok "[$bucket] Versioning enabled (status: $status)"
}

# -- create a new bucket with versioning --
create_bucket() {
  local bucket="$1"
  local remote_path="${REMOTE}:${bucket}/"

  log_info "[$bucket] Bucket doesn't exist remotely — creating..."

  if $DRY_RUN; then
    log_dryrun "[$bucket] Would create bucket with versioning"
    return 0
  fi

  # Step 1: create the bucket
  rclone mkdir "$remote_path" || {
    log_error "[$bucket] Failed to create bucket"
    return 1
  }

  # Step 2: enable versioning (buckets should always be versioned)
  enable_versioning "$bucket" || {
    log_warn "[$bucket] Bucket created but versioning failed — enable manually"
  }

  # Step 3: native lifecycle — cheaper than listing every old version weekly
  apply_native_lifecycle "$bucket" || {
    log_warn "[$bucket] Lifecycle policy failed — weekly script still covers versions"
  }
}

apply_native_lifecycle() {
  local bucket="$1"
  local helper="$SCRIPT_DIR/apply_lifecycle.py"

  if [[ ! -f "$helper" ]]; then
    log_warn "[$bucket] apply_lifecycle.py missing"
    return 1
  fi

  log_info "[$bucket] Applying native lifecycle (90d noncurrent, 7d multipart abort)..."
  python3 "$helper" "$bucket"
}

# -- ensure directory markers so empty dirs persist --
# Only empty dirs. Hetzner bills a 64 kB minimum per object, so a zero-byte
# marker in every directory (the old behaviour) is wasted storage.
ensure_dir_markers() {
  local root="$1"
  local dir marker

  while IFS= read -r -d '' dir; do
    marker="${dir}/${DIR_MARKER}"
    [[ -f "$marker" ]] || touch -- "$marker"
  done < <(find -- "$root" -type d -empty -print0)
}

# -- sync a single bucket: create if needed, then rclone sync --
sync_bucket() {
  local bucket="$1"
  local local_path="${BASE_DIR}/${bucket}/"
  local remote_path="${REMOTE}:${bucket}/"
  local -a flags

  # Create + enable versioning if the bucket is new
  if ! bucket_exists "$bucket"; then
    create_bucket "$bucket" || return 1
  fi

  log_info "[$bucket] Syncing $local_path -> $remote_path"

  if ! $DRY_RUN; then
    ensure_dir_markers "$local_path"
  fi

  # ⚠️ rclone sync = override remote with local state.
  # Single-device assumption — revisit for multi-device setups.
  # Hetzner: multipart above 100 MB; ingress is free, so the win is reliability.
  # Assign after `local` so bash 5.3 does not treat --flags as `local` options.
  flags=(
    sync
    "$local_path"
    "$remote_path"
    --fast-list
    --create-empty-src-dirs
    --s3-upload-cutoff=100Mi
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

  if ! $DRY_RUN; then
    touch "$(stamp_path "$bucket")"
  fi

  log_ok "[$bucket] Sync complete"
  return 0
}

# -- push: sequential or parallel --
FAILED=0

if $PARALLEL; then
  # Fire off all bucket syncs as background jobs
  PIDS=()
  for bucket in "${SYNC_BUCKETS[@]}"; do
    sync_bucket "$bucket" &
    PIDS+=($!)
  done

  # Wait for each job and track failures
  for pid in "${PIDS[@]}"; do
    wait "$pid" || ((FAILED++))
  done
else
  # One at a time — clean logs, easy to debug
  for bucket in "${SYNC_BUCKETS[@]}"; do
    printf "\n"
    sync_bucket "$bucket" || ((FAILED++))
  done

  printf "\n"
fi

# -- summary --
if [[ $FAILED -gt 0 ]]; then
  log_error "$FAILED bucket(s) failed to sync"
  exit 1
fi

if [[ $SKIPPED -gt 0 ]]; then
  log_ok "${#SYNC_BUCKETS[@]} bucket(s) synced, $SKIPPED unchanged"
else
  log_ok "All ${#SYNC_BUCKETS[@]} bucket(s) synced"
fi
