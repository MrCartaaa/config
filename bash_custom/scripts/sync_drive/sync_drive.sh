#!/usr/bin/env bash
set -euo pipefail

# Source logger
source "/home/jaime/.config/.util/log.sh"

# Logger config (no timestamps, no JSON)
LOG_TS=0
LOG_JSON=0

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse first argument
if [[ $# -eq 0 ]]; then
  log_error "Usage: sync-drive <-p|--pull|-u|--push|-t|--teardown> [--] [args...]"
  log_exit_bad "No operation specified"
fi

OPERATION=""
case "$1" in
  -p|--pull)
    OPERATION="pull"
    shift
    ;;
  -u|--push)
    OPERATION="push"
    shift
    ;;
  -t|--teardown)
    OPERATION="teardown"
    shift
    ;;
  *)
    log_exit_bad "Invalid operation: $1. Use -p/--pull, -u/--push, or -t/--teardown"
    ;;
esac

# Check for -- separator if there are more arguments
if [[ $# -gt 0 ]]; then
  if [[ "$1" != "--" ]]; then
    log_exit_bad "Arguments after operation must be preceded by '--'"
  fi
  shift # Remove the --
fi

# Execute the appropriate script
case "$OPERATION" in
  pull)
    log_info "Pulling from ProtonDrive..."
    exec "$SCRIPT_DIR/pull_drive.sh" "$@"
    ;;
  push)
    log_info "Pushing changes to ProtonDrive..."
    exec "$SCRIPT_DIR/push_drive.sh" "$@"
    ;;
  teardown)
    log_info "Tearing down local workspace..."
    exec "$SCRIPT_DIR/teardown_drive.sh" "$@"
    ;;
esac