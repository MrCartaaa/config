#!/usr/bin/env bash
# repo-checkin.sh - Check for repos with uncommitted or unpushed changes
#
# Usage:
#   repo-checkin.sh                        # Report dirty repos
#   CHECKIN=1 repo-checkin.sh              # Commit [WIP] and push dirty repos
#   CHECKIN=1 COMMIT_MSG="msg" repo-checkin.sh  # Commit with custom message

set -euo pipefail

# Source logger (resolve git root from script's location, not CWD)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)/.util/log.sh"

# Logger config - no timestamps for cleaner output
LOG_TS=0

# === CONFIG ===

DEV_DIR="${HOME}/Work"

ALWAYS_INCLUDE=(
  "${HOME}/.config"
)

PRUNE_NAMES=(
  "node_modules" "target" "__pycache__" ".pytest_cache" ".venv" "venv" "env" ".tox"
  ".next" ".angular" "build" "dist" ".cache" ".parcel-cache" "coverage" ".dart_tool"
  ".flutter-plugins" ".packages" "vendor" "logs" "log" "tmp" "temp" ".gradle" ".husky"
  ".idea" ".vscode"
)

# === FUNCTIONS ===

# Arrays to collect dirty repos by category
declare -a UNCOMMITTED_REPOS=()
declare -a UNPUSHED_REPOS=()
declare -a NO_UPSTREAM_REPOS=()

# Check if repo has uncommitted changes and return details
get_uncommitted_details() {
  local git_status
  git_status=$(git status --porcelain 2>/dev/null)
  if [[ -n "$git_status" ]]; then
    local staged=$(echo "$git_status" | grep -c '^[MADRC]' || true)
    local unstaged=$(echo "$git_status" | grep -c '^.[MADRC]' || true)
    local untracked=$(echo "$git_status" | grep -c '^??' || true)

    local parts=""
    [[ $staged -gt 0 ]] && parts+="staged:$staged "
    [[ $unstaged -gt 0 ]] && parts+="modified:$unstaged "
    [[ $untracked -gt 0 ]] && parts+="untracked:$untracked"
    echo "${parts% }"
    return 0
  fi
  return 1
}

# Check if repo has unpushed commits and return count
get_unpushed_count() {
  local upstream
  upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null) || return 1
  local ahead
  ahead=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null) || return 1
  if [[ $ahead -gt 0 ]]; then
    echo "$ahead"
    return 0
  fi
  return 1
}

# Check if branch has no upstream configured
has_no_upstream() {
  ! git rev-parse --abbrev-ref "@{upstream}" &>/dev/null
}

# Perform WIP commit and push for a repo
checkin_repo() {
  local dir="$1"
  cd "$dir" || return 1

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M')

  # Use custom message or default
  local commit_msg
  if [[ -n "${COMMIT_MSG:-}" ]]; then
    commit_msg="$COMMIT_MSG"
  else
    commit_msg="[WIP] Auto checkin $timestamp"
  fi

  # Commit uncommitted changes if any
  local uncommitted_details
  if uncommitted_details=$(get_uncommitted_details); then
    git add -A
    git commit -m "$commit_msg" --no-verify || {
      log_error "Failed to commit in $dir"
      return 1
    }
    log_ok "Committed in $dir"
  fi

  # Push to remote
  local upstream
  upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null) || upstream=""

  if [[ -z "$upstream" ]]; then
    # No upstream - try to set one and push
    git push -u origin "$branch" --no-verify 2>/dev/null || {
      log_error "Failed to push $dir (no upstream, origin/$branch may not exist)"
      return 1
    }
    log_ok "Pushed $dir (set upstream to origin/$branch)"
  else
    git push --no-verify || {
      log_error "Failed to push $dir"
      return 1
    }
    log_ok "Pushed $dir"
  fi

  return 0
}

# Analyze a single repo and collect issues
analyze_repo() {
  local dir="$1"

  cd "$dir" || return 0

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="(detached)"

  local is_dirty=0

  # Check uncommitted
  local uncommitted_details
  if uncommitted_details=$(get_uncommitted_details); then
    is_dirty=1
    UNCOMMITTED_REPOS+=("$dir|$branch|$uncommitted_details")
  fi

  # Check unpushed
  local unpushed_count
  if unpushed_count=$(get_unpushed_count); then
    is_dirty=1
    UNPUSHED_REPOS+=("$dir|$branch|$unpushed_count commit(s)")
  elif has_no_upstream; then
    # Has commits but no upstream
    local has_commits
    has_commits=$(git rev-list --count HEAD 2>/dev/null) || has_commits=0
    if [[ $has_commits -gt 0 ]]; then
      is_dirty=1
      NO_UPSTREAM_REPOS+=("$dir|$branch|not tracking remote")
    fi
  fi

  return $is_dirty
}

