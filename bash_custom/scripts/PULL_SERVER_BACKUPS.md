## README: Postgres (Docker-per-service) + Borg DR Backups (Basebackup + WAL) + System Settings Backups

This documents a repeatable setup to get **daily physical backups + WAL for PITR**, with **Borg encryption** on both the **server** and your **dev machine**, and **pull-based transfer** to your dev machine for inclusion in your existing `~/.bash_custom/scripts/borg-backup.sh` allowlist.

### Design summary

- **[SERVER | Ubuntu]** generates backups (base backups + WAL archives) for **all Postgres containers** listed in a script. It then Borg-archives the produced artifacts to:
    
    1. **server local backup disk** at `/mnt/backup/borg`
        
    2. **server external disk** at `/media/usb/borg` (32GB; includes contingencies)
        
- **[DEV MACHINE]** pulls the server’s backup artifacts (rsync over SSH) into `/mnt/upload/<server>/...` and **adds that directory** to your existing Borg allowlist.
    

---

# 0) Conventions used below

- **[SERVER]** = Ubuntu server running dockerized microservices
    
- **[DEV]** = your dev machine (Omarchy/Arch) with existing Borg system
    
- **Mount points (fixed):**
    
    - **Server local backup disk**: `/mnt/backup`
        
    - **Server primary Borg repo**: `/mnt/backup/borg`
        
    - **Server external drive**: `/media/usb` (small 32GB drive)
        
    - **Server external Borg repo**: `/media/usb/borg`
        
    - **Dev primary Borg repo**: `/mnt/backup/borg` (confirmed)
        
    - **Dev pull destination for server PG backups**: `/mnt/upload/<server_name>/`
        

---

# 1) [SERVER] Install packages

```bash
sudo apt update
sudo apt install -y borgbackup postgresql-client rsync
```

---

# 2) [SERVER] Prepare directories (root-owned, locked down)

### 2.1 Create artifact directories (raw pg backup artifacts)

These are the raw outputs from `pg_basebackup` and WAL archiving. Keep them on the mounted backup disk.

```bash
sudo mkdir -p /mnt/backup/postgres/{basebackups,wal}
sudo chown -R root:root /mnt/backup/postgres
sudo chmod -R 750 /mnt/backup/postgres
```

### 2.2 Create Borg repos (encrypted) on server disks

> These repos store only the **raw artifacts**

```bash
sudo mkdir -p /mnt/backup/borg
sudo borg init --encryption=repokey-blake2 /mnt/backup/borg
```

External repo (only when mounted):

```bash
sudo mkdir -p /media/usb/borg
sudo borg init --encryption=repokey-blake2 /media/usb/borg
```

### 2.3 Export Borg keys (~={yellow} ⚠ mandatory =~)

```bash
sudo borg key export /mnt/backup/borg /root/borg-key-server-primary.txt
# If/when external is initialized:
sudo borg key export /media/usb/borg /root/borg-key-server-external.txt
```

**Store these off-disk** (same rule as your dev machine).

---

# 3) [SERVER] PostgreSQL container prerequisites (replication role + pg_hba)

You have multiple Postgres containers (official image). The host runs backup tools.

## 3.1 Decide how host reaches each container

Recommended: each container exposes Postgres on a unique port bound to **localhost** on the server, e.g.:

- service_a DB: `127.0.0.1:5433`
    
- service_b DB: `127.0.0.1:5434`
    
- service_c DB: `127.0.0.1:5435`
    

## 3.2 Create a replication role in each Postgres container

For each container, run:
**~={yellow} ⚠ CAUTION =~ replace `REPLACE_WITH_STRONG_SECRET`**

```bash
# Example: container name "service_a_pg"
docker exec -i service_a_pg psql -U postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'repl_backup') THEN
    CREATE ROLE repl_backup WITH LOGIN REPLICATION PASSWORD 'REPLACE_WITH_STRONG_SECRET';
  END IF;
END $$;
SQL
```

you can confirm the role exists with:
```SQL
SELECT rolname
FROM pg_roles
WHERE rolname = 'repl_backup';
```

## 3.3 Ensure pg_hba allows replication from the host

Inside each container, append a rule allowing replication connections from the server host.  
If the container sees the host as the docker bridge gateway, it’s often something like `172.190.6.0/24` (verify in your environment).

Example (inside container `pg_hba.conf`), replace the file with:
* be sure to read what you're pasting; make a backup first with
	**[IMPORTANT] Copy out-of-tree:**
	`/root/config_backups/pg_hba.conf.$(date -Is)`
	otherwise, pgsql will pickup the backup file and try to use it (and error)
* check out the hardening at the end to configure further restrictions

**Official Postgres Docker image:** `/var/lib/postgresql/data/pg_hba.conf`

> In Docker, `/var/lib/postgresql/data` is usually a **volume mount**.

**~={yellow} ⚠ CAUTION =~ replace `[REPLACE_WITH_DOCKER_SUBNET_IP]`


