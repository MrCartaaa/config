#!/usr/bin/env bash
# cloud-db-backup.sh — fire the production DB backup CronJob from this machine.
#
# See CLOUD_DB_BACKUP.md in this directory for full docs.

set -euo pipefail

# Source logger (resolve git root from script's location, not CWD)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)/.util/log.sh"

LOG_TS=1

SCRIPT_NAME="$(basename "$0")"

NS_CD="${NS_CD:-statbook-cd}"
NS_PROD="${NS_PROD:-statbook-production}"
CRONJOB="${CRONJOB:-db-backup}"
NEO4J_SERVICES=(api accounting widget queue merchant)
BUCKET="${BUCKET:-statbook-prod-backups}"
DEFAULT_SSH_HOST="${DEFAULT_SSH_HOST:-cloud-cicd}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-7200s}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

SSH_TARGET=""
YES=0
WAIT=1
FOLLOW=1
DRY_RUN=0
FORCE=0
MODE="run" # run | status | logs | list

usage() {
  cat <<EOF
Usage: cloud-backup [--yes] [--ssh [host]] [--no-wait] [--no-follow] [--force]
       cloud-backup --status
       cloud-backup --logs
       cloud-backup --list
       cloud-backup -h | --help

Create a Job from CronJob ${CRONJOB} in namespace ${NS_CD}.
That Job: pg_dump -Fc (online) + Neo4j dump (brief scale-to-0) → Borg → rclone hetzner:${BUCKET}.

Flags:
  --yes, --confirm production
                         Skip the Neo4j-downtime prompt
  --ssh [host]           Opt-in: kubectl on the node (default host: ${DEFAULT_SSH_HOST})
                         Uses /etc/kubernetes/admin.conf via sudo. Not a fallback.
  --no-wait              Create the Job and exit (do not wait or follow logs)
  --no-follow            Wait for Job completion without streaming logs
  --force                Allow a second Job even if one is already Active
  --dry-run              Print kubectl commands; do not create a Job
  --status               Show CronJob + recent Jobs and exit
  --logs                 Follow logs of the newest backup Job and exit
  --list                 In-cluster borg list of hetzner:${BUCKET} (no local copy)
  --context NAME         kubectl context (default: cloud if present)
  -h, --help             Show this help

Examples:
  cloud-backup
  cloud-backup --yes
  cloud-backup --ssh
  cloud-backup --ssh cloud-cicd --yes
  cloud-backup --status
  cloud-backup --logs

Notes:
  Alias backup is local Borg (this machine). This alias is cloud-backup.
  Nightly schedule is 02:00 UTC; this does not wait for it.
  Overlapping backups are refused (Neo4j dump is exclusive) unless --force.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --yes)
      YES=1
      shift
      ;;
    --confirm)
      [[ "${2:-}" == "production" ]] || log_exit_bad "--confirm requires: production"
      YES=1
      shift 2
      ;;
    --ssh)
      if [[ -n "${2:-}" && "$2" != -* ]]; then
        SSH_TARGET="$2"
        shift 2
      else
        SSH_TARGET="$DEFAULT_SSH_HOST"
        shift
      fi
      ;;
    --no-wait)
      WAIT=0
      FOLLOW=0
      shift
      ;;
    --no-follow)
      FOLLOW=0
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --status)
      MODE="status"
      shift
      ;;
    --logs)
      MODE="logs"
      shift
      ;;
    --list)
      MODE="list"
      shift
      ;;
    --context)
      [[ -n "${2:-}" ]] || log_exit_bad "--context requires a name"
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    *)
      log_error "Unknown flag: $1"
      usage
      ;;
  esac
done

if [[ -z "${KUBECONFIG:-}" && -f "${HOME}/.config/kube/config" ]]; then
  export KUBECONFIG="${HOME}/.config/kube/config"
fi

if [[ -n "$SSH_TARGET" ]]; then
  command -v ssh >/dev/null 2>&1 || log_exit_bad "ssh not found in PATH"
else
  command -v kubectl >/dev/null 2>&1 || log_exit_bad "kubectl not found in PATH"
  if [[ -z "$KUBE_CONTEXT" ]] && kubectl config get-contexts -o name 2>/dev/null | grep -qx cloud; then
    KUBE_CONTEXT=cloud
  fi
