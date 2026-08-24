#!/usr/bin/env bash
# In-cluster restore from hetzner:statbook-prod-backups. Never rclone to ~/bucket.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)/.util/log.sh"
LOG_TS=1

NS_CD="${NS_CD:-statbook-cd}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

if [[ -z "${KUBECONFIG:-}" && -f "${HOME}/.config/kube/config" ]]; then
  export KUBECONFIG="${HOME}/.config/kube/config"
fi
command -v kubectl >/dev/null 2>&1 || log_exit_bad "kubectl not found"
if [[ -z "$KUBE_CONTEXT" ]] && kubectl config get-contexts -o name 2>/dev/null | grep -qx cloud; then
  KUBE_CONTEXT=cloud
fi

kc() {
  if [[ -n "$KUBE_CONTEXT" ]]; then
    kubectl --context "$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

if ! timeout 12s kc --request-timeout=8s get --raw /healthz >/dev/null 2>&1; then
  log_exit_bad "kube-apiserver unreachable from this laptop"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
kc -n "$NS_CD" get cm db-backup-scripts -o jsonpath='{.data.restore-prod-db\.sh}' >"$tmp"
[[ -s "$tmp" ]] || log_exit_bad "restore-prod-db.sh missing from ConfigMap db-backup-scripts"
chmod +x "$tmp"
log_hello "in-cluster restore (no local copy of the bucket)"
exec bash "$tmp" "$@"
