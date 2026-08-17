#!/usr/bin/env bash
# Create or discard an Obsidian quick note in the main vault.
set -euo pipefail

vault="${OBSIDIAN_VAULT:-$HOME/Obsidian/main}"
notes_dir="$vault/quick-notes"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
state_file="$state_dir/quick-note-last"

mkdir -p "$notes_dir" "$state_dir"

urlencode() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

is_header_only() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
text = re.sub(r"^# \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s*", "", text)
sys.exit(0 if not text.strip() else 1)
PY
}

discard() {
  local file="${1:-}"
  if [[ -z "$file" && -f "$state_file" ]]; then
    file="$(cat "$state_file")"
  fi
  [[ -n "${file:-}" ]] || return 0

  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [[ -f "$file" ]] && break
    sleep 0.1
  done

  if is_header_only "$file"; then
    rm -f "$file"
  fi
}

if [[ "${1:-}" == "--discard" ]]; then
  discard "${2:-}"
  exit 0
fi

# A previous empty note is leftover scratch; keep notes that have a body.
discard

name="$(date +'%Y-%m-%d %H:%M:%S')"
file="$notes_dir/${name}.md"
printf '# %s\n\n' "$name" >"$file"
printf '%s\n' "$file" >"$state_file"

# Obsidian's `new` action treats `file` as a name and rejects `/`.
# Create the note on disk, then open that path in a pop-out window.
uri="obsidian://open?path=$(urlencode "$file")&paneType=window"

if command -v uwsm-app >/dev/null 2>&1; then
  exec uwsm-app -- obsidian "$uri"
fi
exec obsidian "$uri"
