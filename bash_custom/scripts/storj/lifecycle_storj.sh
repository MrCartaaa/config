#!/usr/bin/env bash
set -euo pipefail

# Purge old object versions from Storj buckets that exceed a retention window.
#
# Storj doesn't support S3 lifecycle policies, so this script handles it.
# Designed to be run periodically by systemd (--user) timer.
#
# How it works:
#   1. Generates temporary S3 credentials via uplink
#   2. Lists all object versions (--s3-versions) per bucket
#   3. Identifies old versions (the -vYYYY-MM-DD-HHMMSS-NNN suffix pattern)
#   4. Deletes old versions whose timestamp exceeds the retention window
#
# Only old versions are deleted — current (latest) versions are never touched.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

BASE_DIR="$HOME/Storj"

# Default retention: 90 days
RETENTION_DAYS=90
DRY_RUN=false
TARGET_CLIENT=""
VERBOSE=false
RCLONE_VERBOSE_FLAGS=()
declare -A S3_REMOTE_CACHE
S3_FLAGS=(--s3-no-check-bucket)

# -- help --
usage() {
  cat <<EOF
Usage: storj --lifecycle [-c <bucket>] [-r <days>] [-n|--dry-run] [-vv|--verbose]

Options:
  -c, --client <name>    Target a single bucket (matches dir name in ~/Storj/)
  -r, --retention <days> Keep versions for this many days (default: 90)
  -n, --dry-run          List what would be deleted without deleting
  -vv, --verbose         Show verbose errors for debugging
  -h, --help             Show this help message
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
    -r|--retention)
      RETENTION_DAYS="${2:-}"
      [[ -z "$RETENTION_DAYS" ]] && log_exit_bad "-r requires a number of days"
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
      RCLONE_VERBOSE_FLAGS=(-vv)
      shift
      ;;
    *)
      log_error "Unknown flag: $1"
      usage
      ;;
  esac
done

# -- validate --
if [[ ! -d "$BASE_DIR" ]]; then
  log_exit_bad "Storj workspace not found: $BASE_DIR"
fi

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -eq 0 ]]; then
  log_exit_bad "Retention must be a positive integer (days)"
fi

# -- collect buckets --
BUCKETS=()

if [[ -n "$TARGET_CLIENT" ]]; then
  if [[ ! -d "$BASE_DIR/$TARGET_CLIENT" ]]; then
    log_exit_bad "Bucket dir not found: $BASE_DIR/$TARGET_CLIENT"
  fi
  BUCKETS+=("$TARGET_CLIENT")
else
  for dir in "$BASE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    BUCKETS+=("$(basename "$dir")")
  done
fi

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  log_exit_ok "No buckets found — nothing to clean"
fi

# -- announce --
log_info "Storj version lifecycle cleanup"
log_info "Retention: ${RETENTION_DAYS} days"
log_info "Buckets: ${BUCKETS[*]}"
$DRY_RUN && log_dryrun "Dry run — nothing will be deleted"
$VERBOSE && log_info "Verbose mode enabled"

# -- generate S3 credentials (scoped to all buckets) --
# We need the S3 gateway to list versions — the native storj remote doesn't support it.
# -- per-bucket S3 credentials (avoid multi-prefix list restrictions) --
get_s3_remote() {
  local bucket="$1"

  if [[ -n "${S3_REMOTE_CACHE[$bucket]:-}" ]]; then
    echo "${S3_REMOTE_CACHE[$bucket]}"
    return 0
  fi

  local share_output
  share_output=$(uplink share --register --readonly=false "sj://$bucket/" 2>&1) || {
    log_error "[$bucket] Failed to generate S3 credentials"
    if $VERBOSE; then
      log_error "[$bucket] uplink: $share_output"
    else
      log_info "[$bucket] Run with -vv to see uplink errors"
    fi
    return 1
  }

  local access_key secret_key endpoint
  access_key=$(echo "$share_output" | grep "Access Key ID:" | awk '{print $NF}')
  secret_key=$(echo "$share_output" | grep "Secret Key" | awk '{print $NF}')
  endpoint=$(echo "$share_output" | grep "Endpoint" | awk '{print $NF}')

  # Strip scheme — rclone inline remotes expect bare hostname
  endpoint="${endpoint#https://}"
  endpoint="${endpoint#http://}"

  if [[ -z "$access_key" || -z "$secret_key" || -z "$endpoint" ]]; then
    log_error "[$bucket] Could not parse S3 credentials from uplink output"
    return 1
  fi

  local s3_remote=":s3,provider=Storj,access_key_id=${access_key},secret_access_key=${secret_key},endpoint=${endpoint}"
  S3_REMOTE_CACHE[$bucket]="$s3_remote"
  echo "$s3_remote"
}

# -- cutoff date in epoch seconds --
CUTOFF_EPOCH=$(date -d "-${RETENTION_DAYS} days" +%s)
log_info "Cutoff date: $(date -d "@$CUTOFF_EPOCH" '+%Y-%m-%d %H:%M:%S')"

