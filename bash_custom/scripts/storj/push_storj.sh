#!/usr/bin/env bash
set -euo pipefail

# Push local Storj workspace to remote Storj buckets via rclone.
#
# Each top-level directory in ~/Storj/ is treated as a bucket.
# New buckets are created with versioning enabled (for future conflict resolution).
#
# ⚠️  WARNING: This uses `rclone sync` which OVERRIDES the remote.
# This is safe ONLY when a single device is pushing.
# If multiple devices need to push, switch to `rclone copy` or
# implement conflict resolution. You've been warned.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

REMOTE="storj"
BASE_DIR="$HOME/Storj"

DRY_RUN=false
PARALLEL=false
TARGET_CLIENT=""
VERBOSE=false
INTERACTIVE=true
RCLONE_QUIET_FLAGS=()
DIR_MARKER=".statbook-dir"

# -- help --
usage() {
  cat <<EOF
Usage: storj -u [-c <bucket>] [-n|--dry-run] [-f|--parallel] [-vv|--verbose]

Options:
  -c, --client <name>   Push only this bucket (matches dir name in ~/Storj/)
  -n, --dry-run         Preview sync without transferring
  -f, --parallel        Sync all buckets concurrently
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
    *)
      log_error "Unknown flag: $1"
      usage
      ;;
  esac
done

# -- validate base dir exists and has content --
if [[ ! -d "$BASE_DIR" ]]; then
  log_exit_bad "Storj workspace not found: $BASE_DIR"
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
  # All buckets — every top-level dir in ~/Storj/
  for dir in "$BASE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    BUCKETS+=("$(basename "$dir")")
  done
fi

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  log_exit_ok "No buckets found in $BASE_DIR — nothing to push"
fi

# -- inputs resolved, announce the push --
log_info "Pushing to Storj..."
log_info "Buckets to sync: ${BUCKETS[*]}"
$DRY_RUN && log_dryrun "Dry run enabled — no changes will be made"
$PARALLEL && log_info "Parallel mode enabled"
$VERBOSE && log_info "Verbose mode enabled"

if ! $VERBOSE; then
  RCLONE_QUIET_FLAGS=(-q)
fi

# -- detect systemd (for log-friendly rclone stats) --
if [[ -n "${INVOCATION_ID:-}" ]]; then
  INTERACTIVE=false
fi

# -- fetch existing remote buckets once (avoid repeated API calls) --
EXISTING_BUCKETS=$(rclone lsd "$REMOTE:" 2>/dev/null | awk '{print $NF}' || true)

# -- check if a bucket exists on the remote --
bucket_exists() {
  local name="$1"
  echo "$EXISTING_BUCKETS" | grep -qx "$name"
}

# -- enable versioning on a bucket via S3 gateway --
# Generates temporary S3 credentials with `uplink share --register`,
# then uses rclone's inline S3 remote to set versioning = Enabled.
# This is required because the native storj rclone backend doesn't expose versioning.
enable_versioning() {
  local bucket="$1"

  log_info "[$bucket] Enabling versioning via S3 gateway..."

  # Generate S3 credentials scoped to this bucket
  local share_output
  share_output=$(uplink share --register --readonly=false "sj://$bucket/" 2>&1) || {
    log_error "[$bucket] Failed to generate S3 credentials"
    return 1
  }

  # Parse access key and secret key from uplink output
  local access_key secret_key endpoint
  access_key=$(echo "$share_output" | grep "Access Key ID:" | awk '{print $NF}')
  secret_key=$(echo "$share_output" | grep "Secret Key" | awk '{print $NF}')
  endpoint=$(echo "$share_output" | grep "Endpoint" | awk '{print $NF}')

  # Strip scheme — rclone inline remotes handle TLS via provider, not the URL
  endpoint="${endpoint#https://}"
  endpoint="${endpoint#http://}"

  if [[ -z "$access_key" || -z "$secret_key" || -z "$endpoint" ]]; then
    log_error "[$bucket] Could not parse S3 credentials from uplink output"
    return 1
  fi

  # Use rclone inline S3 remote — no persistent config needed
  local s3_remote=":s3,provider=Storj,access_key_id=${access_key},secret_access_key=${secret_key},endpoint=${endpoint}"

  local status
  status=$(rclone backend versioning "${s3_remote}:${bucket}" Enabled 2>&1) || {
    log_error "[$bucket] Failed to enable versioning: $status"
    return 1
  }

  log_ok "[$bucket] Versioning enabled (status: $status)"
}

# -- create a new bucket with versioning --
create_bucket() {
  local bucket="$1"
  local remote_path="$REMOTE:$bucket/"

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
    return 0
  }
}

# -- ensure directory markers so empty dirs persist --
ensure_dir_markers() {
  local root="$1"

  # Place a marker in every directory (empty or not) so structure persists.
  # This creates small zero-byte files on the remote but keeps hierarchy intact.
  find "$root" -type d -exec sh -c '
    marker="$1"/'"$DIR_MARKER"'
    [ -f "$marker" ] || : > "$marker"
  ' _ {} \;
}

# -- sync a single bucket: create if needed, then rclone sync --
sync_bucket() {
  local bucket="$1"
  local local_path="$BASE_DIR/$bucket/"
  local remote_path="$REMOTE:$bucket/"

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
  local flags=(
    sync
    "$local_path"
    "$remote_path"
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

# -- push: sequential or parallel --
FAILED=0

if $PARALLEL; then
  # Fire off all bucket syncs as background jobs
  PIDS=()
  for bucket in "${BUCKETS[@]}"; do
    sync_bucket "$bucket" &
    PIDS+=($!)
  done

  # Wait for each job and track failures
  for pid in "${PIDS[@]}"; do
    wait "$pid" || ((FAILED++))
  done
else
  # One at a time — clean logs, easy to debug
  for bucket in "${BUCKETS[@]}"; do
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

log_ok "All ${#BUCKETS[@]} bucket(s) synced"