```
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# ------------------------------------------------------------------
# Local access (UNCHANGED – passwordless local access)
# ------------------------------------------------------------------

# "local" is for Unix domain socket connections only
local   all             all                                     trust

# IPv4 local connections:
host    all             all             127.0.0.1/32            trust

# IPv6 local connections:
host    all             all             ::1/128                 trust

# ------------------------------------------------------------------
# Local replication (UNCHANGED – passwordless local replication)
# ------------------------------------------------------------------

local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust

# ------------------------------------------------------------------
# Remote replication (HARDENED)
# ------------------------------------------------------------------
# Only the repl_backup user may perform replication,
# and only from the Docker Compose network subnet.
# All other replication attempts are explicitly rejected.

# Allow replication ONLY for repl_backup from compose subnet
# 
host    replication     repl_backup     [REPLACE_WITH_DOCKER_SUBNET_IP]          scram-sha-256

# Reject all other replication attempts (must be above catch-all)
host    replication     all             0.0.0.0/0               reject
host    replication     all             ::0/0                   reject

# ------------------------------------------------------------------
# General access (UNCHANGED)
# ------------------------------------------------------------------
# Catch-all: any database, any user, any address must authenticate
# using SCRAM-SHA-256 (applies to app traffic and dev access)

host    all             all             all                     scram-sha-256

# ------------------------------------------------------------------
# OPTIONAL: Developer access (COMMENTED OUT)
# ------------------------------------------------------------------
# These lines are NOT active.
# Uncomment ONLY the ones that match how developers connect.
# All use SCRAM-SHA-256 and are safe if CIDRs are correct.
#
# IMPORTANT:
# - These rules must stay BELOW the replication rules above.
# - They do NOT weaken replication hardening.
# - Prefer the smallest CIDR possible.

# A) Developers on office/home LAN (example)
# host  all  all  192.168.1.0/24        scram-sha-256

# B) Developers on wider private LAN (example)
# host  all  all  192.168.0.0/16        scram-sha-256

# C) Developers on VPN subnet (example)
# host  all  all  10.8.0.0/24           scram-sha-256

# D) Single developer machine (tightest; repeat per dev)
# host  all  all  203.0.113.42/32       scram-sha-256
```

Then reload Postgres inside the container (example):

```bash
docker exec service_a_pg psql -U postgres -c "SELECT pg_reload_conf();"
```

> If you later want your **dev machine** to connect directly for basebackups (not recommended here), you must also allow your dev machine IP in `pg_hba.conf`. Current plan does NOT require that.

---

# 4) [SERVER] Create the “backup all services” script (root-only)

**Location (protected):** `/usr/local/sbin/pg_backup_all.sh`  
**Permissions:** root-only (recommended)

**~={yellow} ⚠ CAUTION =~ add your `SERVICES`

```bash
sudo tee /usr/local/sbin/pg_backup_all.sh >/dev/null <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# Simple logger helpers
# --------------------------
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log_info() { echo "[$(ts)] [INFO] $*"; }
log_warn() { echo "[$(ts)] [WARN] $*" >&2; }
log_ok()   { echo "[$(ts)] [ OK ] $*"; }
log_err()  { echo "[$(ts)] [ERR ] $*" >&2; }

# --------------------------
# Configuration
# --------------------------
SERVER_NAME="${SERVER_NAME:-server}"
DEST_ROOT="/mnt/backup/postgres"                 # raw artifacts stored on mounted disk
BASE_DIR="$DEST_ROOT/basebackups"
WAL_DIR="$DEST_ROOT/wal"

# Replication role shared across containers (same password OK for now)
REPL_USER="repl_backup"
REPL_PASS_FILE="/etc/pg_backup/repl_password"    # root-readable only

# How many days of raw artifacts to keep on server local disk
# Keep this small because Borg holds the long-term copies.
KEEP_RAW_DAYS="${KEEP_RAW_DAYS:-3}"

# Service list:
# Prefer "name:host:port"
# Host should usually be 127.0.0.1 and port the published container port on the server.
# Add/remove services here only.
SERVICES=(
# TODO: Add your SERVICES in here
  # "service_a:127.0.0.1:5433"
  # "service_b:127.0.0.1:5434"
  # "service_c:127.0.0.1:5435"
)

# NOTE: WAL pull frequency:
# - This script is scheduled daily by systemd timer (see below).
# - If you later increase WAL granularity (e.g., hourly), you must:
#   1) Adjust systemd timer schedule(s)
#   2) Ensure WAL archiving is configured for each DB/container (archive_mode on).
#   3) Consider increasing KEEP_RAW_DAYS or pulling more frequently to dev machine.

# --------------------------
# Guards
# --------------------------
if [[ "$EUID" -ne 0 ]]; then
  log_err "Must run as root"
  exit 1
fi

if [[ ! -d /mnt/backup ]]; then
  log_err "/mnt/backup not mounted; aborting"
  exit 1
fi

if [[ ! -f "$REPL_PASS_FILE" ]]; then
  log_err "Replication password file missing: $REPL_PASS_FILE"
  exit 1
fi

REPL_PASS="$(<"$REPL_PASS_FILE")"
if [[ -z "$REPL_PASS" ]]; then
  log_err "Replication password file is empty: $REPL_PASS_FILE"
  exit 1
fi

mkdir -p "$BASE_DIR" "$WAL_DIR"
chmod 750 "$DEST_ROOT" "$BASE_DIR" "$WAL_DIR"

# --------------------------
# Backup function per service
# --------------------------
backup_one() {
  local name="$1"
  local host="$2"
  local port="$3"

  local stamp
  stamp="$(ts | tr ':' '_')"  # filesystem-friendly
  local tmp_dir="$BASE_DIR/.tmp_${name}_basebackup"
  local final_dir="$BASE_DIR/${name}_basebackup_${stamp}"

  log_info "[$name] Starting basebackup from ${host}:${port}"

  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
  chmod 750 "$tmp_dir"

  # Use PGPASSWORD only for this invocation (avoid global env leakage)
  # -X stream ensures the base backup includes required WAL without relying on archive_command.
  # -c fast gives a quicker checkpoint, typically fine for small DBs.
  if ! PGPASSWORD="$REPL_PASS" pg_basebackup \
      -h "$host" \
      -p "$port" \
      -U "$REPL_USER" \
      -D "$tmp_dir" \
      -c fast \
      -X stream \
      -P; then
    log_err "[$name] pg_basebackup failed; leaving tmp dir for inspection: $tmp_dir"
    return 1
  fi

  # Atomic finalize: rename only after success.
  mv "$tmp_dir" "$final_dir"
  chmod -R 750 "$final_dir"
  log_ok "[$name] Basebackup complete: $final_dir"
}

# --------------------------
# Main
# --------------------------
log_info "Starting daily Postgres backups for ${#SERVICES[@]} services"

fail_count=0
for spec in "${SERVICES[@]}"; do
  IFS=':' read -r name host port <<<"$spec"
  if [[ -z "$name" || -z "$host" || -z "$port" ]]; then
    log_warn "Skipping invalid spec: $spec"
    continue
  fi

  if ! backup_one "$name" "$host" "$port"; then
    fail_count=$((fail_count + 1))
  fi
done

# Prune raw artifacts on server local disk (short retention)
log_info "Pruning raw basebackups older than ${KEEP_RAW_DAYS} days in $BASE_DIR"
find "$BASE_DIR" -maxdepth 1 -type d -name "*_basebackup_*" -mtime +"$KEEP_RAW_DAYS" -print -exec rm -rf {} \; || true

# NOTE about WAL:
# This guide assumes each Postgres container is configured to archive WAL to a host-visible directory
# (or that WAL is captured via -X stream in basebackup). If you implement archive_command to a host path,
# place per-service WAL under: $WAL_DIR/<service>/ and prune similarly.

if [[ "$fail_count" -gt 0 ]]; then
  log_warn "Completed with failures: $fail_count service(s) failed"
  exit 1
fi

log_ok "All service basebackups completed successfully"
BASH

sudo chmod 750 /usr/local/sbin/pg_backup_all.sh
sudo chown root:root /usr/local/sbin/pg_backup_all.sh
```

