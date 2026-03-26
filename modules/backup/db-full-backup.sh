#!/usr/bin/env bash
# /home/actools/modules/backup/db-full-backup.sh
# Phase 4.5 Item 2 — Daily full database dump (PITR baseline)
#
# Schedule: 02:00 daily (see cron entry at bottom of this file)
# Output:   /home/actools/backups/db/YYYY-MM-DD/full-dump.sql.gz.age
#
# Restoring from this dump is Step 1 of PITR.
# Step 2 is replaying binlogs up to the target time (see pitr-restore.sh).
#
# Usage: ./db-full-backup.sh [--verify]
#   --verify  After dump, do a quick structural check before encrypting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTOOLS_HOME="/home/actools"
BACKUP_ROOT="${ACTOOLS_HOME}/backups/db"
COMPOSE_FILE="${ACTOOLS_HOME}/docker-compose.yml"
ENV_FILE="${ACTOOLS_HOME}/actools.env"
AGE_KEY_FILE="${ACTOOLS_HOME}/.age-public-key"
LOG_FILE="${ACTOOLS_HOME}/logs/backup-db.log"

# Load env
# shellcheck source=/dev/null
source "${ENV_FILE}"

VERIFY=false
[[ "${1:-}" == "--verify" ]] && VERIFY=true

DATE=$(date +%F)
TIME=$(date +%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${DATE}"
DUMP_FILE="${BACKUP_DIR}/full-dump-${TIME}.sql.gz"
ENCRYPTED_FILE="${DUMP_FILE}.age"
CHECKSUM_FILE="${ENCRYPTED_FILE}.sha256"

log() { echo "$(date -u +%FT%TZ) [db-full-backup] $*" | tee -a "${LOG_FILE}"; }

mkdir -p "${BACKUP_DIR}"
log "Starting full database dump — ${DATE} ${TIME}"

# ── 1. Dump ──────────────────────────────────────────────────────────────────
# --single-transaction: consistent snapshot without locking tables (InnoDB)
# --flush-logs: rotate binlog at dump time so we know exactly which binlog
#               position this dump corresponds to. Critical for PITR.
# --master-data=2: writes CHANGE MASTER / binlog position as a comment in the
#                  dump. pitr-restore.sh uses this to know where to start
#                  replaying binlogs.
log "Dumping all databases..."
docker compose -f "${COMPOSE_FILE}" exec -T db \
  mariadb-dump \
    --user=root \
    --password="${DB_ROOT_PASS}" \
    --all-databases \
    --single-transaction \
    --flush-logs \
    --master-data=2 \
    --routines \
    --events \
    --triggers \
    --hex-blob \
  2>>"${LOG_FILE}" \
  | gzip -9 > "${DUMP_FILE}"

DUMP_SIZE=$(du -sh "${DUMP_FILE}" | cut -f1)
log "Dump complete — ${DUMP_SIZE} compressed"

# ── 2. Optional verification ──────────────────────────────────────────────────
if [[ "${VERIFY}" == "true" ]]; then
  log "Verifying dump structure..."
  TABLES=$(zcat "${DUMP_FILE}" | grep -c "^CREATE TABLE" || true)
  if [[ "${TABLES}" -lt 1 ]]; then
    log "ERROR: Dump appears empty (0 CREATE TABLE statements found)"
    exit 1
  fi
  log "Verification passed — ${TABLES} tables found in dump"
fi

# ── 3. Encrypt with age ────────────────────────────────────────────────────────
AGE_PUBLIC_KEY=$(cat "${AGE_KEY_FILE}")
log "Encrypting dump with age..."
age -r "${AGE_PUBLIC_KEY}" -o "${ENCRYPTED_FILE}" "${DUMP_FILE}"
rm "${DUMP_FILE}"  # Remove unencrypted copy immediately

# ── 4. Checksum ────────────────────────────────────────────────────────────────
sha256sum "${ENCRYPTED_FILE}" > "${CHECKSUM_FILE}"
log "Checksum written: $(cat "${CHECKSUM_FILE}")"

# ── 5. Record binlog position from this dump ──────────────────────────────────
# Grab the binlog file + position embedded in the dump header (--master-data=2)
BINLOG_POSITION=$(zcat "${ENCRYPTED_FILE}" 2>/dev/null | head -50 || true)
# Note: since the dump is now age-encrypted we can't zcat it easily here.
# The binlog position is embedded in the dump itself — pitr-restore.sh
# decrypts and extracts it at restore time. We log the current position
# separately for reference:
CURRENT_POSITION=$(docker compose -f "${COMPOSE_FILE}" exec -T db \
  mariadb --user=root --password="${DB_ROOT_PASS}" --batch --skip-column-names \
  -e "SHOW MASTER STATUS\G" 2>/dev/null || true)
log "Current binlog position at dump time:"
echo "${CURRENT_POSITION}" | tee -a "${LOG_FILE}"

# Write a plain-text manifest alongside the backup (not sensitive)
cat > "${BACKUP_DIR}/manifest.txt" << EOF
date: ${DATE} ${TIME}
file: $(basename "${ENCRYPTED_FILE}")
size_before_encrypt: ${DUMP_SIZE}
checksum_file: $(basename "${CHECKSUM_FILE}")
binlog_position_at_dump:
${CURRENT_POSITION}
EOF

# ── 6. Upload to off-site storage ─────────────────────────────────────────────
if command -v rclone &>/dev/null && [[ -n "${RCLONE_REMOTE:-}" ]]; then
  log "Uploading to ${RCLONE_REMOTE}/db-backups/${DATE}/ ..."
  rclone copy "${BACKUP_DIR}" "${RCLONE_REMOTE}/db-backups/${DATE}/" \
    --include "*.age" --include "*.sha256" --include "manifest.txt" \
    2>>"${LOG_FILE}"
  log "Upload complete"
else
  log "WARN: rclone not configured or RCLONE_REMOTE not set — skipping upload"
fi

# ── 7. Prune local backups older than retention window ────────────────────────
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
log "Pruning local backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d \
  -mtime "+${RETENTION_DAYS}" -exec rm -rf {} \; 2>>"${LOG_FILE}" || true

log "Full backup complete — ${ENCRYPTED_FILE}"

# ── CRON ENTRY ─────────────────────────────────────────────────────────────────
# Add to /etc/cron.d/actools-db-backup:
#
#   0 2 * * * actools /home/actools/modules/backup/db-full-backup.sh --verify >> /home/actools/logs/backup-db.log 2>&1
