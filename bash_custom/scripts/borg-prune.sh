#!/usr/bin/env bash
set -euo pipefail

# one-time-borg-keep-latest.sh
#
# Deletes ALL archives in a Borg repo except the most recent one,
# then compacts the repo to reclaim space.
#
# Usage:
#   ./one-time-borg-keep-latest.sh /mnt/backup/borg
#   ./one-time-borg-keep-latest.sh "/run/media/jaime/371 - BACKUP/borg"
#
# Notes:
# - This is destructive. There is no undo.
# - Requires borg >= 1.2 (for `borg compact`). If compact is unavailable, it will skip.
# - Prompts once for passphrase and reuses it for all borg commands.

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo "ERROR: repo path required"
  echo "Example: $0 /mnt/backup/borg"
  exit 1
fi

if [[ ! -d "$REPO" ]]; then
  echo "ERROR: repo not found at: $REPO"
  exit 1
fi

# Prompt once for Borg passphrase (reused for all borg commands)
if [[ -z "${BORG_PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter Borg passphrase for $REPO: " BORG_PASSPHRASE
  echo
  export BORG_PASSPHRASE
fi
cleanup() { unset BORG_PASSPHRASE; }
trap cleanup EXIT

# Get most recent archive name (borg list output is chronological; last line is newest)
latest="$(borg list "$REPO" --short | tail -n 1 || true)"
if [[ -z "$latest" ]]; then
  echo "ERROR: no archives found in repo: $REPO"
  exit 1
fi

echo "Repo:    $REPO"
echo "Keeping: $latest"
echo

# Delete everything except the latest archive
# We stream the archive list and delete line-by-line to avoid argument limits.
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ "$name" != "$latest" ]]; then
    echo "Deleting: $name"
    borg delete -v "$REPO::$name"
  fi
done < <(borg list "$REPO" --short)

echo
echo "Verifying repo..."
borg check "$REPO"

# Reclaim disk space (if supported)
if borg help 2>/dev/null | grep -qE '\bcompact\b'; then
  echo "Compacting repo to reclaim space..."
  borg compact "$REPO"
else
  echo "NOTE: borg compact not available on this version; skipping compaction."
fi

echo
echo "Remaining archives:"
borg list "$REPO" --short
