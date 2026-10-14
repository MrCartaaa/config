# wire-statbook-dbs

Parallel `kubectl port-forward` helper for **Statbook Postgres** databases managed by ArgoCD.

Postgres services are **ClusterIP only** (not public). This script opens local listeners so GUI clients (`psql`, DBeaver, DataGrip, etc.) can reach staging and/or production DBs.

| | |
|---|---|
| Script | `~/.config/bash_custom/scripts/wire-statbook-dbs.sh` |
| Alias | `wire-statbook-dbs` (from `aliases.conf`) |
| Kubeconfig | `$KUBECONFIG` or `~/.config/kube/config` |

## 1:1 local wiring

Each env×service has **one** client port. That number is both:

1. the port you configure in your DB client, and  
2. the local bind port on `127.0.0.1`

**Example:** staging api → **15432** → connect to `localhost:15432` (not some other remapped local port).

Inside the cluster the Service still listens on 5432–5436; kubectl maps `local:cluster` under the hood (`15432:5432` for staging api). You never need the cluster port in your client.

## Requirements

- `kubectl` on `PATH`
- Cluster access (same context you use for Argo / `statbook-staging`)
- Credentials from **Vault** (this script does **not** fetch passwords):

  `secret/data/postgres/{staging|production}/{api|accounting|widget|queue|merchant|email}`

## Usage

```bash
# All services, staging only
wire-statbook-dbs --staging

# All services, production only
wire-statbook-dbs --prod

# Both environments, all services (12 forwards)
wire-statbook-dbs --staging --prod

# Staging, only API + queue
wire-statbook-dbs --staging --api-service --queue-service

# Production merchant only (underscore form also works)
wire-statbook-dbs --prod --merchant_service

# Show port map
wire-statbook-dbs --list

# Plan only
wire-statbook-dbs --staging --api-service --dry-run
```

### Flags

| Flag | Meaning |
|------|---------|
| `--staging` | Namespace `statbook-staging` |
| `--prod` / `--production` | Namespace `statbook-production` |
| `--api-service` / `--api_service` / `--api` | `postgres-api` |
| `--accounting-service` / … | `postgres-accounting` |
| `--widget-service` / … | `postgres-widget` |
| `--queue-service` / … | `postgres-queue` |
| `--merchant-service` / … | `postgres-merchant` |
| `--email-service` / `--email_service` / `--email` | `postgres-email` |
| `--all-services` | Every service (default when no service flag is given) |
| `--dry-run` | Print plan, start nothing |
| `--list` | Port / DB name cheat sheet |
| `-h` / `--help` | Help |

**Rules**

1. At least one of `--staging` or `--prod` is **required**.
2. Service flags are optional; if omitted, **all six** services are forwarded for each selected env.
3. Service flags alone (without an env flag) are an error.

Leave the terminal open. **Ctrl-C** kills every forward cleanly.

## Port map (1:1 local)

| Service | Staging (local) | Prod (local) | Cluster Service port | K8s service |
|---------|-----------------|--------------|----------------------|-------------|
| api | **15432** | **25432** | 5432 | `postgres-api` |
| accounting | **15433** | **25433** | 5433 | `postgres-accounting` |
| widget | **15434** | **25434** | 5434 | `postgres-widget` |
| queue | **15435** | **25435** | 5435 | `postgres-queue` |
| merchant | **15436** | **25436** | 5436 | `postgres-merchant` |
| email | **15437** | **25437** | 5437 | `postgres-email` |

Staging uses `15xxx`, prod `25xxx`, so both can run at once.

## Client settings

| Setting | Value |
|---------|--------|
| Host | `127.0.0.1` |
| Port | **wire port from table** (e.g. staging api = `15432`) |
| User | `app` (day-to-day) or `db_migrator` / `postgres` from Vault |
| Password | matching `app_user_pwd` / `migrator_pwd` / `superuser_pwd` |
| Database | see below |
| SSL | off (plain TCP over port-forward) |
| Options | `search_path=app` (Mae schema) |

### Database names

| Service | Database |
|---------|----------|
| api | `statbook` |
| accounting | `ru_accounting_service` |
| widget | `ru_widget_service` |
| queue | `ru_queue_service` |
| merchant | `ru_merchant_service` |
| email | `ru_email_service` |

### Example (`psql`, staging API)

```bash
wire-statbook-dbs --staging --api-service
# other terminal:
PGPASSWORD='…from vault…' psql -h 127.0.0.1 -p 15432 -U app -d statbook \
  -c 'SET search_path TO app; \dt'
```

Connection URI:

```text
postgres://app:PASSWORD@127.0.0.1:15432/statbook?options=-csearch_path%3Dapp
```

## Behaviour

- Starts one `kubectl port-forward` **per** env×service in the background (parallel).
- Binds **127.0.0.1** only (not LAN).
- **1:1 local:** client port == bind port (e.g. staging api = 15432).
- Refuses to start if a local port is already listening.
- Logs start/ready/errors with timestamps; per-forward kubectl output is written under `/tmp/wire-statbook-dbs-<pid>/` while running.
- Supervises children: if any forward dies, the script exits and tears down the rest.

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| `must specify at least one environment` | Pass `--staging` and/or `--prod` |
| `local port … already in use` | Another forward or app holds the port; `ss -ltnp \| grep 15432` |
| Forward dies immediately | `kubectl config current-context`; pod Running: `kubectl -n statbook-staging get pods -l app=postgres-api` |
| Auth failed in client | Wrong Vault env path (`staging` vs `production`) or wrong role password |
| Empty tables | Forgot `search_path=app` |

## Related

- Vault paths: `secret/data/postgres/{staging\|production}/{service}` (`email` included)
- Argo namespaces: `statbook-staging`, `statbook-production`
- K8s secrets (synced by ESO): `postgres-{service}-secret`
