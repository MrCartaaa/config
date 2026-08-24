#!/usr/bin/env bash
set -euo pipefail

# Keep Hetzner bucket cost in line with their billing:
#   - native lifecycle (noncurrent versions + multipart abort + delete markers)
#   - rclone cleanup of leftover multipart fragments
#
# Current (latest) objects are never expired. Designed for systemd --user timer.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

REMOTE="hetzner"
BASE_DIR="$HOME/bucket"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=protected.sh
source "${SCRIPT_DIR}/protected.sh"

# Default retention: 90 days
RETENTION_DAYS=90
DRY_RUN=false
TARGET_CLIENT=""
VERBOSE=false
RCLONE_VERBOSE_FLAGS=()
S3_FLAGS=(--s3-no-check-bucket)

# -- help --
usage() {
  cat <<EOF
Usage: bucket --lifecycle [-c <bucket>] [-r <days>] [-n|--dry-run] [-vv|--verbose]

Options:
  -c, --client <name>    Target a single bucket (matches dir name in ~/bucket/)
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
  log_exit_bad "Workspace not found: $BASE_DIR"
fi

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -eq 0 ]]; then
  log_exit_bad "Retention must be a positive integer (days)"
fi

# -- collect buckets --
BUCKETS=()

if [[ -n "$TARGET_CLIENT" ]]; then
  refuse_protected_bucket "$TARGET_CLIENT"
  if [[ ! -d "$BASE_DIR/$TARGET_CLIENT" ]]; then
    log_exit_bad "Bucket dir not found: $BASE_DIR/$TARGET_CLIENT"
  fi
  BUCKETS+=("$TARGET_CLIENT")
else
  for dir in "$BASE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    if bucket_is_protected "$name"; then
      log_exit_bad "Remove ~/bucket/${name}; prod DB backups must not live in ~/bucket"
    fi
    BUCKETS+=("$name")
  done
fi

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  log_exit_ok "No buckets found — nothing to clean"
fi

# -- announce --
log_info "Hetzner lifecycle (native policy + multipart cleanup)"
log_info "Noncurrent version retention: ${RETENTION_DAYS} days"
log_info "Buckets: ${BUCKETS[*]}"
$DRY_RUN && log_dryrun "Dry run — policies will not be applied, multipart cleanup is preview-only"
$VERBOSE && log_info "Verbose mode enabled"

FAILED=0

cleanup_bucket() {
  local bucket="$1"
  local helper="$SCRIPT_DIR/apply_lifecycle.py"

  log_info "[$bucket] Ensuring native lifecycle policy..."

  if $DRY_RUN; then
    log_dryrun "[$bucket] Would apply noncurrent=${RETENTION_DAYS}d, multipart abort=7d"
  else
    if ! python3 "$helper" --days "$RETENTION_DAYS" "$bucket"; then
      log_error "[$bucket] Failed to apply lifecycle policy"
      return 1
    fi
    log_ok "[$bucket] Lifecycle policy applied"
  fi

  log_info "[$bucket] Cleaning incomplete multipart uploads older than 7 days..."
  local rclone_global=("${S3_FLAGS[@]}")
  $DRY_RUN && rclone_global+=(--dry-run)
  $VERBOSE && rclone_global+=(-vv)

  if rclone "${rclone_global[@]}" backend cleanup -o max-age=7d "${REMOTE}:${bucket}"; then
    log_ok "[$bucket] Multipart cleanup complete"
  else
    log_warn "[$bucket] Multipart cleanup failed (non-fatal)"
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
  log_ok "Lifecycle cleanup complete"
fi
