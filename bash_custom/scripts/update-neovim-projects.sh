#!/usr/bin/env bash
# update-neovim-projects.sh - CORRECT ROOT: ADD DIRECTORY CONTAINING .git

set -euo pipefail

# Source logger (resolve git root from script's location, not CWD)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)/.util/log.sh"

# Logger config - no timestamps for cleaner output
LOG_TS=0

# Return 0 (true) if $1 is equal to or a descendant of any ALWAYS_INCLUDE path.
is_under_always_include() {
  local target="${1%/}"
  local a
  for a in "${ALWAYS_INCLUDE[@]}"; do
    a="${a%/}"
    if [[ "$target" == "$a" || "$target" == "$a"/* ]]; then
      return 0
    fi
  done
  return 1
}

# === CONFIG ===

DEV_DIR="${HOME}/Work"
HISTORY_FILE="${HOME}/.local/share/nvim/project_nvim/project_history"

ALWAYS_INCLUDE=(
  "${HOME}/.config"
  "${HOME}/Work/back_end/ru_statbook"
  "${HOME}/Work/back_end/statbook"
)

# Junk to prune (skip entire subtree)
PRUNE_NAMES=(
  "node_modules" "target" "__pycache__" ".pytest_cache" ".venv" "venv" "env" ".tox"
  ".next" ".angular" "build" "dist" ".cache" ".parcel-cache" "coverage" ".dart_tool"
  ".flutter-plugins" ".packages" "vendor" "logs" "log" "tmp" "temp" ".gradle" ".husky"
  ".idea" ".vscode"
)

# === START ===

log_info "Starting project discovery..."

[[ -d "$DEV_DIR" ]] || log_fatal "Directory not found → $DEV_DIR"
log_ok "Dev directory exists → $DEV_DIR"

declare -A projects

log_info "Checking always-included directories..."
for p in "${ALWAYS_INCLUDE[@]}"; do
  # ALWAYS_INCLUDE projects do not require git
  if [[ -d "$p" ]]; then
    projects["$p"]=1
    log_ok "Added → $p"
  else
    log_warn "Skipped → $p (no .git or missing)"
  fi
done

log_info "Scanning ~/Work/ (pruning junk + adding dir containing .git)..."

scanned_dirs=0
project_count=0

prune_args=()
for name in "${PRUNE_NAMES[@]}"; do
  prune_args+=(-name "$name" -prune -o)
done

tmpfile=$(mktemp)
find "$DEV_DIR" "(" "${prune_args[@]}" -true ")" -type d -print0 >"$tmpfile" 2>/dev/null || true

set +e

while IFS= read -r -d '' dir; do
  let scanned_dirs=scanned_dirs+1

  log_debug "Scanned: $dir"

  # Detect .git inside this dir → this dir IS the project root
  if [[ -d "$dir/.git" ]]; then
    if is_under_always_include "$dir"; then
      log_debug "Skipping $dir (has always-include parent)"
    elif [[ -z "${projects[$dir]+x}" ]]; then
      # Add THIS directory (the one containing .git)
      projects["$dir"]=1
      let project_count=project_count+1
      log_debug "Found .git → added project root: $dir"
    fi

    # Prune subtree (no deeper scan inside this project)
    find "$dir" -mindepth 1 -prune -o -quit 2>/dev/null || true
  fi
done <"$tmpfile"

set -e

rm -f "$tmpfile"

log_ok "Scan complete"

# Summary (always shown)
echo ""
log_info "Summary:"
echo "  Scanned directories : ${scanned_dirs}"
echo "  Projects collected  : ${project_count} (from ~/Work/) + ${#ALWAYS_INCLUDE[@]} always-included"
log_ok "Total unique projects: ${#projects[@]}"

if ((project_count + ${#ALWAYS_INCLUDE[@]} == 0)); then
  log_warn "No projects found — check ~/Work/ for .git directories"
fi

if [[ "${1:-}" == "--dry" ]]; then
  log_info "Dry run — would write these ${#projects[@]} projects to ${HISTORY_FILE}"
  echo ""
  printf '%s\n' "${!projects[@]}" | sort
  echo ""
  log_ok "Dry run complete — no file changed"
  exit 0
fi

# Real write
BACKUP_FILE="${HISTORY_FILE}.backup.$(date +%Y%m%d-%H%M%S)"

[[ -f "$HISTORY_FILE" ]] && cp "$HISTORY_FILE" "$BACKUP_FILE" && log_ok "Backed up → ${BACKUP_FILE}"

mkdir -p "$(dirname "$HISTORY_FILE")"
printf '%s\n' "${!projects[@]}" | sort >"$HISTORY_FILE"

log_ok "History file updated → ${HISTORY_FILE}"
log_info "Entries written: ${#projects[@]}"
echo "  → Open Neovim → :Telescope projects"
