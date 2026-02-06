#!/usr/bin/env bash
# update-neovim-projects.sh - CORRECT ROOT: ADD DIRECTORY CONTAINING .git

set -euo pipefail

# Colors & emoji (two spaces after emoji)
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' CYAN='\033[0;36m' NC='\033[0m'

emoji_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
emoji_ok() { echo -e "${GREEN}✅  $1${NC}"; }
emoji_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
emoji_error() {
  echo -e "${RED}❌  $1${NC}"
  exit 1
}

debug() {
  [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}DEBUG: $1${NC}"
}

# === CONFIG ===

DEV_DIR="${HOME}/Work"
HISTORY_FILE="${HOME}/.local/share/nvim/project_nvim/project_history"

ALWAYS_INCLUDE=(
  "${HOME}/.config"
)

# Junk to prune (skip entire subtree)
PRUNE_NAMES=(
  "node_modules" "target" "__pycache__" ".pytest_cache" ".venv" "venv" "env" ".tox"
  ".next" ".angular" "build" "dist" ".cache" ".parcel-cache" "coverage" ".dart_tool"
  ".flutter-plugins" ".packages" "vendor" "logs" "log" "tmp" "temp" ".gradle" ".husky"
  ".idea" ".vscode"
)

# === START ===

emoji_info "Starting project discovery..."

[[ -d "$DEV_DIR" ]] || emoji_error "Directory not found → $DEV_DIR"
emoji_ok "Dev directory exists → $DEV_DIR"

declare -A projects

emoji_info "Checking always-included directories..."
for p in "${ALWAYS_INCLUDE[@]}"; do
  if [[ -d "$p" ]] && [[ -d "$p/.git" ]]; then
    projects["$p"]=1
    emoji_ok "Added → $p"
  else
    emoji_warn "Skipped → $p (no .git or missing)"
  fi
done

emoji_info "Scanning ~/Work/ (pruning junk + adding dir containing .git)..."

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

  debug "Scanned: $dir"

  # Detect .git inside this dir → this dir IS the project root
  if [[ -d "$dir/.git" ]]; then
    # Add THIS directory (the one containing .git)
    if [[ -z "${projects[$dir]+x}" ]]; then
      projects["$dir"]=1
      let project_count=project_count+1
      debug "Found .git → added project root: $dir"
    fi

    # Prune subtree (no deeper scan inside this project)
    find "$dir" -mindepth 1 -prune -o -quit 2>/dev/null || true
  fi
done <"$tmpfile"

set -e

rm -f "$tmpfile"

emoji_ok "Scan complete"

# Summary (always shown)
echo ""
emoji_info "Summary:"
echo "  Scanned directories : ${scanned_dirs}"
echo "  Projects collected  : ${project_count} (from ~/Work/) + ${#ALWAYS_INCLUDE[@]} always-included"
emoji_ok "Total unique projects: ${#projects[@]}"

if ((project_count + ${#ALWAYS_INCLUDE[@]} == 0)); then
  emoji_warn "No projects found — check ~/Work/ for .git directories"
fi

if [[ "${1:-}" == "--dry" ]]; then
  emoji_info "Dry run — would write these ${#projects[@]} projects to ${HISTORY_FILE}"
  echo ""
  printf '%s\n' "${!projects[@]}" | sort
  echo ""
  emoji_ok "Dry run complete — no file changed"
  exit 0
fi

# Real write
BACKUP_FILE="${HISTORY_FILE}.backup.$(date +%Y%m%d-%H%M%S)"

[[ -f "$HISTORY_FILE" ]] && cp "$HISTORY_FILE" "$BACKUP_FILE" && emoji_ok "Backed up → ${BACKUP_FILE}"

mkdir -p "$(dirname "$HISTORY_FILE")"
printf '%s\n' "${!projects[@]}" | sort >"$HISTORY_FILE"

emoji_ok "History file updated → ${HISTORY_FILE}"
emoji_info "Entries written: ${#projects[@]}"
echo "  → Open Neovim → :Telescope projects"
