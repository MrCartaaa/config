#!/usr/bin/env bash
set -euo pipefail

# Source logger
source "/home/jaime/.config/.util/log.sh"

# Logger config (no timestamps, no JSON)
LOG_TS=0
LOG_JSON=0

WORKSPACE_ROOT="$HOME/ProtonDrive"
SESSION_FILE="$WORKSPACE_ROOT/.session"

# Check if running in TTY
if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
  log_exit_bad "Teardown requires an interactive terminal (TTY)"
fi

# Check for active session
if [[ ! -f "$SESSION_FILE" ]]; then
  log_exit_bad "No active session found"
fi

# Load session info
source "$SESSION_FILE"

# Display session info
log_info "Current session:"
log_info "  Client: ${CLIENT:-[direct path]}"
log_info "  Path: ${CLIENT_PATH}${DIRECT_PATH:+/$DIRECT_PATH}"

# Ask about pushing changes first
echo ""
read -r -p "    Would you like to push your changes before tearing down? [Y/n/c] " push_response

# Default to 'y' if empty response
push_response=${push_response:-y}

# Check push response
case "${push_response,,}" in
  c)
    log_info "Teardown cancelled"
    exit 0
    ;;
  n)
    log_info "Skipping push"
    ;;
  y|"")
    log_info "Pushing changes first..."
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Run push_drive.sh
    if ! "$SCRIPT_DIR/push_drive.sh"; then
      log_error "Push failed"
      read -r -p "    Continue with teardown anyway? [y/N] " continue_response
      continue_response=${continue_response:-n}
      if [[ ! "$continue_response" =~ ^[Yy]$ ]]; then
        log_info "Teardown cancelled"
        exit 1
      fi
    fi
    ;;
  *)
    log_error "Invalid response. Please enter y, n, or c"
    exit 1
    ;;
esac

# Confirm teardown
log_warn "This will remove all local files in $WORKSPACE_ROOT"
echo ""
read -r -p "    Are you sure you want to tear down the workspace? [y/N] " response

# Default to 'n' if empty response
response=${response:-n}

# Check response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
  log_info "Teardown cancelled"
  exit 0
fi

log_info "Removing local workspace..."
rm -rf "$WORKSPACE_ROOT"

log_ok "Teardown complete"