## 4.1 Store the replication password securely (root-only)

```bash
sudo mkdir -p /etc/pg_backup
sudo chmod 750 /etc/pg_backup
sudo chown root:root /etc/pg_backup

# Put the repl_backup password here:
sudo tee /etc/pg_backup/repl_password >/dev/null <<'EOF'
REPLACE_WITH_STRONG_SECRET
EOF

sudo chmod 640 /etc/pg_backup/repl_password
sudo chown root:root /etc/pg_backup/repl_password
```

---

# 5) [SERVER] Borg “archive the raw artifacts” script (with external-drive contingency)

**Location:** `/usr/local/sbin/borg_pg_artifacts.sh` (root-only)  
This creates a Borg archive from `/mnt/backup/postgres` into:

- primary repo: `/mnt/backup/borg`
    
- external repo: `/media/usb/borg` (if mounted)
    

It includes contingencies for the **32GB external drive**:

- checks free space
    
- attempts archive
    
- if it fails due to space, prunes oldest repeatedly and retries
    
- logs warnings each iteration
    
- does not require reconfig when you swap to a larger external drive (same mount path)
    

```bash
sudo tee /usr/local/sbin/borg_pg_artifacts.sh >/dev/null <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log_info() { echo "[$(ts)] [INFO] $*"; }
log_warn() { echo "[$(ts)] [WARN] $*" >&2; }
log_ok()   { echo "[$(ts)] [ OK ] $*"; }
log_err()  { echo "[$(ts)] [ERR ] $*" >&2; }

PRIMARY_REPO="/mnt/backup/borg"
EXTERNAL_MOUNT="/media/usb"
EXTERNAL_REPO="$EXTERNAL_MOUNT/borg"

# What we Borg on the server (raw pg artifacts)
PG_ARTIFACTS_DIR="/mnt/backup/postgres"

# Retention for primary repo (server-side Borg). Keep modest; dev machine Borg will keep longer.
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"

# External drive free space warning threshold (bytes).
# With a small 32GB drive, warn early but still attempt backup.
EXTERNAL_WARN_FREE_BYTES="${EXTERNAL_WARN_FREE_BYTES:-2147483648}" # 2GiB

# If external is full, we'll prune oldest archives until create succeeds or nothing left.
MAX_EXTERNAL_PRUNE_ITERS="${MAX_EXTERNAL_PRUNE_ITERS:-25}"

if [[ "$EUID" -ne 0 ]]; then
  log_err "Must run as root"
  exit 1
fi

if [[ ! -d "$PRIMARY_REPO" ]]; then
  log_err "Primary repo missing: $PRIMARY_REPO"
  exit 1
fi

if [[ ! -d "$PG_ARTIFACTS_DIR" ]]; then
  log_err "Artifacts dir missing: $PG_ARTIFACTS_DIR"
  exit 1
fi

archive="pg-artifacts-$(date -Is)"

run_borg() {
  local desc="$1"; shift
  local stderr_file
  stderr_file="$(mktemp)"
  log_info "$desc"
  if ! "$@" >/dev/null 2>"$stderr_file"; then
    local err
    err="$(<"$stderr_file")"
    rm -f "$stderr_file"
    log_err "$desc failed"
    [[ -n "$err" ]] && log_err "$err"
    return 1
  fi
  rm -f "$stderr_file"
  log_ok "$desc"
}

# -------------------------
# Primary repo: create + prune + check
# -------------------------
run_borg "Creating primary archive: $archive" \
  borg create --stats \
  "$PRIMARY_REPO::$archive" \
  "$PG_ARTIFACTS_DIR"

run_borg "Pruning primary repo" \
  borg prune --list "$PRIMARY_REPO" \
  --keep-daily="$KEEP_DAILY" \
  --keep-weekly="$KEEP_WEEKLY" \
  --keep-monthly="$KEEP_MONTHLY"

run_borg "Checking primary repo" \
  borg check "$PRIMARY_REPO"

log_ok "Primary pg-artifacts backup complete"

# -------------------------
# External repo: best-effort with small-drive contingency
# -------------------------
if mountpoint -q "$EXTERNAL_MOUNT" && [[ -d "$EXTERNAL_REPO" ]]; then
  free_bytes="$(df -PB1 "$EXTERNAL_MOUNT" | awk 'NR==2 {print $4}')"
  if [[ "${free_bytes:-0}" -lt "$EXTERNAL_WARN_FREE_BYTES" ]]; then
    log_warn "External drive low free space: ${free_bytes} bytes free at $EXTERNAL_MOUNT"
  fi

  # Attempt archive; if it fails due to space, prune and retry.
  iter=0
  while true; do
    iter=$((iter + 1))

    if borg create --stats "$EXTERNAL_REPO::$archive" "$PG_ARTIFACTS_DIR" >/dev/null 2>&1; then
      log_ok "External archive created: $archive"
      break
    fi

    log_warn "External archive failed (likely no space). Iteration $iter/${MAX_EXTERNAL_PRUNE_ITERS}."

    if [[ "$iter" -gt "$MAX_EXTERNAL_PRUNE_ITERS" ]]; then
      log_warn "Giving up on external archive after $MAX_EXTERNAL_PRUNE_ITERS attempts; continuing."
      break
    fi

    # Prune oldest by tightening retention first; if still full, delete oldest archive explicitly.
    # Strategy:
    # 1) Try prune with normal policy (may free space).
    # 2) If still failing, delete the single oldest archive.
    borg prune --list "$EXTERNAL_REPO" \
      --keep-daily="$KEEP_DAILY" \
      --keep-weekly="$KEEP_WEEKLY" \
      --keep-monthly="$KEEP_MONTHLY" >/dev/null 2>&1 || true

    # Delete oldest archive if needed (hard guarantee to free space gradually).
    oldest="$(borg list "$EXTERNAL_REPO" --format '{archive}{NL}' 2>/dev/null | head -n 1 || true)"
    if [[ -n "$oldest" ]]; then
      log_warn "Deleting oldest external archive to free space: $oldest"
      borg delete "$EXTERNAL_REPO::$oldest" >/dev/null 2>&1 || true
      borg compact "$EXTERNAL_REPO" >/dev/null 2>&1 || true
    else
      log_warn "No external archives left to delete; continuing without external backup."
      break
    fi
  done

  # Best-effort external check
  borg check "$EXTERNAL_REPO" >/dev/null 2>&1 || log_warn "External borg check failed; continuing."

else
  log_warn "External drive not mounted or repo missing; skipping external backup."
fi

log_ok "borg_pg_artifacts complete: $archive"
BASH

sudo chmod 750 /usr/local/sbin/borg_pg_artifacts.sh
sudo chown root:root /usr/local/sbin/borg_pg_artifacts.sh
```

