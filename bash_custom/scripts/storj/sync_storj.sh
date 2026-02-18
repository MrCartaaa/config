#!/usr/bin/env bash
set -euo pipefail

# Storj sync dispatcher — routes to the appropriate operation script.
# Supports push, pull, and lifecycle.

source "/home/jaime/.config/.util/log.sh"

LOG_TS=0
LOG_JSON=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -- help --
usage() {
  cat <<EOF
Usage: storj <operation> [args...]

Operations:
  -p, --pull         Pull remote buckets to local (see: storj -p -h)
  -u, --push         Push local buckets to Storj (see: storj -u -h)
      --lifecycle    Purge old object versions (see: storj --lifecycle -h)
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
    exec "$SCRIPT_DIR/pull_storj.sh" "$@"
    ;;
  push)
    exec "$SCRIPT_DIR/push_storj.sh" "$@"
    ;;
  lifecycle)
    exec "$SCRIPT_DIR/lifecycle_storj.sh" "$@"
    ;;
esac