# Print repos grouped by issue type
print_issues() {
  if [[ ${#UNCOMMITTED_REPOS[@]} -gt 0 ]]; then
    log_warn "[uncommitted]"
    for entry in "${UNCOMMITTED_REPOS[@]}"; do
      IFS='|' read -r dir branch details <<< "$entry"
      log_object "  $dir - $branch ($details)"
    done
  fi

  if [[ ${#UNPUSHED_REPOS[@]} -gt 0 ]]; then
    log_warn "[unpushed]"
    for entry in "${UNPUSHED_REPOS[@]}"; do
      IFS='|' read -r dir branch details <<< "$entry"
      log_object "  $dir - $branch ($details)"
    done
  fi

  if [[ ${#NO_UPSTREAM_REPOS[@]} -gt 0 ]]; then
    log_warn "[no-upstream]"
    for entry in "${NO_UPSTREAM_REPOS[@]}"; do
      IFS='|' read -r dir branch details <<< "$entry"
      log_object "  $dir - $branch ($details)"
    done
  fi
}

# === MAIN ===

# Check for CHECKIN flag (must be explicitly passed per-invocation)
DO_CHECKIN="${CHECKIN:-0}"

if [[ "$DO_CHECKIN" == "1" ]]; then
  if [[ -n "${COMMIT_MSG:-}" ]]; then
    log_hello "Checking in dirty repos (commit + push): $COMMIT_MSG"
  else
    log_hello "Checking in dirty repos ([WIP] commit + push)"
  fi
else
  log_hello "Checking repos for uncommitted/unpushed changes"
fi

declare -A projects
declare -A checked_in
dirty_count=0
checkin_count=0

# Collect always-included projects
for p in "${ALWAYS_INCLUDE[@]}"; do
  if [[ -d "$p" ]] && [[ -d "$p/.git" ]]; then
    projects["$p"]=1
  fi
done

# Scan ~/Work for git repos
if [[ -d "$DEV_DIR" ]]; then
  prune_args=()
  for name in "${PRUNE_NAMES[@]}"; do
    prune_args+=(-name "$name" -prune -o)
  done

  tmpfile=$(mktemp)
  find "$DEV_DIR" "(" "${prune_args[@]}" -true ")" -type d -print0 >"$tmpfile" 2>/dev/null || true

  while IFS= read -r -d '' dir; do
    if [[ -d "$dir/.git" ]]; then
      projects["$dir"]=1
    fi
  done <"$tmpfile"

  rm -f "$tmpfile"
fi

# Analyze each project
for project in $(printf '%s\n' "${!projects[@]}" | sort); do
  if ! analyze_repo "$project"; then
    ((dirty_count++)) || true
  fi
done

# Report or checkin
if [[ $dirty_count -eq 0 ]]; then
  log_ok "All ${#projects[@]} repos are clean."
  log_goodbye "Done"
else
  # Print grouped issues
  print_issues

  if [[ "$DO_CHECKIN" == "1" ]]; then
    echo ""
    log_info "Performing checkin..."

    # Checkin all dirty repos
    for entry in "${UNCOMMITTED_REPOS[@]}" "${UNPUSHED_REPOS[@]}" "${NO_UPSTREAM_REPOS[@]}"; do
      IFS='|' read -r dir branch details <<< "$entry"
      # Deduplicate (a repo may appear in multiple categories)
      if [[ -z "${checked_in[$dir]:-}" ]]; then
        checked_in[$dir]=1
        checkin_repo "$dir" && ((checkin_count++)) || true
      fi
    done

    log_notice "Checked in $checkin_count repo(s)."
    log_goodbye "Done"
  else
    echo ""
    log_notice "Found $dirty_count dirty repo(s) out of ${#projects[@]} total."
    log_info "Run with CHECKIN=1 to commit [WIP] and push"
  fi
fi