---

# 6) [SERVER] systemd service + timer (daily, persistent)

#### 6.01 Create a root-only Borg passphrase file

**~={yellow} ⚠ CAUTION =~ add your `REPLACE_WITH_YOUR_BORG_REPO_PASSPHRASE`

```bash
sudo mkdir -p /etc/borg

sudo chmod 750 /etc/borg

sudo chown root:root /etc/borg

  

sudo tee /etc/borg/pg-borg.env >/dev/null <<'EOF'

# Used by borg_pg_artifacts.sh via systemd.

# Keep this file root-only.

BORG_PASSPHRASE=REPLACE_WITH_YOUR_BORG_REPO_PASSPHRASE

EOF

  

sudo chmod 640 /etc/borg/pg-borg.env

sudo chown root:root /etc/borg/pg-borg.env
```

> Use the same passphrase you used when you did `borg init --encryption=repokey-blake2 /mnt/backup/borg`.


## 6.1 Create a single daily “runner” that:

1. runs `pg_backup_all.sh`
    
2. then runs `borg_pg_artifacts.sh`
    

### `/etc/systemd/system/pg-backup-all.service`

```bash
sudo tee /etc/systemd/system/pg-backup-all.service >/dev/null <<'UNIT'
[Unit]
Description=Daily Postgres basebackups for all docker services + Borg archive
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
EnvironmentFile=/etc/borg/pg-borg.env
ExecStart=/usr/local/sbin/pg_backup_all.sh
ExecStart=/usr/local/sbin/borg_pg_artifacts.sh
UNIT
```

### `/etc/systemd/system/pg-backup-all.timer`

```bash
sudo tee /etc/systemd/system/pg-backup-all.timer >/dev/null <<'UNIT'
[Unit]
Description=Daily Postgres backups (persistent)

[Timer]
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pg-backup-all.timer
```

Check:

```bash
systemctl list-timers pg-backup-all.timer
systemctl status pg-backup-all.service
journalctl -u pg-backup-all.service --since yesterday
```

