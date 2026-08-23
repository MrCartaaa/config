# Bucket Sync

Push local workspace (`~/bucket/`) to Hetzner Object Storage via rclone.

Each top-level directory in `~/bucket/` maps 1:1 to a remote bucket.

## Bucket Structure

```
~/bucket/
  armstrong/    -> hetzner:armstrong
  carter/       -> hetzner:carter
  houghton/     -> hetzner:houghton
  kegel/        -> hetzner:kegel
  lindale/      -> hetzner:lindale
  madigan/      -> hetzner:madigan
  michelle/     -> hetzner:michelle
  pocock/       -> hetzner:pocock
  steele/       -> hetzner:steele
  util/         -> hetzner:util
```

Unrelated buckets already on the remote (for example `mae-tech`) are left alone.

## Usage

```bash
# Push all buckets
bucket -u

# Push a single bucket
bucket -u -c armstrong

# Dry run (preview only)
bucket -u --dry-run
bucket -u -c pocock -n

# Parallel sync (all buckets concurrently)
bucket -u -f

# Force a full compare even if nothing changed locally
bucket -u -F

# Verbose push (live progress)
bucket -u -vv

# Pull all local buckets (remote -> local mirror)
bucket -p

# Parallel pull
bucket -p -f

# Verbose pull (live progress)
bucket -p -vv

# Version lifecycle cleanup
bucket --lifecycle                    # purge versions older than 90 days (default)
bucket --lifecycle -r 30              # purge versions older than 30 days
bucket --lifecycle -c pocock -n       # dry run on a single bucket
bucket --lifecycle -r 60 --dry-run    # preview 60-day cleanup
bucket --lifecycle -vv               # verbose errors for debugging

# Help
bucket -h
bucket -u -h
bucket --lifecycle -h
```

## Incremental push

`rclone sync` only **uploads files that differ** (size/modtime). Unchanged files
are not re-uploaded. The first push to an empty remote is a full upload by
definition.

After a successful push, each bucket gets a stamp in
`~/.local/state/bucket-sync/`. Later runs skip rclone entirely for buckets with
no local changes (new/edited files, or deletes — parent directory mtime).
Hourly and lock-screen pushes then cost nothing when the tree is idle.

Use `bucket -u -F` to force a compare against the remote anyway.

## Single-Device Warning

**This setup uses `rclone sync`, which makes the remote an exact mirror of local.**
Deleted or modified local files will be deleted/overwritten on the remote.

This is safe only when **one device** is the source of truth.
If you add more devices, switch to `rclone copy` or implement proper conflict resolution.

## Versioning

New buckets are created with **object versioning enabled**. This preserves previous versions
of objects on the remote even when overwritten or deleted by `rclone sync`.

On bucket creation, the script:
1. Creates the bucket with `rclone mkdir`
2. Enables versioning with `rclone backend versioning`
3. Applies a native Hetzner lifecycle policy (90-day noncurrent versions, 7-day
   multipart abort, expired delete markers). Current objects are never expired.

This means previous versions are recoverable even under the current single-device override model.
When multi-device push/pull is implemented, versioning will be used for conflict resolution.

### How versioning cost works

`rclone sync` only uploads files that have changed (by size/modtime). Unchanged files are
skipped entirely — no new version is created. Hetzner bills **all versions** toward
storage (and a 64 kB minimum per object), so old versions are expired server-side
after 90 days.

## Version Lifecycle

`lifecycle_bucket.sh` (weekly timer) re-applies the native lifecycle policy and
cleans incomplete multipart uploads. It does **not** expire current objects.

**Default noncurrent retention: 90 days.** Override with `-r <days>`.

Hetzner's own example lifecycle includes `Expiration.Days` on current objects.
We do not use that — it would delete the live backup.

### Systemd timer

```bash
# Enable the weekly lifecycle timer
systemctl --user enable --now bucket-lifecycle.timer

# Check timer status
systemctl --user status bucket-lifecycle.timer

# Run manually
systemctl --user start bucket-lifecycle.service

# View logs
journalctl --user -u bucket-lifecycle.service
```

## Pull Behavior

Pull mirrors remote -> local for **local buckets only** (dirs under `~/bucket/`).

Preflight rule (safe-practical):
- If local has changes vs remote, pull is blocked to avoid overwrites.
- Remote-only changes are allowed and will be pulled.

Empty directories are preserved by syncing directory markers
(`.statbook-dir` files in every directory).

### Systemd pull at login

```bash
# Enable pull at login
systemctl --user enable --now bucket-pull.timer

# Run manually
systemctl --user start bucket-pull.service

# View logs
journalctl --user -u bucket-pull.service
```

### Systemd push schedule

Push is **hourly** (not every 10 minutes). Missed hours while the machine is asleep are not caught up; lock/sleep already push on the way out.

```bash
# Enable hourly push
systemctl --user enable --now bucket-push.timer

# Run manually
systemctl --user start bucket-push.service

# View logs
journalctl --user -u bucket-push.service
```

## Schedule

| Job | Cadence |
|---|---|
| Push (timer) | Hourly while the session is up; no catch-up after sleep |
| Push (hypridle) | Before lock (20 min idle) and before sleep |
| Pull (timer) | Once at login |
| Pull (hypridle) | After resume from sleep |
| Lifecycle | Weekly |

Push and pull use a shared lock (`/tmp/bucket-sync.lock`) so they never overlap.

## Lock/Sleep Integration

Hypridle runs `bucket-push.service` before lock and sleep.
This ensures a push completes before the session locks or suspends.

## Pricing notes (Hetzner)

Aligned with [Hetzner's billing](https://docs.hetzner.com/storage/object-storage/overview/#pricing)
and [workload FAQ](https://docs.hetzner.com/storage/object-storage/faq/general/#which-use-cases-and-workloads-are-a-good-fit-for-object-storage):

- This is a backup / write-once workload (good fit). Push is **ingress** (free).
  Pull is **egress** (counts against the ~1 TB/month included traffic).
- S3 PUT/GET/DELETE themselves are free; listing an idle tree is still load,
  so unchanged buckets skip rclone.
- Minimum billable object size is **64 kB**. Directory markers are only created
  for **empty** dirs. After the first seed, remove leftover `.statbook-dir`
  files from non-empty dirs (`find ~/bucket -name .statbook-dir -delete`) and
  push once so they disappear from the remote.
- Multipart upload kicks in at **100 MB** (Hetzner recommendation).
- Native lifecycle expires old versions and aborted multipart parts so they
  stop accruing storage.

~1.7 GB of current data sits well under the ~1 TB included storage in the
$7.99/mo base price, as long as version history and tiny objects stay in check.

## Filters

The `filters/` directory exists for future use. Currently, all files are pushed without filtering.

## Prerequisites

- `rclone` with `hetzner:` S3 remote configured (`rclone listremotes` to verify)
- `python3` (used by lifecycle script to parse version timestamps from JSON)