fi

SSH_TTY=0
kube() {
  if [[ -n "$SSH_TARGET" ]]; then
    local remote
    remote=$(printf '%q ' kubectl "$@")
    local ssh_cmd=(ssh -o BatchMode=yes -o ConnectTimeout=10)
    if (( SSH_TTY )); then
      ssh_cmd+=(-t)
    fi
    "${ssh_cmd[@]}" "$SSH_TARGET" \
      "sudo env KUBECONFIG=/etc/kubernetes/admin.conf $remote"
  else
    if [[ -n "$KUBE_CONTEXT" ]]; then
      kubectl --context "$KUBE_CONTEXT" "$@"
    else
      kubectl "$@"
    fi
  fi
}

# kube-control from this laptop is required. Do not hide API failures behind SSH.
require_local_api() {
  local ctx=()
  [[ -n "$KUBE_CONTEXT" ]] && ctx=(--context "$KUBE_CONTEXT")
  if timeout 12s kubectl "${ctx[@]}" --request-timeout=8s get --raw /healthz >/dev/null 2>&1; then
    return 0
  fi
  log_exit_bad "kube-apiserver unreachable from this laptop (context ${KUBE_CONTEXT:-current}). Fix kubectl/6443; SSH is opt-in --ssh only."
}

newest_job() {
  kube -n "$NS_CD" get jobs -l "app.kubernetes.io/name=${CRONJOB}" \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true
}