---

# 6.A) “NOPASSWD but constrained” for `rsync` only

there is a problem with the pull implementation; the *pull* from the [dev] machine requires sudo to access the directory `/mnt/backup/*` however, it is redundant to (1) provide passwordless sudo or (2) have a *push* implementation where the server can push unencrypted files to any random IP. So, the compromise is as follows:
>
> **we'll use `jared` as the [server] user here. change the user when implementing**
>

This does **not** give `jared` general passwordless sudo; it only allows `rsync` with a fixed argv pattern.

## A1) [SERVER] Create a sudoers drop-in

Run on **SERVER**:
```bash
sudo visudo -f /etc/sudoers.d/pg_rsync_pull
```

Paste (adjust paths if needed):
```sudodoers
Defaults:jared !requiretty

Cmnd_Alias PG_RSYNC = /usr/bin/rsync

# Allow rsync only (non-interactive), nothing else.

jared ALL=(root) NOPASSWD: PG_RSYNC
```

Lock permissions:
```bash
sudo chmod 440 /etc/sudoers.d/pg_rsync_pull
```

## A2) [DEV] Use rsync with remote sudo rsync

In your dev script:
```bash
rsync -av --delete \

  -e "${RSYNC_RSH}" \

  --rsync-path="sudo /usr/bin/rsync" \

  "${SERVER_USER}@${SERVER_HOST}:${REMOTE_BASE_DIR}" \

  "${LOCAL_DIR}/"
```


### Why this matches your security intent

- non-root users cannot `cat` or `ls` `/mnt/backup/postgres` directly
    
- non-root users can only run `rsync` as root, which is purpose-built for controlled copying
    
- No interactive prompt → automation-safe
    

**Hardening note:** A fully “argv-locked” sudoers rule is possible but brittle with `rsync` (it passes dynamic flags/paths). In practice, restricting to `/usr/bin/rsync` is the standard compromise.

---
# 7) [DEV] Pull server PG backups to dev machine (SSH pull)

## 7.1 Create pull destination



***The files being uploaded are ~={red} 🔥 NOT encrypted =~***, so we have to lock everything down pretty well:
 
```bash
sudo mkdir -p /mnt/upload
sudo chown root:root /mnt/upload
sudo chmod 700 /mnt/upload
```

Every time there is a new server that is added to the list (for example `main-server`):
~={yellow}⚠ CAUTION=~, replace `main-server` 

```bash
sudo mkdir -p /mnt/upload/main-server
sudo chown root:root /mnt/upload/main-server
sudo chmod 700 /mnt/upload/main-server
```

## 7.2 Create an SSH key for [DEV] root user

> make a key on the [dev] machine:
```bash
sudo mkdir -p /etc/backup/ssh

sudo chmod 700 /etc/backup/ssh

# NOTE: if you change the name of this file, remember to change it in the script in secion 7.3
sudo ssh-keygen -t ed25519 -N "" -f /etc/backup/ssh/backup_servers_ed25519

sudo cat /etc/backup/ssh/backup_servers_ed25519.pub
ssh-ed25519 YOUR_KEY root@omarchy

```
> paste the key in the bottom of `path/to/your/.ssh/authorized_keys` (likely `~/.ssh/authorized_keys`)

```bash
echo "YOUR_KEY" >> path/to/your/.ssh/authorized_keys
# OR
vim path/to/your/.ssh/authorized_keys # ... and paste it in
```
## 7.3 Create pull script (keep in your dev machine repo/scripts area)

**Location:** `~/.bash_custom/scripts/pull-server-pg-backups.sh`  
(Your preference: don’t move your dev scripts.)

```bash
cat > ~/.bash_custom/scripts/pull-server-backups.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# check if the local machine has rsync
command -v rsync >/dev/null 2>&1 || {
  echo "ERROR: rsync not installed. Install with: sudo pacman -S --needed rsync"
  exit 127
}

DEBUG="${DEBUG:-0}"

if [[ "$DEBUG" == "1" ]]; then
  set -x
fi

# Self-elevate (preserve DEBUG across sudo)
# this is required becuase the /mnt/upload folder is locked down to root
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo --preserve-env=DEBUG -- "$0" "$@"
fi

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*"; }

# --------------------------
# CONFIG (DEV MACHINE)
# --------------------------

# Dict-style configuration
# All keys MUST match across arrays
declare -A SERVER_HOSTS=(
  # ["main-server"]="1.2.3.4"
  # ["prod_server"]="10.0.0.5"
)

declare -A SERVER_USERS=(
  # ["main-server"]="main-user"
  # ["prod_server"]="backupuser"
)

REMOTE_PG_DIR="/mnt/backup/postgres"
# TODO: Implement configuration settings backups
REMOTE_CONFIG_DIR="/mnt/backup/config"
LOCAL_BASE_DIR="/mnt/upload"

[[ "$REMOTE_PG_DIR" != */ ]] || {
  echo "REMOTE_PG_DIR must NOT end with / (directory-itself semantics required)"
  exit 1
}

SSH_PORT=2222
SSH_KEY="/etc/backup/ssh/backup_servers_ed25519"

RSYNC_RSH="ssh -p ${SSH_PORT} -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes"

# --------------------------
# RUN
# --------------------------

for SERVER_NAME in "${!SERVER_HOSTS[@]}"; do
  SERVER_HOST="${SERVER_HOSTS[$SERVER_NAME]}"
  SERVER_USER="${SERVER_USERS[$SERVER_NAME]}"

  if [[ -z "$SERVER_USER" ]]; then
    echo "Missing SERVER_USER for ${SERVER_NAME}"
    exit 1
  fi

  LOCAL_DIR="${LOCAL_BASE_DIR}/${SERVER_NAME}/"
  # Safety: ensure trailing slash semantics
[[ "$LOCAL_DIR" == */ ]] || {
  echo "LOCAL_DIR must end with /"
  exit 1
}

  log "Pulling PG artifacts from ${SERVER_HOST}:${REMOTE_PG_DIR}"
  log "→ Local destination: ${LOCAL_DIR}"

  sudo mkdir -p "$LOCAL_DIR"
  sudo chmod 750 "$LOCAL_DIR"

SRC="${SERVER_USER}@${SERVER_HOST}:${REMOTE_PG_DIR}"

rsync -av --delete \
  -e "${RSYNC_RSH}" \
  --rsync-path="sudo rsync" \
  "${SRC}" \
  "${LOCAL_DIR}"

  log "Pull complete for ${SERVER_NAME}"
done

log "All server pulls completed successfully"

chmod 750 ~/.bash_custom/scripts/pull-server-backups.sh
```

