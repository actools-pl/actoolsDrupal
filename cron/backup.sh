#!/usr/bin/env bash
# =============================================================================
# cron/backup.sh — Daily Backup Cron (S3-aware)
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================
set -euo pipefail

BACKUP_DIR="/home/actools/backups"
INSTALL_DIR="/home/actools"
TIMESTAMP=$(date +%F)

command -v docker &>/dev/null || exit 1
cd "${INSTALL_DIR}" || { echo "ERROR: INSTALL_DIR not found" >&2; exit 1; }

# shellcheck source=/dev/null
source "${INSTALL_DIR}/actools.env"

for env in "prod"; do
  DB="actools_${env}"
  DUMPFILE="${BACKUP_DIR}/${env}_db_${TIMESTAMP}.sql.gz"

  docker exec actools_db mariadb-dump \
    --single-transaction --quick \
    -ubackup -p"${BACKUP_RETENTION_DAYS:-7}" "$DB" \
    | gzip > "$DUMPFILE"

  sha256sum "$DUMPFILE" > "$DUMPFILE.sha256"
  sha256sum -c "$DUMPFILE.sha256" &>/dev/null || {
    echo "DB backup FAILED integrity check: $DUMPFILE" >&2
    rm -f "$DUMPFILE" "$DUMPFILE.sha256"
  }

  if [[ "${ENABLE_S3_STORAGE:-false}" == "true" ]]; then
    docker compose exec -T php_prod bash -c \
      "cd /var/www/html/prod && ./vendor/bin/drush s3fs:refresh-cache 2>/dev/null" \
      &>/dev/null && echo "S3 reachability OK for ${env}" \
      || echo "WARNING: S3 bucket unreachable for ${env}" >&2
  else
    FILES_SRC="${INSTALL_DIR}/docroot/${env}/web/sites/default/files"
    FILES_DST="${BACKUP_DIR}/${env}_files_${TIMESTAMP}.tar.gz"
    if [[ -d "$FILES_SRC" ]]; then
      tar -czf "$FILES_DST" -C "$FILES_SRC" . && \
        sha256sum "$FILES_DST" > "$FILES_DST.sha256"
    fi
  fi
done

find "${BACKUP_DIR}" -name "*.sql.gz"        -mtime +7 -delete
find "${BACKUP_DIR}" -name "*.sql.gz.sha256" -mtime +7 -delete
find "${BACKUP_DIR}" -name "*.tar.gz"        -mtime +7 -delete
find "${BACKUP_DIR}" -name "*.tar.gz.sha256" -mtime +7 -delete

RCLONE_REMOTE="${RCLONE_REMOTE:-}"
if [[ -n "${RCLONE_REMOTE}" ]] && command -v rclone &>/dev/null; then
  rclone copy "${BACKUP_DIR}" "${RCLONE_REMOTE}/" \
    --include "*.sql.gz" --include "*.tar.gz" \
    && echo "Remote backup pushed to ${RCLONE_REMOTE}"
fi
