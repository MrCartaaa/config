# Storj Sync Scripts

Push local workspace (`~/Storj/`) to Storj cloud storage via rclone.

Each top-level directory in `~/Storj/` maps 1:1 to a Storj bucket.

## Bucket Structure

```
~/Storj/
  armstrong/    -> storj:armstrong
  houghton/    -> storj:houghton
  kegel/       -> storj:kegel
  madigan/     -> storj:madigan
  pocock/      -> storj:pocock
  steele/      -> storj:steele
```

## Usage

```bash
# Push all buckets
storj -u

# Push a single bucket
storj -u -c armstrong

# Dry run (preview only)
storj -u --dry-run
storj -u -c pocock -n

# Parallel sync (all buckets concurrently)
storj -u -f

# Verbose push (live progress)
storj -u -vv

# Pull all local buckets (remote -> local mirror)
storj -p

# Parallel pull
storj -p -f

# Verbose pull (live progress)
storj -p -vv

# Version lifecycle cleanup
storj --lifecycle                    # purge versions older than 90 days (default)
storj --lifecycle -r 30              # purge versions older than 30 days
storj --lifecycle -c pocock -n       # dry run on a single bucket
storj --lifecycle -r 60 --dry-run    # preview 60-day cleanup
storj --lifecycle -vv               # verbose errors for debugging

# Help
storj -h
storj -u -h
storj --lifecycle -h
```

## Single-Device Warning

**This setup uses `rclone sync`, which makes the remote an exact mirror of local.**
Deleted or modified local files will be deleted/overwritten on the remote.

This is safe only when **one device** is the source of truth.
If you add more devices, switch to `rclone copy` or implement proper conflict resolution.

## Versioning

New buckets are created with **object versioning enabled**. This preserves previous versions
of objects on the remote even when overwritten or deleted by `rclone sync`.

Versioning is enabled via Storj's S3-compatible gateway. On bucket creation, the script:
1. Creates the bucket with `rclone mkdir` (native storj remote)
2. Generates temporary S3 credentials with `uplink share --register`
3. Enables versioning with `rclone backend versioning` (inline S3 remote)

This means previous versions are recoverable even under the current single-device override model.
When multi-device push/pull is implemented, versioning will be used for conflict resolution.

### How versioning cost works

`rclone sync` only uploads files that have changed (by size/modtime). Unchanged files are
skipped entirely — no new version is created on Storj. You only pay for versions of files
that were actually modified or deleted.

## Version Lifecycle

Storj doesn't support S3 lifecycle policies, so old versions are cleaned up by
`lifecycle_storj.sh`, which runs on a systemd timer (weekly by default).

The script:
1. Lists all object versions per bucket via the S3 gateway (`--s3-versions`)
2. Identifies old versions by their `-vYYYY-MM-DD-HHMMSS-NNN` filename suffix
3. Deletes versions whose timestamp exceeds the retention window

**Default retention: 90 days.** Override with `-r <days>`.

### Systemd timer

```bash
# Enable the weekly lifecycle timer
systemctl --user enable --now storj-lifecycle.timer

# Check timer status
systemctl --user status storj-lifecycle.timer

# Run manually
systemctl --user start storj-lifecycle.service

# View logs
journalctl --user -u storj-lifecycle.service
```

## Pull Behavior

Pull mirrors remote -> local for **local buckets only** (dirs under `~/Storj/`).

Preflight rule (safe-practical):
- If local has changes vs remote, pull is blocked to avoid overwrites.
- Remote-only changes are allowed and will be pulled.

Empty directories are preserved by syncing directory markers
(`.statbook-dir` files in every directory).

### Systemd pull at login

```bash
# Enable pull at login
systemctl --user enable --now storj-pull.timer

# Run manually
systemctl --user start storj-pull.service

# View logs
journalctl --user -u storj-pull.service
```

### Systemd push schedule

```bash
# Enable push every 10 minutes
systemctl --user enable --now storj-push.timer

# Run manually
systemctl --user start storj-push.service

# View logs
journalctl --user -u storj-push.service
```

Push and pull use a shared lock (`/tmp/storj-sync.lock`) so they never overlap.

## Lock/Sleep Integration

Hypridle runs `storj-push.service` before lock and sleep.
This ensures a push completes before the session locks or suspends.

## Filters

The `filters/` directory exists for future use. Currently, all files are pushed without filtering.

## Prerequisites

- `rclone` with `storj:` remote configured (`rclone listremotes` to verify)
- `uplink` CLI configured with access to the Storj satellite (used for S3 credential generation)
- `python3` (used by lifecycle script to parse version timestamps from JSON)
