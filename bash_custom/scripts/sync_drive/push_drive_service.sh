#!/usr/bin/env bash
# Wrapper script for systemd service to ensure proper environment and logging

# Set up environment
export HOME="/home/jaime"
export USER="jaime"
export BASH_CUSTOM_DIR="/home/jaime/.config/bash_custom"

# Source logger
source "/home/jaime/.config/.util/log.sh"

# Logger config (no timestamps since journald adds them, no JSON)
LOG_TS=0
LOG_JSON=0

# Log service start
log_info "Proton Drive push service starting"

# Check if session exists
SESSION_FILE="$HOME/ProtonDrive/.session"
if [[ ! -f "$SESSION_FILE" ]]; then
  log_info "No active session found - nothing to push"
  exit 0
fi

# Run the actual push script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/push_drive.sh" 2>&1

# Capture exit code
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
  log_info "Proton Drive push service completed successfully"
else
  log_error "Proton Drive push service failed with exit code: $EXIT_CODE"
fi

exit $EXIT_CODE