# -- process each bucket --
TOTAL_DELETED=0
FAILED=0

cleanup_bucket() {
  local bucket="$1"
  local deleted=0

  log_info "[$bucket] Listing old versions..."

  # List all versions including old ones and delete markers
  # --s3-versions surfaces old versions with a -vYYYY-MM-DD-HHMMSS-NNN suffix
  log_info "[$bucket] Generating S3 credentials..."
  local s3_remote
  s3_remote=$(get_s3_remote "$bucket") || return 1

  local versions_json
  local err_file
  err_file=$(mktemp)
  if ! versions_json=$(rclone lsjson --s3-versions --s3-version-deleted -R "${s3_remote}:${bucket}" "${S3_FLAGS[@]}" "${RCLONE_VERBOSE_FLAGS[@]}" 2>"$err_file"); then
    local err_msg
    err_msg=$(<"$err_file")
    rm -f "$err_file"
    if [[ "$err_msg" == *"directory not found"* ]]; then
      log_warn "[$bucket] Bucket not found on S3 gateway — skipping"
      return 0
    fi

    log_error "[$bucket] Failed to list versions"
    if $VERBOSE && [[ -n "$err_msg" ]]; then
      log_error "[$bucket] rclone: $err_msg"
    else
      log_info "[$bucket] Run with -vv to see rclone errors"
    fi
    return 1
  fi
  rm -f "$err_file"

  # Extract old version entries (they have the -vYYYY-MM-DD- suffix pattern)
  # Current versions don't have this suffix — they're never touched
  #
  # Format from rclone: each entry has Path, ModTime, Size, etc.
  # Old versions: "file-v2026-01-15-120000-000.txt"
  # Current versions: "file.txt"
  local old_versions
  local parse_err
  parse_err=$(mktemp)
  old_versions=$(echo "$versions_json" | \
    python3 -c "
import sys, json
from datetime import datetime

cutoff = $CUTOFF_EPOCH
entries = json.load(sys.stdin)

for entry in entries:
    path = entry.get('Path', '')
    # Old versions have -vYYYY-MM-DD-HHMMSS-NNN before the extension
    # This is rclone's version suffix pattern
    import re
    match = re.search(r'-v(\d{4}-\d{2}-\d{2}-\d{6})-\d{3}', path)
    if not match:
        continue  # Current version, skip

    # Parse the version timestamp from the filename
    ts_str = match.group(1)
    try:
        ts = datetime.strptime(ts_str, '%Y-%m-%d-%H%M%S')
        if ts.timestamp() < cutoff:
            print(path)
    except ValueError:
        continue
" 2>"$parse_err") || {
    local err_msg
    err_msg=$(<"$parse_err")
    rm -f "$parse_err"
    log_error "[$bucket] Failed to parse version data"
    if $VERBOSE && [[ -n "$err_msg" ]]; then
      log_error "[$bucket] python: $err_msg"
    else
      log_info "[$bucket] Run with -vv to see parser errors"
    fi
    return 1
  }
  rm -f "$parse_err"

  if [[ -z "$old_versions" ]]; then
    log_ok "[$bucket] No expired versions found"
    return 0
  fi

  local count
  count=$(echo "$old_versions" | wc -l)
  log_info "[$bucket] Found $count expired version(s)"

  # Delete each expired version
  while IFS= read -r version_path; do
    [[ -z "$version_path" ]] && continue

    if $DRY_RUN; then
      log_dryrun "[$bucket] Would delete: $version_path"
    else
      local del_err
      del_err=$(mktemp)
      if rclone deletefile "${s3_remote}:${bucket}/${version_path}" "${S3_FLAGS[@]}" "${RCLONE_VERBOSE_FLAGS[@]}" 2>"$del_err"; then
        ((deleted++))
      else
        local err_msg
        err_msg=$(<"$del_err")
        log_error "[$bucket] Failed to delete: $version_path"
        if $VERBOSE && [[ -n "$err_msg" ]]; then
          log_error "[$bucket] rclone: $err_msg"
        else
          log_info "[$bucket] Run with -vv to see rclone errors"
        fi
      fi
      rm -f "$del_err"
    fi
  done <<< "$old_versions"

  if $DRY_RUN; then
    log_dryrun "[$bucket] Would delete $count version(s)"
  else
    log_ok "[$bucket] Deleted $deleted expired version(s)"
    ((TOTAL_DELETED += deleted))
  fi

  return 0
}

for bucket in "${BUCKETS[@]}"; do
  printf "\n"
  cleanup_bucket "$bucket" || ((FAILED++))
done

printf "\n"

# -- summary --
if [[ $FAILED -gt 0 ]]; then
  log_error "$FAILED bucket(s) had errors during cleanup"
  exit 1
fi

if $DRY_RUN; then
  log_ok "Dry run complete"
else
  log_ok "Lifecycle cleanup complete — $TOTAL_DELETED total version(s) purged"
fi