active_jobs() {
  kube -n "$NS_CD" get jobs -l "app.kubernetes.io/name=${CRONJOB}" \
    -o jsonpath='{range .items[?(@.status.active>0)]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}

show_status() {
  log_info "CronJob ${CRONJOB} (${NS_CD})"
  kube -n "$NS_CD" get cronjob "$CRONJOB" || {
    log_exit_bad "CronJob ${CRONJOB} not found in ${NS_CD} — merge/sync argocd db-backup Application first"
  }
  echo
  log_info "Jobs"
  kube -n "$NS_CD" get jobs -l "app.kubernetes.io/name=${CRONJOB}" \
    --sort-by=.metadata.creationTimestamp || true
}

follow_job_logs() {
  local job="$1"
  [[ -n "$job" ]] || log_exit_bad "no ${CRONJOB} Job found"
  log_info "waiting for a pod on Job/${job}"
  kube -n "$NS_CD" wait --for=condition=Ready pod -l "job-name=${job}" --timeout=180s \
    || log_warn "pod not Ready yet; attempting logs anyway"
  SSH_TTY=1
  kube -n "$NS_CD" logs -f "job/${job}" --all-containers=true --tail=100 || true
  SSH_TTY=0
}

restore_neo4j() {
  local svc
  log_warn "restoring neo4j production replicas to 1"
  for svc in "${NEO4J_SERVICES[@]}"; do
    kube -n "$NS_PROD" scale "deploy/neo4j-${svc}" --replicas=1 || log_warn "scale neo4j-${svc} failed"
  done
}

# After a Job exists: Ctrl-C must not leave Neo4j at 0.
# Delete the Job so the pod gets SIGTERM (in-cluster trap + preStop), then scale anyway.
HOLD_NEO4J=0
CREATED_JOB=""
abort_restore_neo4j() {
  trap - INT TERM
  (( HOLD_NEO4J )) || return 0
  HOLD_NEO4J=0
  log_warn "backup interrupted — putting Neo4j back up"
  if [[ -n "${CREATED_JOB:-}" ]]; then
    kube -n "$NS_CD" delete "job/${CREATED_JOB}" --wait=false --ignore-not-found || true
  fi
  restore_neo4j
}

wait_job() {
  local job="$1"
  log_info "waiting up to ${WAIT_TIMEOUT} for Job/${job}"
  if kube -n "$NS_CD" wait --for=condition=complete "job/${job}" --timeout="$WAIT_TIMEOUT"; then
    log_ok "Job/${job} completed — archives are in hetzner:${BUCKET}"
    return 0
  fi
  local failed
  failed="$(kube -n "$NS_CD" get "job/${job}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  restore_neo4j
  if [[ -n "$failed" && "$failed" != "0" ]]; then
    log_error "Job/${job} failed"
    kube -n "$NS_CD" logs "job/${job}" --all-containers=true --tail=80 || true
    log_exit_bad "Job/${job} failed (neo4j scaled back to 1)"
  fi
  log_exit_bad "Job/${job} did not complete within ${WAIT_TIMEOUT} (neo4j scaled back to 1)"
}

confirm_run() {
  (( YES )) && return 0
  if [[ ! -t 0 ]]; then
    log_exit_bad "non-interactive: pass --yes (Neo4j production will be briefly unavailable)"
  fi
  log_warn "This runs the production DB backup now."
  log_info "Postgres: online pg_dump -Fc (api, accounting, widget, queue, merchant)"
  log_info "Neo4j: each graph is scaled to 0 for the dump, then scaled back"
  log_info "Destination: hetzner:${BUCKET}"
  local ans=""
  read -r -p "Continue? [y/N] " ans
  if [[ "$ans" != [yY] && "$ans" != [yY][eE][sS] ]]; then
    log_skip "aborted"
    exit 0
  fi
}

if [[ -z "$SSH_TARGET" ]]; then
  require_local_api
fi

if [[ "$MODE" == "status" ]]; then
  log_hello "Production DB backup status"
  show_status
  log_exit_ok "status complete"
fi

if [[ "$MODE" == "logs" ]]; then
  job="$(newest_job)"
  follow_job_logs "$job"
  log_exit_ok "logs complete"
fi

if [[ "$MODE" == "list" ]]; then
  list_args=(--list)
  [[ -n "$SSH_TARGET" ]] && list_args+=(--ssh "$SSH_TARGET")
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cloud-db-restore.sh" "${list_args[@]}"
fi

via="kubectl"
[[ -n "$SSH_TARGET" ]] && via="ssh ${SSH_TARGET}"
log_hello "Triggering ${CRONJOB} via ${via} → hetzner:${BUCKET}"

if ! kube -n "$NS_CD" get "cronjob/${CRONJOB}" >/dev/null; then
  log_exit_bad "CronJob ${CRONJOB} not found in ${NS_CD}. Need GitOps db-backup Application + Vault secret db-backup-secret."
fi

if ! kube -n "$NS_CD" get secret db-backup-secret >/dev/null; then
  log_exit_bad "Secret db-backup-secret missing in ${NS_CD}. Run ansible k8s-bootstrap --tags vault-secrets, then wait for ESO."
fi

if ! kube -n "$NS_CD" get pvc db-backup-borg >/dev/null; then
  log_exit_bad "PVC db-backup-borg missing in ${NS_CD}."
fi

running="$(active_jobs)"
if [[ -n "$running" ]]; then
  if (( FORCE )); then
    log_warn "already Active: ${running//$'\n'/ } — --force, creating another Job"
  else
    log_exit_bad "backup already Active (${running//$'\n'/ }). Wait, or pass --force (Neo4j dump is exclusive)."
  fi
fi

job="db-backup-manual-$(date -u +%Y%m%d-%H%M%S)"

if (( DRY_RUN )); then
  log_dryrun "would create Job/${job} from cronjob/${CRONJOB}"
  log_info "kubectl -n ${NS_CD} create job ${job} --from=cronjob/${CRONJOB}"
  log_exit_ok "dry-run complete"
fi

confirm_run

log_info "creating Job/${job}"
if ! kube -n "$NS_CD" create job "$job" --from="cronjob/${CRONJOB}"; then
  log_exit_bad "failed to create Job/${job}"
fi
log_ok "Job/${job} created"

CREATED_JOB="$job"
HOLD_NEO4J=1
trap abort_restore_neo4j INT TERM

if (( ! WAIT )); then
  trap - INT TERM
  HOLD_NEO4J=0
  log_info "not waiting (--no-wait). Follow later with: ${SCRIPT_NAME} --logs"
  log_warn "Neo4j restore on abort is the in-cluster trap/preStop + minute guard"
  log_exit_ok "Job/${job} created"
fi

if (( FOLLOW )); then
  follow_job_logs "$job"
fi
wait_job "$job"
trap - INT TERM
HOLD_NEO4J=0
restore_neo4j
log_exit_ok "backup complete: Job/${job} → hetzner:${BUCKET}"