---

# 8) [DEV] systemd service + timer for the pull (daily, persistent)

### `/etc/systemd/system/pull-server-pg-backups.service`

```bash
sudo tee /etc/systemd/system/pull-server-backups.service >/dev/null <<'UNIT'
[Unit]
Description=Pull server backup artifacts to dev machine
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/home/jaime/.bash_custom/scripts/pull-server-backups.sh
UNIT
```

### `/etc/systemd/system/pull-server-pg-backups.timer`

Schedule this **after** the server’s backup time (server runs 02:00). Example: 03:00.

```bash
sudo tee /etc/systemd/system/pull-server-backups.timer >/dev/null <<'UNIT'
[Unit]
Description=Daily pull of server artifacts (persistent)

[Timer]
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pull-server-backups.timer
```

Logs:

```bash
systemctl list-timers pull-server-backups.timer
journalctl -u pull-server-backups.service --since yesterday
```

Handy for testing:

```bash
# Start a one-off cmd
systemctl start pull-server-backups.service
# watch it run
journalctl -u pull-server-backups.service --since yesterday
```

---

# 9) [DEV] Add the pulled directory to your existing `borg-backup.sh` allowlist

Your `borg-backup.sh` uses an explicit `keep_paths=(...)` allowlist. Add **one new entry** for the pulled server backups directory.

### Change in `~/.bash_custom/scripts/borg-backup.sh`

Add:

```bash
"/mnt/backup/postgres"
```

…somewhere inside `keep_paths=( ...)`.

Example placement near other top-level dirs:

```bash
keep_paths=(
  "/etc"
  "/mnt/backup/postgres"   # server PG backups pulled to dev machine
  "$home_dir/Work"
  ...
)
```

No other changes to your dev Borg script are required. (It already creates/prunes/checks primary and optional external repos.)

---

# 10) Changing WAL pull frequency later (documented procedure)

## If you want WAL pulls more frequently than daily:

You must change **both**:

1. **[DEV]** `pull-server-pg-backups.timer` schedule (e.g., hourly)
    
2. **[SERVER]** ensure WAL retention is sufficient (increase raw retention / stop aggressive pruning of WAL)
    

### Step guide

- **[DEV]** edit `/etc/systemd/system/pull-server-pg-backups.timer`:
    
    - hourly example:
        
        ```
        OnCalendar=hourly
        ```
        
    - then:
        
        ```bash
        sudo systemctl daemon-reload
        sudo systemctl restart pull-server-pg-backups.timer
        ```
        
- **[SERVER]** increase retention guardrails:
    
    - in `/usr/local/sbin/pg_backup_all.sh`, bump:
        
        ```
        KEEP_RAW_DAYS=3
        ```
        
        to something larger if server disk allows (e.g., 7), and ensure your WAL directories (if used) are pruned consistently.
        

---

# 11) Script/directory protection rules (enforced by this setup)

- **[SERVER] scripts** live under `/usr/local/sbin` and are `root:root` `750`
    
- **[SERVER] secrets** live under `/etc/pg_backup` `root:root` `750`, password file `640`
    
- **[DEV] scripts** remain in your existing `~/.bash_custom/scripts` area (your preference)
    
- **[DEV] systemd units** are in `/etc/systemd/system` and run as root (matches your current Borg approach)
    

---

# 12) Operational checks (both machines)

## [SERVER]

```bash
systemctl list-timers pg-backup-all.timer
journalctl -u pg-backup-all.service --since today
sudo borg list /mnt/backup/borg | tail
```

## [DEV]

```bash
systemctl list-timers pull-server-pg-backups.timer
journalctl -u pull-server-pg-backups.service --since today
sudo borg list /mnt/backup/borg | tail
```

---

# 13) Required edits you must make before enabling

## [SERVER]

- Fill `SERVICES=(...)` in `/usr/local/sbin/pg_backup_all.sh` with actual services/ports.
    
- Set `/etc/pg_backup/repl_password` to the real replication password.
    
- Ensure each container exposes a port to the host and `pg_hba.conf` allows replication from the host.
    

## [DEV]

- Set `SERVER_USER`, `SERVER_HOST`, `SERVER_NAME` in `~/.bash_custom/scripts/pull-server-pg-backups.sh`.
    
