# Omarchy Backup (Borg)

## Purpose

This backup system exists to reliably preserve **working data and system configuration** on an Omarchy (Arch Linux) system with **minimal operational complexity**.

The design favors:

* recoverability over cleverness
* explicit scope over implicit behavior
* encrypted data at rest
* automated daily execution with manual observability

Backups run automatically via a systemd timer at **2:30 AM daily**. If the system is powered off at that time, the backup runs when the system next starts (persistent timer).

---

## Backup Model

The system uses **BorgBackup** with client-side encryption.

Each backup run:

* creates a new, immutable archive
* stores it in a primary encrypted repository
* names the archive using a timestamp for chronological ordering

Archives in both repositories are retained according to a fixed policy and pruned regularly.

---

## Repositories

### Primary repository

The primary Borg repository is located at:

* `/mnt/backup/borg`

This repository is authoritative.
All backups are created here first.

The primary repository:

* is encrypted with a passphrase
* stores the encryption key internally
* is pruned according to the defined retention policy

The backup drive containing the primary repository **must be mounted at `/mnt/backup`** before any backup run.

---

### External repository (optional mirror)

An optional external Borg repository may exist on a secondary drive.

By default, this repository is expected at:

* `/mnt/ext_backup/borg`

This location may be overridden by environment variables in the backup script.

The external repository:

* receives a **new archive created directly** (same content as primary)
* is **pruned with the same retention policy** as the primary repository
* serves as an offsite/secondary copy

The external repository is treated as a **redundant backup**, not a long-term archival mirror.

---

## What Is Backed Up

Each archive contains **exactly** the following paths (allowlist approach):

### 1. System configuration

* `/etc`

This captures system-level configuration required to reconstruct services, system behavior, and host-specific settings after reinstall. Includes:

* `/etc/systemd/system/` — system-level systemd services and timers (e.g., `borg-backup.service`)

### 2. User directories and config

* `~/Work` — project and work files
* `~/.ssh` — SSH keys and config
* `~/.gnupg` — GPG keys
* `~/.bash_custom` — shell customizations
* `~/.config` — application configuration (**excluding** `~/.config/nvim`), includes:
  * `~/.config/systemd/user/` — user-level systemd services and timers (e.g., `repo-checkin.service`)
* `~/Documents` — personal documents (if the directory exists)

### 3. User data directories

* `~/.local/share/keyrings` — credential storage
* `~/.local/share/fonts` — custom fonts
* `~/.local/share/applications` — custom .desktop files

### 4. Package manifest

* `pkglist.txt`

This file is generated at backup time from:

```bash
pacman -Qqe
```

It is embedded directly into the Borg archive and records all explicitly installed packages.
It is used during recovery to reinstall the system's software set.

---

## What Is Excluded

The backup explicitly excludes:

* cache directories (via Borg's `--exclude-caches` flag)
* `~/.config/nvim` — Neovim configuration (managed separately or regenerated)

The allowlist approach means only the paths listed above are backed up. Everything else in the home directory (downloads, caches, build artifacts, etc.) is implicitly excluded.

---

## Backup Scripts

### Primary backup script (automated)

* `~/.bash_custom/scripts/borg-backup.sh`

This script runs automatically via a **systemd timer** at **2:30 AM daily**. If the system is off at that time, the backup runs when the system next boots (persistent timer).

The script performs the following steps:

1. Verifies that the primary Borg repository exists and is mounted
2. Reads the passphrase (from environment or prompt)
3. Creates a new timestamped archive in the primary repository
4. Embeds the package manifest as `pkglist.txt`
5. Prunes old archives according to the retention policy
6. Runs a fast integrity check on the primary repository
7. If the external drive is mounted, creates an archive there too
8. Prunes and checks the external repository (if used)

Failure or absence of the external drive does **not** cause the backup to fail.

---

### Prune utility (manual only)

* `~/.bash_custom/scripts/borg-prune.sh`

This is a **manual utility** for aggressively reducing repository size. It is **not run automatically**.

Use this script when you need to reclaim disk space by keeping only the most recent archive:

```bash
~/.bash_custom/scripts/borg-prune.sh /mnt/backup/borg
```

**Warning:** This is destructive. It deletes all archives except the latest one and compacts the repository. There is no undo.

---

## Systemd Timer Management

The backup runs via a systemd timer. Use these commands to manage it:

**Check next scheduled run:**

```bash
systemctl list-timers borg-backup.timer
```

**Check last execution status:**

```bash
systemctl status borg-backup.service
```

**View recent logs:**

```bash
journalctl -u borg-backup.service --since yesterday
```

**Watch logs in real-time:**

```bash
journalctl -u borg-backup.service -f
```

**Disable the timer:**

```bash
sudo systemctl stop borg-backup.timer
```

**Re-enable the timer:**

```bash
sudo systemctl start borg-backup.timer
```

**This is handy when trouble shooting and debugging:**
```bash
# run a one-off cmd
sudo systemctl start borg-backup.service && journalctl -u borg-backup.service --since "1 hour ago"
# Then watch it
journalctl -u borg-backup.service -f
```

### Updating the Service

When modifying a systemd service unit (for example, editing
`/etc/systemd/system/borg-backup.service`), systemd does **not**
automatically pick up the changes.

After saving the file, you must reload systemd’s unit definitions:

```bash
sudo systemctl daemon-reload
```

Then apply the changes:

* If the service runs directly:

  ```bash
  sudo systemctl restart borg-backup.service
  ```

* If the service is triggered by a timer:

  ```bash
  sudo systemctl restart borg-backup.timer
  ```

### Notes

* `daemon-reload` is required whenever a unit file is edited.
* `systemctl reload <service>` only works if the unit defines
  `ExecReload=` and **does not** re-read the unit file.
* To verify what systemd is using:

  ```bash
  systemctl cat borg-backup.service
  ```


---

## Backup Requirements

A valid backup run requires:

* the primary backup drive connected
* the drive mounted at `/mnt/backup`
* the Borg repository accessible
* the `BORG_PASSPHRASE` environment variable set (for automated runs)

Each run results in exactly one new archive in the primary repository (and optionally the external repository if mounted).

---

## Retention Policy

Both repositories (primary and external) use the same retention policy:

* 7 daily backups
* 4 weekly backups
* 6 monthly backups

Archives outside this policy are pruned automatically after each backup run.

---

## Inspecting Backups

List archives in the primary repository:

```bash
borg list /mnt/backup/borg
```

List archives in the external repository:

```bash
borg list "/mnt/ext_backup/borg"
```

Inspect the contents of a specific archive:

```bash
borg list /mnt/backup/borg::omarchy-YYYY-MM-DDTHH:MM:SS
```

Confirm the embedded package list exists:

```bash
borg list /mnt/backup/borg::omarchy-YYYY-MM-DDTHH:MM:SS | grep pkglist.txt
```

---

## Restore Model

Restoration assumes:

* a functioning Linux system
* access to the encrypted backup drive
* the Borg passphrase (and preferably a key export)

## 🔑 Recovery Using the Exported Key (Passphrase Lost)

**This is the primary disaster-recovery path.**

If the Borg passphrase is forgotten but the repository key was exported, full recovery is still possible.

#### Restore the key into Borg’s key store

On a fresh system or new machine:

```bash
borg key import /mnt/backup/borg borg-key-omarchy.txt
```

This installs the key into `~/.config/borg/keys/`.

After import, Borg can unlock the repository without the original passphrase.

#### Verify access
```bash
borg list /mnt/backup/borg
```

If this succeeds, the repository is fully accessible.

#### (Recommended) Set a new passphrase

Immediately protect the imported key with a new passphrase:
```bash
borg key change-passphrase /mnt/backup/borg
```

This does not rewrite repository data—only the local key encryption.

---

#### Temporary recovery without importing the key

If you do not want the key persisted on disk:
```bash
BORG_KEY_FILE=borg-key-omarchy.txt borg list /mnt/backup/borg
```

This method:
* uses the key for a single command
* leaves no key material behind
* is suitable for one-off restores or emergency access

### Restore user directories

```bash
cd /
borg extract /mnt/backup/borg::omarchy-YYYY-MM-DDTHH:MM:SS home/<user>
```

This extracts all backed-up paths under `home/<user>` (Work, .ssh, .gnupg, .config, etc.).

### Restore system configuration

```bash
cd /
borg extract /mnt/backup/borg::omarchy-YYYY-MM-DDTHH:MM:SS etc
```

### Restore package list and reinstall software

```bash
borg extract /mnt/backup/borg::omarchy-YYYY-MM-DDTHH:MM:SS pkglist.txt
sudo pacman -S --needed - < pkglist.txt
```

Restores are explicit and file-based. No special tooling beyond Borg is required.

---

## Integrity and Verification

After each backup run:

* a lightweight `borg check` is executed on the primary repository

Occasionally (manually), a full data verification may be run:

```bash
borg check --verify-data /mnt/backup/borg
```

---

Key Management

The repository encryption key must be exported and stored off-disk.

Example:

borg key export /mnt/backup/borg borg-key-omarchy.txt

Key properties:

* The key allows full decryption without the passphrase
* Anyone with the key can read the repository
* Treat it like a private SSH or GPG master key

Storage guidance:

* Keep at least one offline copy (USB, encrypted vault, paper/QR backup)
* Do not store the key next to the repository
* Duplicate the key to two physical locations

Loss conditions:

| Scenario                       | Recoverable |
| ------------------------------ | ----------- |
| Repository lost                | ❌           |
| Key lost, repo intact          | ❌           |
| Passphrase lost, key available | ✅           |
| Key + repo available           | ✅           |

Key export is mandatory for long-term safety.

Expected Recovery Outcome

Given:

* the backup drive
* either the Borg passphrase or the exported encryption key

It is possible to:

* recover all backed-up user directories
* restore /etc system configuration
* reinstall all explicitly installed packages
* rebuild the system to a working state with minimal guesswork

---

## Non-Goals

This backup system does not attempt to:

* snapshot the running OS image
* preserve caches or temporary build artifacts
* back up the entire home directory (uses explicit allowlist instead)
* optimize for minimal storage usage at the expense of clarity

The system is intentionally simple and explicit, with automated daily execution.
