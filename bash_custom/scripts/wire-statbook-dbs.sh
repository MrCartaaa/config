#!/usr/bin/env bash
# wire-statbook-dbs.sh — parallel kubectl port-forwards for Statbook Postgres
#
# See WIRE_STATBOOK_DBS.md in this directory for full docs.

set -euo pipefail

# ── constants ──────────────────────────────────────────────────────────────

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cluster Service ports (kubectl remote side — internal only).
declare -A CLUSTER_PORT=(
  [api]=5432
  [accounting]=5433
  [widget]=5434
  [queue]=5435
  [merchant]=5436
)

declare -A SERVICE_NAME=(
  [api]=postgres-api
  [accounting]=postgres-accounting
  [widget]=postgres-widget
  [queue]=postgres-queue
  [merchant]=postgres-merchant
)

# 1:1 local wiring: the wire port IS the local bind port (connect → localhost:N).
# Staging 15xxx / prod 25xxx so both envs can run together without collisions.
# Example: staging api → local 15432 (not remapped to something else on the client).
declare -A PORT_STAGING=(
  [api]=15432
  [accounting]=15433
  [widget]=15434
  [queue]=15435
  [merchant]=15436
)

declare -A PORT_PROD=(
  [api]=25432
  [accounting]=25433
  [widget]=25434
  [queue]=25435
  [merchant]=25436
)

declare -A NS=(
  [staging]=statbook-staging
  [prod]=statbook-production
)

ALL_SERVICES=(api accounting widget queue merchant)

# ── logging ────────────────────────────────────────────────────────────────

# Colors when stdout is a TTY
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET= C_DIM= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN=
fi

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

log()  { printf '%s%s%s %s\n' "$C_DIM" "$(_ts)" "$C_RESET" "$*"; }
info() { printf '%s%s%s %sℹ%s  %s\n' "$C_DIM" "$(_ts)" "$C_RESET" "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s%s%s %s✓%s  %s\n' "$C_DIM" "$(_ts)" "$C_RESET" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s%s%s %s!%s  %s\n' "$C_DIM" "$(_ts)" "$C_RESET" "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s%s%s %s✗%s  %s\n' "$C_DIM" "$(_ts)" "$C_RESET" "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── usage ──────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
${C_BOLD}${SCRIPT_NAME}${C_RESET} — port-forward Statbook Postgres (staging / production)

${C_BOLD}USAGE${C_RESET}
  wire-statbook-dbs --staging [--prod] [service flags…]
  wire-statbook-dbs --prod [service flags…]
  wire-statbook-dbs --staging --prod          # all services, both envs
  wire-statbook-dbs -h | --help

${C_BOLD}ENV FLAGS${C_RESET} (at least one required)
  --staging              Forward databases in namespace statbook-staging
  --prod, --production   Forward databases in namespace statbook-production

${C_BOLD}SERVICE FLAGS${C_RESET} (optional; default = all services)
  Require at least one of --staging / --prod.
  --api-service | --api_service | --api
  --accounting-service | --accounting_service | --accounting
  --widget-service | --widget_service | --widget
  --queue-service | --queue_service | --queue
  --merchant-service | --merchant_service | --merchant
  --all-services         Explicitly select every service (default when none given)

${C_BOLD}OTHER${C_RESET}
  -h, --help             Show this help
  --dry-run              Print planned forwards; do not start kubectl
  --list                 Print local port map and exit

${C_BOLD}PORTS (1:1 local — connect to localhost:N)${C_RESET}
  staging:  api 15432  accounting 15433  widget 15434  queue 15435  merchant 15436
  prod:     api 25432  accounting 25433  widget 25434  queue 25435  merchant 25436
  (cluster Service ports stay 5432–5436; only used as the kubectl remote target)

${C_BOLD}EXAMPLES${C_RESET}
  wire-statbook-dbs --staging
  wire-statbook-dbs --staging --api-service --queue-service
  wire-statbook-dbs --prod --merchant_service
  wire-statbook-dbs --staging --prod --api-service

Ctrl-C stops all port-forwards cleanly.
Docs: ${SCRIPT_DIR}/WIRE_STATBOOK_DBS.md
EOF
}

list_ports() {
  cat <<EOF
${C_BOLD}Statbook Postgres port map (1:1 local)${C_RESET}

  Connect to ${C_BOLD}localhost:<port>${C_RESET} — the wire port is the local bind port.

  Service       Staging   Prod     Cluster svc port   K8s service
  ────────────  ────────  ───────  ─────────────────  ──────────────────
EOF
  for s in "${ALL_SERVICES[@]}"; do
    printf '  %-12s  %-8s  %-7s  %-17s  %s\n' \
      "$s" "${PORT_STAGING[$s]}" "${PORT_PROD[$s]}" "${CLUSTER_PORT[$s]}" "${SERVICE_NAME[$s]}"
  done
  cat <<EOF

  Namespaces:  staging → ${NS[staging]}
               prod    → ${NS[prod]}

  Database names (for clients; not set by this script):
    api        → statbook
    accounting → ru_accounting_service
    widget     → ru_widget_service
    queue      → ru_queue_service
    merchant   → ru_merchant_service

  Prefer user ${C_BOLD}app${C_RESET} (or db_migrator) from Vault secret/data/postgres/{env}/{service}.
  Set search_path=app (Mae).
EOF
}

