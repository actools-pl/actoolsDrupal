#!/usr/bin/env bash
# =============================================================================
# modules/backup/cron.sh — Daily backup cron generator (S3-aware)
#
# LIVE AUTHORITY (P0-L): carries the monolith's exact setup_backup_cron()
# definition, extracted VERBATIM from the inline v14 block in actools.sh
# (per-function byte-identity verified; the generated
# /etc/cron.daily/actools-backup is byte-identical — golden capture
# tests/fixtures/golden/backup-cron). Sourced by actools.sh on the live
# install path.
#
# SECURITY SHAPE (locked by tests/guards/cron_security_shape_guard_test.bats):
# the generated cron writes [mariadb-dump]/user/password into a umask-077
# temp file INSIDE the DB container and runs
# `mariadb-dump --defaults-extra-file="$t"` — the password is NEVER on argv
# (never visible in ps) and is read from .actools-state.json at cron RUNTIME,
# so no secret is baked into the script. The retired v9.2 orphan twin
# (deleted at P0-L) passed the backup password as a -p argument on argv
# (visible in ps); that form must never be adopted.
#
# Required globals (set by actools.sh BEFORE setup_backup_cron is called):
#   INSTALL_DIR            — install root (BASH_SOURCE-relative, v14 semantics)
#   ENVIRONMENTS           — comma-separated env list (render-time expansion)
#   ENABLE_S3_STORAGE, S3_BUCKET, S3_ENDPOINT_URL, STORAGE_PROVIDER,
#   BACKUP_RETENTION_DAYS, RCLONE_REMOTE — optional; the v14 defaults
#   (:-true / "" / aws / 7 / "") expand inside the function/heredoc.
#
# Collaborators (must be defined when the function RUNS):
#   section/log      — core/bootstrap.sh
#   get_backup_pass  — core/secrets.sh
#
# Functions only — no variable assignments — so the module is inert under
# `set -u` at source time.
# =============================================================================

setup_backup_cron() {
  section "Backup Cron"
  local backup_dir="$INSTALL_DIR/backups"
  local backup_pass
  backup_pass=$(get_backup_pass)
  local s3_on="${ENABLE_S3_STORAGE:-true}"
  local s3_bucket="${S3_BUCKET:-}"
  local s3_endpoint="${S3_ENDPOINT_URL:-}"
  local s3_provider="${STORAGE_PROVIDER:-aws}"

  cat > /etc/cron.daily/actools-backup <<BACKUP
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="${backup_dir}"
INSTALL_DIR="${INSTALL_DIR}"
TIMESTAMP=\$(date +%F)
ENABLE_S3_STORAGE="${s3_on}"
S3_BUCKET="${s3_bucket}"
S3_ENDPOINT_URL="${s3_endpoint}"
STORAGE_PROVIDER="${s3_provider}"

command -v docker &>/dev/null || exit 1
cd "\${INSTALL_DIR}" || { echo "ERROR: INSTALL_DIR not found: \${INSTALL_DIR}" >&2; exit 1; }

for env in $(echo "${ENVIRONMENTS}" | tr ',' ' '); do
  DB="actools_\${env}"
  DUMPFILE="\${BACKUP_DIR}/\${env}_db_\${TIMESTAMP}.sql.gz"
  BK=\$(jq -r '.backup_user_pass // empty' "${INSTALL_DIR}/.actools-state.json")
  printf '%s\n' '[mariadb-dump]' 'user=backup' "password=\$BK" \
    | docker exec -i actools_db sh -c '
        umask 077; t=\$(mktemp /tmp/actools-dump.XXXXXX.cnf); trap "rm -f \"\$t\"" EXIT
        cat > "\$t"
        mariadb-dump --defaults-extra-file="\$t" "\$@"
      ' _ --single-transaction --quick "\$DB" \
    | gzip > "\$DUMPFILE"
  sha256sum "\$DUMPFILE" > "\$DUMPFILE.sha256"
  sha256sum -c "\$DUMPFILE.sha256" &>/dev/null || {
    echo "DB backup FAILED integrity check: \$DUMPFILE" >&2
    rm -f "\$DUMPFILE" "\$DUMPFILE.sha256"
  }

  if [[ "\${ENABLE_S3_STORAGE}" == "true" ]]; then
    if docker compose exec -T php_prod bash -c \
      "cd /var/www/html/prod && ./vendor/bin/drush s3fs:refresh-cache 2>/dev/null" \
      &>/dev/null 2>&1; then
      echo "S3 reachability OK for \${env} (bucket: \${S3_BUCKET})"
    else
      echo "WARNING: S3 bucket unreachable for \${env} -- files not backed up" >&2
    fi
  else
    FILES_SRC="${INSTALL_DIR}/docroot/\${env}/web/sites/default/files"
    FILES_DST="\${BACKUP_DIR}/\${env}_files_\${TIMESTAMP}.tar.gz"
    if [[ -d "\$FILES_SRC" ]]; then
      tar -czf "\$FILES_DST" -C "\$FILES_SRC" . && \
        sha256sum "\$FILES_DST" > "\$FILES_DST.sha256" && \
        sha256sum -c "\$FILES_DST.sha256" &>/dev/null || {
          echo "Files backup FAILED integrity check: \$FILES_DST" >&2
          rm -f "\$FILES_DST" "\$FILES_DST.sha256"
        }
    fi
  fi
done

find "\${BACKUP_DIR}" -name "*.sql.gz"        -mtime +${BACKUP_RETENTION_DAYS:-7} -delete
find "\${BACKUP_DIR}" -name "*.sql.gz.sha256"  -mtime +${BACKUP_RETENTION_DAYS:-7} -delete
find "\${BACKUP_DIR}" -name "*.tar.gz"         -mtime +${BACKUP_RETENTION_DAYS:-7} -delete
find "\${BACKUP_DIR}" -name "*.tar.gz.sha256"  -mtime +${BACKUP_RETENTION_DAYS:-7} -delete

RCLONE_REMOTE="${RCLONE_REMOTE:-}"
if [[ -n "\${RCLONE_REMOTE}" ]] && command -v rclone &>/dev/null; then
  rclone copy "\${BACKUP_DIR}" "\${RCLONE_REMOTE}/" \
    --include "*.sql.gz" --include "*.tar.gz" \
    && echo "Remote backup pushed to \${RCLONE_REMOTE}"
fi
BACKUP
  chmod +x /etc/cron.daily/actools-backup
  log "Daily backup cron installed (S3-aware)."
}
