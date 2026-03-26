#!/usr/bin/env bash
# /home/actools/modules/backup/binlog-rotate.sh
# Phase 4.5 Item 2 — Hourly binlog rotation, encryption and upload

set -euo pipefail

ACTOOLS_HOME="/home/actools"
COMPOSE_FILE="${ACTOOLS_HOME}/docker-compose.yml"
ENV_FILE="${ACTOOLS_HOME}/actools.env"
AGE_KEY_FILE="${ACTOOLS_HOME}/.age-public-key"
LOG_FILE="${ACTOOLS_HOME}/logs/binlog-rotate.log"
ARCHIVE_DIR="${ACTOOLS_HOME}/backups/binlogs"

source "${ENV_FILE}"

log() { echo "$(date -u +%FT%TZ) [binlog-rotate] $*" | tee -a "${LOG_FILE}"; }

mkdir -p "${ARCHIVE_DIR}"
AGE_PUBLIC_KEY=$(cat "${AGE_KEY_FILE}")

mariadb_cmd() {
  docker compose -f "${COMPOSE_FILE}" exec -T db \
    mariadb --user=root --password="${DB_ROOT_PASS}" \
    --batch --skip-column-names "$@" 2>/dev/null
}

# 1. Flush current binlog
log "Flushing binary logs..."
mariadb_cmd -e "FLUSH BINARY LOGS;"

# 2. Get current active binlog
CURRENT_BINLOG=$(mariadb_cmd -e "SHOW MASTER STATUS;" | awk '{print $1}')
log "Current active binlog: ${CURRENT_BINLOG}"

# 3. Collect all binlog names into array first
#    (must not use while-read + docker exec together — docker exec steals stdin)
mapfile -t ALL_BINLOGS < <(mariadb_cmd -e "SHOW BINARY LOGS;" | awk '{print $1}')

ARCHIVED=0
SKIPPED=0

for BINLOG_NAME in "${ALL_BINLOGS[@]}"; do
  [[ -z "${BINLOG_NAME}" ]] && continue

  # Skip active binlog
  if [[ "${BINLOG_NAME}" == "${CURRENT_BINLOG}" ]]; then
    (( SKIPPED++ )) || true
    continue
  fi

  # Skip already archived
  if [[ -f "${ARCHIVE_DIR}/${BINLOG_NAME}.gz.age" ]]; then
    (( SKIPPED++ )) || true
    continue
  fi

  log "Archiving ${BINLOG_NAME}..."

  # </dev/null prevents docker exec from consuming the for-loop's stdin
  docker compose -f "${COMPOSE_FILE}" exec -T db \
    cat "/var/log/mysql/${BINLOG_NAME}" </dev/null \
    | gzip -c \
    | age -r "${AGE_PUBLIC_KEY}" \
    -o "${ARCHIVE_DIR}/${BINLOG_NAME}.gz.age"

  sha256sum "${ARCHIVE_DIR}/${BINLOG_NAME}.gz.age" \
    > "${ARCHIVE_DIR}/${BINLOG_NAME}.gz.age.sha256"

  (( ARCHIVED++ )) || true
  log "Archived ${BINLOG_NAME}"
done

log "Archived ${ARCHIVED} binlog(s), skipped ${SKIPPED}"

# 4. Upload if rclone configured
if [[ "${ARCHIVED}" -gt 0 ]] && command -v rclone &>/dev/null && [[ -n "${RCLONE_REMOTE:-}" ]]; then
  log "Uploading to ${RCLONE_REMOTE}/binlogs/..."
  rclone copy "${ARCHIVE_DIR}" "${RCLONE_REMOTE}/binlogs/" \
    --include "*.age" --include "*.sha256" 2>>"${LOG_FILE}"
  log "Upload complete"
fi

# 5. Prune old archives
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
PRUNED=$(find "${ARCHIVE_DIR}" -name "*.gz.age" -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null | wc -l)
[[ "${PRUNED}" -gt 0 ]] && log "Pruned ${PRUNED} old archive(s)"

log "Binlog rotation complete"