# ── helpers ────────────────────────────────────────────────────────────────

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :${port} )" 2>/dev/null | grep -q ":${port}"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  else
    # best-effort: try binding via bash /dev/tcp reverse is not enough; assume free
    return 1
  fi
}

normalize_service_flag() {
  # stdin-free: echo normalized service key or empty
  local raw="${1//_/-}"
  raw="${raw#--}"
  raw="${raw%-service}"
  case "$raw" in
    api|accounting|widget|queue|merchant) echo "$raw" ;;
    all) echo "all" ;;
    *) echo "" ;;
  esac
}

# ── arg parse ──────────────────────────────────────────────────────────────

want_staging=0
want_prod=0
dry_run=0
declare -a selected_services=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --list)
      list_ports
      exit 0
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --staging)
      want_staging=1
      shift
      ;;
    --prod|--production)
      want_prod=1
      shift
      ;;
    --all-services|--all_services)
      selected_services=("${ALL_SERVICES[@]}")
      shift
      ;;
    --api-service|--api_service|--api|\
    --accounting-service|--accounting_service|--accounting|\
    --widget-service|--widget_service|--widget|\
    --queue-service|--queue_service|--queue|\
    --merchant-service|--merchant_service|--merchant)
      key="$(normalize_service_flag "$1")"
      [[ -n "$key" ]] || die "internal: bad service flag parse: $1"
      selected_services+=("$key")
      shift
      ;;
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
done

# ── validation ─────────────────────────────────────────────────────────────

if (( want_staging == 0 && want_prod == 0 )); then
  die "must specify at least one environment: --staging and/or --prod"
fi

