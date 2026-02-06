# Repo Checkin (`repo-checkin.sh`)

## What it does

Scans all git repositories in `~/Work/` plus configured always-include directories, and reports any that are "dirty":

* **Uncommitted changes** - staged, modified, or untracked files
* **Unpushed commits** - local commits not yet pushed to upstream
* **No upstream** - branch not tracking a remote

Optionally commits and pushes all dirty repos with a `[WIP]` message.

---

## Automated Execution

The script runs automatically via a **systemd user timer** at **3:30 AM daily** with `CHECKIN=1` (auto-commit and push). If the system is powered off at that time, it runs when you next log in (persistent timer).

---

## Systemd Timer Management

**Check next scheduled run:**

```bash
systemctl --user list-timers repo-checkin.timer
```

**Check last execution status:**

```bash
systemctl --user status repo-checkin.service
```

**View recent logs:**

```bash
journalctl --user -u repo-checkin.service --since today
```

**Run manually:**

```bash
systemctl --user start repo-checkin.service
```

**Disable the timer:**

```bash
systemctl --user stop repo-checkin.timer
systemctl --user disable repo-checkin.timer
```

**Re-enable the timer:**

```bash
systemctl --user enable repo-checkin.timer
systemctl --user start repo-checkin.timer
```

---

## Systemd Files

To modify the schedule or behavior, edit these files:

* **Service:** `~/.config/systemd/user/repo-checkin.service`
* **Timer:** `~/.config/systemd/user/repo-checkin.timer`

After editing, reload systemd:

```bash
systemctl --user daemon-reload
```

These files are backed up automatically by `borg-backup.sh` (via `~/.config`).

---

## Manual Usage

### Report dirty repos

```bash
repo-checkin.sh
```

Output groups issues by type:

```
  👋  HELLO  Checking repos for uncommitted/unpushed changes
  😶  WARN  [uncommitted]
  📦  OBJECT    ~/.bash_custom - main (staged:1 modified:2)
  😶  WARN  [unpushed]
  📦  OBJECT    ~/Work/myproject - feature (3 commit(s))

  📣  NOTICE  Found 2 dirty repo(s) out of 15 total.
  💬  INFO  Run with CHECKIN=1 to commit [WIP] and push
```

### Checkin all dirty repos

```bash
CHECKIN=1 repo-checkin.sh
```

This will:

1. Stage all changes (`git add -A`)
2. Commit with message `[WIP] Auto checkin <timestamp>`
3. Push to upstream (sets upstream if not configured)

Uses `--no-verify` to skip pre-commit hooks for speed.

### Checkin with custom commit message

```bash
CHECKIN=1 COMMIT_MSG="your message here" repo-checkin.sh
```

Uses the provided message instead of the default `[WIP]` message.

---

## Configuration

### Scanned directories

Edit the script to modify:

```bash
DEV_DIR="${HOME}/Work"

ALWAYS_INCLUDE=(
  "${HOME}/.config/nvim"
  "${HOME}/.bash_custom"
)
```

### Pruned directories

These are skipped during scanning (build artifacts, dependencies, etc.):

```bash
PRUNE_NAMES=(
  "node_modules" "target" "__pycache__" ...
)
```

---

## Undoing a WIP commit

If you need to continue working after a checkin:

```bash
# Uncommit but keep changes staged
git reset --soft HEAD~1

# Uncommit and unstage
git reset HEAD~1
```

---

## Dependencies

* Requires `log.sh` from `devops/bash_util` (sourced via `.util/log.sh`)
* Bash 4+ (uses associative arrays)
