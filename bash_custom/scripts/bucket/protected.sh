# Cluster-owned buckets. Never push, pull, or lifecycle from ~/bucket/.
# Sourced by push_bucket.sh, pull_bucket.sh, lifecycle_bucket.sh.
PROTECTED_BUCKETS=(statbook-prod-backups)

bucket_is_protected() {
  local name="$1" p
  for p in "${PROTECTED_BUCKETS[@]}"; do
    [[ "$name" == "$p" ]] && return 0
  done
  return 1
}

refuse_protected_bucket() {
  local name="$1"
  if bucket_is_protected "$name"; then
    log_exit_bad "${name} is cluster-owned (prod DB Borg). Do not push/pull/lifecycle it from ~/bucket. USB copy is borg-backup.sh when /mnt/ext_backup is mounted."
  fi
}
