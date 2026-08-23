#!/usr/bin/env bash
set -euo pipefail

# Bucket sync dispatcher — routes to the appropriate operation script.
# Supports push, pull, and lifecycle.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -- help --
usage() {
  cat <<EOF
Usage: bucket <operation> [args...]

Operations:
  -p, --pull         Pull remote buckets to local (see: bucket -p -h)
  -u, --push         Push local buckets to remote (see: bucket -u -h)
      --lifecycle    Purge old object versions (see: bucket --lifecycle -h)
  -h, --help         Show this help message
EOF
  exit 0
}

# -- require an operation flag --
if [[ $# -eq 0 ]]; then
  usage
fi

OPERATION=""
case "$1" in
  -h|--help)
    usage
    ;;
  -p|--pull)
    OPERATION="pull"
    shift
    ;;
  -u|--push)
    OPERATION="push"
    shift
    ;;
  --lifecycle)
    OPERATION="lifecycle"
    shift
    ;;
  *)
    log_exit_bad "Unknown operation: $1 — use -p/--pull, -u/--push, --lifecycle, or -h/--help"
    ;;
esac

# -- dispatch (silent — each script handles its own logging) --
case "$OPERATION" in
  pull)
    exec "$SCRIPT_DIR/pull_bucket.sh" "$@"
    ;;
  push)
    exec "$SCRIPT_DIR/push_bucket.sh" "$@"
    ;;
  lifecycle)
    exec "$SCRIPT_DIR/lifecycle_bucket.sh" "$@"
    ;;
esac