# Service flags require an env flag (already enforced by the check above if they
# only passed services — but if they passed services without env, same error).
# Explicit rule for clarity when only services were intended:
if (( ${#selected_services[@]} > 0 )) && (( want_staging == 0 && want_prod == 0 )); then
  die "service flags require --staging and/or --prod"
fi

if (( ${#selected_services[@]} == 0 )); then
  selected_services=("${ALL_SERVICES[@]}")
fi

# Dedupe services while preserving order
declare -A seen_svc=()
declare -a services=()
for s in "${selected_services[@]}"; do
  [[ -n "${seen_svc[$s]:-}" ]] && continue
  seen_svc[$s]=1
  services+=("$s")
done

command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"
if [[ -z "${KUBECONFIG:-}" && ! -f "${HOME}/.kube/config" && ! -f "${HOME}/.config/kube/config" ]]; then
  warn "KUBECONFIG unset and no default kubeconfig found; kubectl may fail"
fi
# Prefer project kubeconfig if set in shell already; else common path
if [[ -z "${KUBECONFIG:-}" && -f "${HOME}/.config/kube/config" ]]; then
  export KUBECONFIG="${HOME}/.config/kube/config"
fi

# ── build forward plan ─────────────────────────────────────────────────────

# Each entry: env|service|namespace|k8s_svc|port|cluster_port
# port is 1:1 local (bind + client). cluster_port is kubectl remote only.
declare -a PLAN=()

add_plan() {
  local env="$1" svc="$2"
  local ns port cluster_port k8s
  ns="${NS[$env]}"
  cluster_port="${CLUSTER_PORT[$svc]}"
  k8s="${SERVICE_NAME[$svc]}"
  if [[ "$env" == "staging" ]]; then
    port="${PORT_STAGING[$svc]}"
  else
    port="${PORT_PROD[$svc]}"
  fi
  PLAN+=("${env}|${svc}|${ns}|${k8s}|${port}|${cluster_port}")
}

for s in "${services[@]}"; do
  (( want_staging )) && add_plan staging "$s"
  (( want_prod )) && add_plan prod "$s"
done

info "plan: ${#PLAN[@]} port-forward(s) — services: ${services[*]} (1:1 local ports)"
for entry in "${PLAN[@]}"; do
  IFS='|' read -r env svc ns k8s port cport <<<"$entry"
  log "  ${C_CYAN}${env}${C_RESET}/${C_BOLD}${svc}${C_RESET}  ${ns}/${k8s}  ${C_GREEN}localhost:${port}${C_RESET}  (cluster :${cport})"
done

if (( dry_run )); then
  ok "dry-run complete (nothing started)"
  exit 0
fi

# ── port conflict check ────────────────────────────────────────────────────

for entry in "${PLAN[@]}"; do
  IFS='|' read -r env svc ns k8s port cport <<<"$entry"
  if port_in_use "$port"; then
    die "local port ${port} already in use (${env}/${svc}). Stop the other process or free the port."
  fi
done

# ── run forwards in parallel ───────────────────────────────────────────────

declare -a PF_PIDS=()
declare -A PID_LABEL=()
LOG_DIR="${TMPDIR:-/tmp}/wire-statbook-dbs-$$"
mkdir -p "$LOG_DIR"

cleanup() {
  local code=$?
  trap - EXIT INT TERM
  echo
  warn "shutting down ${#PF_PIDS[@]} port-forward(s)…"
  for pid in "${PF_PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # also kill process group children of kubectl
      kill -- -"$pid" 2>/dev/null || true
    fi
  done
  # wait briefly
  for pid in "${PF_PIDS[@]:-}"; do
    wait "$pid" 2>/dev/null || true
  done
  ok "all port-forwards stopped (logs were in ${LOG_DIR})"
  rm -rf "$LOG_DIR" 2>/dev/null || true
  exit "$code"
}

trap cleanup EXIT INT TERM

start_forward() {
  local env="$1" svc="$2" ns="$3" k8s="$4" port="$5" cport="$6"
  local label="${env}/${svc}"
  local logf="${LOG_DIR}/${env}-${svc}.log"

  # 1:1 local: bind port == client port. Cluster service port is kubectl remote only.
  # --address 127.0.0.1 keeps binds local-only
  kubectl -n "$ns" port-forward --address 127.0.0.1 "svc/${k8s}" "${port}:${cport}" \
    >"$logf" 2>&1 &
  local pid=$!
  PF_PIDS+=("$pid")
  PID_LABEL[$pid]="$label"
  info "started ${label}  pid=${pid}  localhost:${port}  log=${logf}"
}

for entry in "${PLAN[@]}"; do
  IFS='|' read -r env svc ns k8s port cport <<<"$entry"
  start_forward "$env" "$svc" "$ns" "$k8s" "$port" "$cport"
done

# ── readiness wait ─────────────────────────────────────────────────────────

info "waiting for listeners…"
ready=0
fail=0
deadline=$(( SECONDS + 30 ))

declare -A IS_READY=()

while (( SECONDS < deadline )); do
  ready=0
  fail=0
  for pid in "${PF_PIDS[@]}"; do
    label="${PID_LABEL[$pid]}"
    if [[ -n "${IS_READY[$pid]:-}" ]]; then
      ((ready++)) || true
      continue
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      err "port-forward died early: ${label}"
      # show tail of log
      env_svc="${label//\//-}"
      logf="${LOG_DIR}/${env_svc}.log"
      [[ -f "$logf" ]] && sed 's/^/    /' "$logf" | tail -n 8 >&2
      ((fail++)) || true
      continue
    fi
    # extract local port from plan by label
    for entry in "${PLAN[@]}"; do
      IFS='|' read -r e s n k p c <<<"$entry"
      if [[ "${e}/${s}" == "$label" ]]; then
        if port_in_use "$p"; then
          IS_READY[$pid]=1
          ok "ready ${label}  localhost:${p}  (${n}/svc/${k} cluster :${c})"
          ((ready++)) || true
        fi
        break
      fi
    done
  done

  if (( fail > 0 )); then
    die "${fail} forward(s) failed to start — check kubectl context and that pods are Running"
  fi
  if (( ready == ${#PF_PIDS[@]} )); then
    break
  fi
  sleep 0.3
done

if (( ready < ${#PF_PIDS[@]} )); then
  warn "only ${ready}/${#PF_PIDS[@]} listeners confirmed after timeout; check logs in ${LOG_DIR}"
fi

echo
ok "forwarding ${#PF_PIDS[@]} database(s). Leave this terminal open."
info "connection tip: host=127.0.0.1  user=app  db=see --list  options=search_path=app"
info "credentials: Vault secret/data/postgres/{staging|production}/{service}"
echo
printf '%s\n' "${C_BOLD}Active forwards (1:1 local — use these ports in your client)${C_RESET}"
printf '  %-12s %-12s %-18s %s\n' "ENV" "SERVICE" "CONNECT" "K8S TARGET"
printf '  %-12s %-12s %-18s %s\n' "───" "───────" "───────" "──────────"
for entry in "${PLAN[@]}"; do
  IFS='|' read -r env svc ns k8s port cport <<<"$entry"
  printf '  %-12s %-12s %-18s %s\n' \
    "$env" "$svc" "127.0.0.1:${port}" "${ns}/${k8s}:${cport}"
done
echo
info "press Ctrl-C to stop all"

# ── supervise ──────────────────────────────────────────────────────────────

# Wait until any child exits (unexpected) or signal
while true; do
  for pid in "${PF_PIDS[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      label="${PID_LABEL[$pid]}"
      err "port-forward exited: ${label}"
      env_svc="${label//\//-}"
      logf="${LOG_DIR}/${env_svc}.log"
      [[ -f "$logf" ]] && { warn "last log lines:"; sed 's/^/    /' "$logf" | tail -n 12; }
      die "aborting remaining forwards"
    fi
  done
  sleep 2
done
