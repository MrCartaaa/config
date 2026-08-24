# cloud-db-backup

On-demand trigger for the **production** DB backup CronJob. Runs the same Job the nightly schedule would: `pg_dump -Fc` + Neo4j dump → Borg → rclone `hetzner:statbook-prod-backups`.

This does **not** dump from the laptop. It creates a cluster Job. Staging is out of scope.

| | |
|---|---|
| Script | `~/.config/bash_custom/scripts/cloud-db-backup.sh` |
| Alias | `cloud-backup` (from `aliases.conf`) |
| Nightly | CronJob `db-backup` in `statbook-cd`, `0 2 * * *` UTC |
| Bucket | `hetzner:statbook-prod-backups` (rclone creates it) |
| Local Borg | `backup` alias — this machine only; different command |

## Requirements

- CronJob + PVC + secret already on the cluster (GitOps `db-backup` Application, Ansible vault `secret/db-backup/production` → ESO `db-backup-secret`)
- **kubectl** (required): `KUBECONFIG` or `~/.config/kube/config`, context `cloud`. API down = error. No automatic SSH fallback.
- **`--ssh`**: opt-in only (control plane `/etc/kubernetes/admin.conf`). Not used unless you pass it.

## Usage

```bash
# Prompt, then run now (Neo4j briefly unavailable during dump)
cloud-backup

# No prompt
cloud-backup --yes

# Opt-in: kubectl on the control plane (not a fallback)
cloud-backup --ssh
cloud-backup --ssh cloud-cicd --yes

# Fire and forget
cloud-backup --yes --no-wait

# Inspect
cloud-backup --status
cloud-backup --logs
cloud-backup --list                 # in-cluster borg list (no ~/bucket copy)
cloud-restore --kind postgres --service api --archive NAME --confirm production
```

### Flags

| Flag | Meaning |
|---|---|
| `--yes` / `--confirm production` | Skip the downtime prompt |
| `--ssh [host]` | Opt-in: kubectl over SSH (default host `cloud-cicd`). Not automatic |
| `--no-wait` | Create the Job and exit |
| `--no-follow` | Wait without streaming logs |
| `--force` | Allow a second Job while one is Active |
| `--dry-run` | Print the create command only |
| `--status` | CronJob + recent Jobs |
| `--logs` | Follow the newest backup Job |
| `--list` | In-cluster `borg list` of the prod bucket (no local copy) |
| `--context NAME` | kubectl context (default `cloud` if it exists) |

Leave overlapping backups alone unless you pass `--force`. The Neo4j dump scales each graph to 0.

Neo4j is always scaled back to 1: in-cluster EXIT/INT/TERM trap + container preStop, this script on Ctrl-C / Job failure, and CronJob `neo4j-replica-guard` every minute if a dump Job is not Active.

## Restore

`cloud-restore` (never rclone to `~/bucket`). One service at a time:

```bash
cloud-backup --list
cloud-restore --kind postgres --service api --archive ARCHIVE --confirm production
```

`--confirm production` is required. Neo4j load scales that graph to 0; trap/preStop/guard scale it back. Concourse is not used.

USB: `borg-backup.sh` rclone-syncs **from** `hetzner:statbook-prod-backups` to `/mnt/ext_backup/statbook-prod-backups` when the stick is mounted. That name is denylisted in `bucket -u/-p/--lifecycle`.