- Add `/mnt/backup/postgres` to `keep_paths` in `~/.bash_custom/scripts/borg-backup.sh`.
    

---

# 14) Commands to run after edits (sanity)

## [SERVER]

```bash
sudo systemctl daemon-reload
sudo systemctl start pg-backup-all.service
sudo journalctl -u pg-backup-all.service -n 200 --no-pager
```

## [DEV]

```bash
sudo systemctl daemon-reload
sudo systemctl start pull-server-pg-backups.service
sudo journalctl -u pull-server-pg-backups.service -n 200 --no-pager
sudo ~/.bash_custom/scripts/borg-backup.sh
```

---
---
# Troubleshooting Quick Reference (Server + External Drive)
---
---


This section documents common failure modes and fast verification steps for the Postgres + Borg backup pipeline.

---

### 1. External drive appears “not mounted”

**Symptom**

- Logs show: `external drive not mounted`
    
- Borg skips `/media/usb`
    

**Checks**

```bash
findmnt -T /media/usb
df -hT /media/usb
```

**Expected**

- Exactly **one** source device (e.g. `/dev/sde1`)
    
- Filesystem type `ext4`
    

**Fix**

- If no output or multiple sources appear:
    
    ```bash
    sudo umount /media/usb
    sudo mount /dev/sde1 /media/usb
    ```
    
- Ensure persistent mount exists in `/etc/fstab` using the correct UUID.
    

---

### 2. “Phantom” or stacked mounts

**Symptom**

- `findmnt` shows more than one device mounted at `/media/usb`
    
- `umount /dev/sdX1` fails with “Invalid argument”
    

**Root cause**

- Stale mount table entry from an automounter or previous USB device.
    

**Fix**

```bash
sudo umount /media/usb
sudo mount -a
findmnt -T /media/usb
```

There must be **one and only one** mount source.

---

### 3. Borg reports “not a valid repository”

**Symptom**

```text
/media/usb/borg is not a valid repository
```

**Checks**

```bash
ls -la /media/usb/borg
```

**Expected**

- Files like `config`, `data/`, `index.*`
    

**Fix**

- If empty or missing:
    
    ```bash
    sudo borg init --encryption=repokey-blake2 /media/usb/borg
    ```
    
- Export the key immediately after:
    
    ```bash
    sudo borg key export /media/usb/borg /root/borg-key-server-external.txt
    ```
    

---

### 4. Borg prompts for passphrase in systemd

**Symptom**

```text
can not acquire a passphrase
BORG_PASSPHRASE is not set
```

**Root cause**

- Borg running non-interactively without an environment source.
    

**Fix**

- Ensure the systemd service references the Borg env file:
    
    ```ini
    EnvironmentFile=/etc/borg/pg-borg.env
    ```
    
- Confirm file permissions are root-only.
    

---

### 5. `pg_basebackup` fails with version mismatch

**Symptom**

```text
pg_basebackup: error: incompatible server version
```

**Fix**

- Install matching client version:
    
    ```bash
    sudo apt install postgresql-client-17
    ```
    
- Call the versioned binary explicitly:
    
    ```bash
    /usr/lib/postgresql/17/bin/pg_basebackup
    ```
    

---

### 6. `pg_basebackup` fails referencing `pg_hba.backup.conf`

**Symptom**

```text
could not open file "./pg_hba.backup.conf": Permission denied
```

**Root cause**

- Backup file accidentally included or referenced by Postgres.
    

**Fix**

- Remove the file from the data directory:
    
    ```bash
    docker exec <pg_container> rm -f /var/lib/postgresql/data/pg_hba.backup.conf
    ```
    
- Reload config:
    
    ```bash
    docker exec <pg_container> psql -U postgres -c "SELECT pg_reload_conf();"
    ```
    

**Policy**

- Back up `pg_hba.conf` outside the data directory or with a non-referenced filename.
    

---

### 7. External drive is full (expected with small disks)

**Behavior**

- Borg logs warnings
    
- Oldest external archives are pruned automatically
    
- Primary repo continues uninterrupted
    

**Verification**

```bash
df -h /media/usb
sudo borg list /media/usb/borg | tail
```

No action required unless the drive is completely unavailable.

---

### 8. Verify everything in one shot

**Manual run**

```bash
sudo systemctl start pg-backup-all.service
sudo journalctl -u pg-backup-all.service -n 200 --no-pager
```

**Expected**

- All service base backups complete
    
- Primary Borg archive created
    
- External Borg attempted (with warnings if space-limited)
    

---

### 9. Key recovery reminder

If the passphrase is lost, recovery requires the exported key:

```bash
borg key import /mnt/backup/borg borg-key-server-primary.txt
borg key import /media/usb/borg borg-key-server-external.txt
```

Without the key export, recovery is impossible.

---

### Operational rule of thumb

If something looks wrong:

1. Check mounts (`findmnt`)
    
2. Check Borg repo validity (`borg list`)
    
3. Check systemd logs
    
4. Never “fix” by deleting data directories blindly
    

---
---
# Service & Timer Health Checks (Operational)
---
---

This section documents how to verify, control, and observe the Postgres backup service and its systemd timer.

All commands are run on the **server** unless noted otherwise.

---

### 1. Check timer status (scheduled execution)

Show the next and last scheduled runs:

```bash
systemctl list-timers pg-backup-all.timer
```

**Expected**

- Timer is **enabled**
    
- `NEXT` is in the future
    
- `LAST` is in the past (after at least one successful run)
    

---

### 2. Check service status (last execution result)

```bash
systemctl status pg-backup-all.service
```

**Interpretation**

- `active (exited)` → last run completed
    
- `failed` → inspect logs immediately
    

---

### 3. View recent logs (post-run)

```bash
journalctl -u pg-backup-all.service -n 200 --no-pager
```

Look for:

- per-service basebackup success lines
    
- Borg archive creation
    
- warnings vs hard errors
    

---

### 4. Watch a run in real time

```bash
journalctl -u pg-backup-all.service -f
```

Use this when manually starting the service or debugging timing issues.

---

### 5. Manually trigger a backup run

This does **not** affect the timer schedule.

```bash
sudo systemctl start pg-backup-all.service
```

Immediately follow with:

```bash
journalctl -u pg-backup-all.service -n 200 --no-pager
```

---

### 6. Stop an in-progress run (if required)

```bash
sudo systemctl stop pg-backup-all.service
```

Use only if:

- disk is filling unexpectedly
    
- external drive behavior needs correction
    

Partial base backups are written to temp directories and will not be promoted as valid.

---

### 7. Reload after configuration or script changes

If any of the following change:

- systemd unit files
    
- backup scripts
    
- environment files (Borg passphrase, etc.)
    

Run:

```bash
sudo systemctl daemon-reload
```

Then restart the timer or service as needed.

---

### 8. Enable / disable the timer

Disable automatic runs (maintenance window):

```bash
sudo systemctl disable --now pg-backup-all.timer
```

Re-enable:

```bash
sudo systemctl enable --now pg-backup-all.timer
```

---

### 9. Verify artifacts exist after a run

**Raw base backups**

```bash
ls -lh /mnt/backup/postgres/basebackups
```

**Primary Borg repo**

```bash
sudo borg list /mnt/backup/borg | tail
```

**External Borg repo (if mounted)**

```bash
sudo borg list /media/usb/borg | tail
```

---

### 10. Check timer/service wiring

Confirm the service runs after filesystem availability:

```bash
systemctl show pg-backup-all.service | grep -E 'After=|Wants='
```

Expected to include:

- `local-fs.target`
    
- `network-online.target`
    

---

### 11. Expected service exit behavior

- Base backup failures are logged per service
    
- Borg still runs if configured via `ExecStartPost`
    
- External-drive failures produce warnings, not hard stops
    
- A non-zero exit status always means **review logs**
    

---

### Operational guideline

If backups look unhealthy:

1. Check the timer (`list-timers`)
    
2. Check the service status
    
3. Read the last 200 log lines
    
4. Verify mounts
    
5. Verify Borg repos
    
6. **Do not delete backup data blindly**
    

This process isolates >95% of real-world failures.

---
---
## Mounting an External Backup Drive via `/etc/fstab` (Automount)

This system uses a **systemd automount** entry in `/etc/fstab` to provide a **stable mount path** for an external backup drive, without blocking boot if the drive is absent.

### Why this approach

- Provides a **stable path** (`/mnt/backup`) for tools like Borg
    
- Avoids boot failures when the drive is unplugged
    
- Mounts the drive **on first access**, not at boot
    
- Uses restrictive mount flags for removable media
    

---

## Step 1: Identify the drive UUID

Plug in the external drive and run:

```bash
sudo blkid
```

Locate the correct partition (e.g. `/dev/sde1`) and copy its `UUID`.

Example output:

```text
/dev/sde1: UUID="52e71a97-d76e-4f58-a182-ec73a59e7fe8" TYPE="ext4"
```

---

## Step 2: Create the mount point

Ensure the target directory exists:

```bash
sudo mkdir -p /mnt/backup
sudo chown root:root /mnt/backup
sudo chmod 755 /mnt/backup
```

---

## Step 3: Add the entry to `/etc/fstab`

Edit `/etc/fstab`:

```bash
sudo nano /etc/fstab
```

Add the following line, replacing the UUID with the correct value:

```fstab
UUID=XXXX-XXXX  /mnt/backup  ext4  nosuid,nodev,nofail,x-systemd.automount  0  2
```

### Option breakdown

- `nosuid`  
    Disables setuid/setgid binaries on the drive
    
- `nodev`  
    Prevents device files from being interpreted
    
- `nofail`  
    Allows the system to boot even if the drive is not present
    
- `x-systemd.automount`  
    Defers mounting until the path is accessed (prevents race conditions)
    

---

## Step 4: Apply and test the configuration

Reload mounts:

```bash
sudo mount -a
```

Verify the automount unit exists:

```bash
systemctl list-units --type=automount | grep mnt-backup
```

Trigger the mount by accessing the directory:

```bash
ls /mnt/backup
```

Verify the drive is now mounted:

```bash
findmnt -T /mnt/backup
```

---

## Expected behavior

- If the drive is **plugged in**:
    
    - `/mnt/backup` mounts automatically on access
        
- If the drive is **unplugged**:
    
    - `/mnt/backup` exists but remains empty
        
    - No boot delays or errors occur
        
- The system never blocks waiting for the drive
    

---

## Important notes

- Do **not** combine this with `udisks/udiskie` for the same device
    
- Use **either** `/etc/fstab` automount **or** user-space hotplug mounting, not both
    
- This method is recommended when a **fixed path is required** for automation
    

---

## Verification checklist

```bash
findmnt -T /mnt/backup
df -h /mnt/backup
```

If both commands behave as expected, the automount configuration is complete.

---
