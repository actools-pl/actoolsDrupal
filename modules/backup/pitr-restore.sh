#!/usr/bin/env bash
# /home/actools/modules/backup/pitr-restore.sh
# Phase 4.5 Item 2 — Point-in-Time Recovery
#
# Restores the database to any point in time since the last full dump.
#
# Usage:
#   ./pitr-restore.sh --target "2026-03-26 14:30:00"
#   ./pitr-restore.sh --target "2026-03-26 14:30:00" --dry-run
#   ./pitr-restore.sh --target "2026-03-26 14:30:00" --dump-date 2026-03-26
#
# What it does:
#   1. Finds the most recent full dump before --target datetime
#   2. Decrypts it using age private key
#   3. Stops the app containers (Drupal) to prevent writes during restore
#   4. Restores the dump into MariaDB (drops + recreates all databases)
#   5. Replays all binlogs from dump's binlog position up to --target
#   6. Restarts app containers
#
# WARNING: This is destructive. Run against a test/staging copy first.
# The --dry-run flag shows what would happen without executing steps 3–6.

set -euo pipefail

ACTOOLS_HOME="/home/actools"
COMPOSE_FILE="${ACTOOLS_HOME}/docker-compose.yml"
ENV_FILE="${ACTOOLS_HOME}/actools.env"
AGE_KEY_FILE="${ACTOOLS_HOME}/.age-key.txt"   # PRIVATE key (not public)
BACKUP_ROOT="${ACTOOLS_HOME}/backups/db"
BINLOG_ARCHIVE="${ACTOOLS_HOME}/backups/binlogs"
LOG_FILE="${ACTOOLS_HOME}/logs/pitr-restore.log"
WORK_DIR="/tmp/actools-pitr-$$"

# shellcheck source=/dev/null
source "${ENV_FILE}"

TARGET_DATETIME=""
DUMP_DATE=""
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 --target "YYYY-MM-DD HH:MM:SS" [--dump-date YYYY-MM-DD] [--dry-run]

  --target      Target datetime to restore to (required)
  --dump-date   Use dump from this specific date (default: auto-detect latest before target)
  --dry-run     Show what would happen without making changes

Example:
  $0 --target "2026-03-26 14:30:00"
  $0 --target "2026-03-26 14:30:00" --dry-run
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)     TARGET_DATETIME="$2"; shift 2 ;;
    --dump-date)  DUMP_DATE="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    *)            usage ;;
  esac
done

[[ -z "${TARGET_DATETIME}" ]] && usage

log() { echo "$(date -u +%FT%TZ) [pitr-restore] $*" | tee -a "${LOG_FILE}"; }
die() { log "ERROR: $*"; exit 1; }

log "======================================================"
log "PITR restore requested — target: ${TARGET_DATETIME}"
[[ "${DRY_RUN}" == "true" ]] && log "[DRY RUN — no changes will be made]"

# ── 1. Validate age private key ───────────────────────────────────────────────
[[ -f "${AGE_KEY_FILE}" ]] || die "age private key not found at ${AGE_KEY_FILE}"
[[ -r "${AGE_KEY_FILE}" ]] || die "age private key not readable — check permissions"

# ── 2. Find the most recent full dump before the target datetime ───────────────
TARGET_EPOCH=$(date -d "${TARGET_DATETIME}" +%s 2>/dev/null) \
  || die "Invalid target datetime format. Use: YYYY-MM-DD HH:MM:SS"

if [[ -n "${DUMP_DATE}" ]]; then
  DUMP_DIR="${BACKUP_ROOT}/${DUMP_DATE}"
  [[ -d "${DUMP_DIR}" ]] || die "No dump directory found for ${DUMP_DATE}"
else
  # Find most recent dump dir whose date is <= target date
  DUMP_DIR=""
  while IFS= read -r dir; do
    DIR_DATE=$(basename "${dir}")
    DIR_EPOCH=$(date -d "${DIR_DATE} 02:00:00" +%s 2>/dev/null || echo 0)
    if [[ "${DIR_EPOCH}" -le "${TARGET_EPOCH}" ]]; then
      DUMP_DIR="${dir}"
      break
    fi
  done < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort -r)
  [[ -n "${DUMP_DIR}" ]] || die "No full dump found before ${TARGET_DATETIME}"
fi

# Find the encrypted dump file in that dir
DUMP_FILE=$(find "${DUMP_DIR}" -name "full-dump-*.sql.gz.age" | sort | tail -1)
[[ -n "${DUMP_FILE}" ]] || die "No dump file found in ${DUMP_DIR}"
log "Using dump: ${DUMP_FILE}"

MANIFEST="${DUMP_DIR}/manifest.txt"
[[ -f "${MANIFEST}" ]] && log "Manifest:" && cat "${MANIFEST}" | tee -a "${LOG_FILE}"

# ── 3. Find binlog archives to replay ─────────────────────────────────────────
DUMP_DATE_STR=$(basename "${DUMP_DIR}")
log "Finding binlog archives from ${DUMP_DATE_STR} up to ${TARGET_DATETIME}..."

BINLOGS_TO_REPLAY=()
while IFS= read -r bf; do
  # Binlog archive filename: mysql-bin.NNNNNN.gz.age
  # We'll decrypt and replay all binlogs from dump date forward;
  # mysqlbinlog --stop-datetime handles the time boundary precisely.
  BF_DATE=$(stat -c %y "${bf}" | cut -d' ' -f1)
  BF_EPOCH=$(date -d "${BF_DATE}" +%s 2>/dev/null || echo 0)
  DUMP_EPOCH=$(date -d "${DUMP_DATE_STR}" +%s)
  if [[ "${BF_EPOCH}" -ge "${DUMP_EPOCH}" ]]; then
    BINLOGS_TO_REPLAY+=("${bf}")
  fi
done < <(find "${BINLOG_ARCHIVE}" -name "mysql-bin.*.gz.age" | sort)

log "Binlog archives to replay: ${#BINLOGS_TO_REPLAY[@]}"
for bl in "${BINLOGS_TO_REPLAY[@]}"; do
  log "  ${bl}"
done

if [[ "${DRY_RUN}" == "true" ]]; then
  log "--- DRY RUN complete ---"
  log "Would restore dump: ${DUMP_FILE}"
  log "Would replay ${#BINLOGS_TO_REPLAY[@]} binlog archive(s) up to ${TARGET_DATETIME}"
  log "No changes made."
  exit 0
fi

# ── 4. Prepare work directory ─────────────────────────────────────────────────
mkdir -p "${WORK_DIR}"
trap 'log "Cleaning up work dir..."; rm -rf "${WORK_DIR}"' EXIT

# ── 5. Decrypt the full dump ──────────────────────────────────────────────────
log "Decrypting dump..."
DECRYPTED_DUMP="${WORK_DIR}/full-dump.sql.gz"
age --decrypt -i "${AGE_KEY_FILE}" -o "${DECRYPTED_DUMP}" "${DUMP_FILE}"
log "Dump decrypted: $(du -sh "${DECRYPTED_DUMP}" | cut -f1)"

# ── 6. Stop Drupal app containers (prevent writes during restore) ──────────────
log "Stopping app containers..."
docker compose -f "${COMPOSE_FILE}" stop php_prod worker_prod 2>>"${LOG_FILE}" || true
log "App containers stopped"

# ── 7. Restore the full dump ──────────────────────────────────────────────────
log "Restoring full dump into MariaDB — this may take several minutes..."
zcat "${DECRYPTED_DUMP}" | docker compose -f "${COMPOSE_FILE}" exec -T db \
  mariadb --user=root --password="${DB_ROOT_PASS}" \
  2>>"${LOG_FILE}"
log "Full dump restored"

# ── 8. Extract binlog start position from dump header ─────────────────────────
# mysqldump --master-data=2 embeds a comment like:
#   -- CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000042', MASTER_LOG_POS=1234;
START_FILE=$(zcat "${DECRYPTED_DUMP}" | grep "^-- CHANGE MASTER" | \
  grep -oP "MASTER_LOG_FILE='[^']+'" | grep -oP "'[^']+'" | tr -d "'" || echo "")
START_POS=$(zcat "${DECRYPTED_DUMP}" | grep "^-- CHANGE MASTER" | \
  grep -oP "MASTER_LOG_POS=[0-9]+" | grep -oP "[0-9]+" || echo "4")

log "Dump binlog start position: file=${START_FILE} pos=${START_POS}"

# ── 9. Decrypt and replay binlogs ─────────────────────────────────────────────
if [[ "${#BINLOGS_TO_REPLAY[@]}" -gt 0 ]]; then
  log "Replaying ${#BINLOGS_TO_REPLAY[@]} binlog archive(s) up to ${TARGET_DATETIME}..."

  FIRST=true
  for BINLOG_ARCHIVE_FILE in "${BINLOGS_TO_REPLAY[@]}"; do
    BASENAME=$(basename "${BINLOG_ARCHIVE_FILE}" .gz.age)
    DECRYPTED_BINLOG="${WORK_DIR}/${BASENAME}"

    log "  Decrypting ${BASENAME}..."
    age --decrypt -i "${AGE_KEY_FILE}" \
      -o "${WORK_DIR}/${BASENAME}.gz" "${BINLOG_ARCHIVE_FILE}"
    gunzip -c "${WORK_DIR}/${BASENAME}.gz" > "${DECRYPTED_BINLOG}"
    rm "${WORK_DIR}/${BASENAME}.gz"

    # Build mysqlbinlog args
    MYSQLBINLOG_ARGS=("--stop-datetime=${TARGET_DATETIME}")

    # For the first binlog, start from the position recorded in the dump
    if [[ "${FIRST}" == "true" && -n "${START_FILE}" ]]; then
      if [[ "${BASENAME}" == "${START_FILE}" ]]; then
        MYSQLBINLOG_ARGS+=("--start-position=${START_POS}")
        FIRST=false
      else
        # This binlog predates dump start position — skip safely
        log "  Skipping ${BASENAME} (before dump start position)"
        rm -f "${DECRYPTED_BINLOG}"
        continue
      fi
    fi

    log "  Replaying ${BASENAME}..."
    docker compose -f "${COMPOSE_FILE}" exec -T db \
      bash -c "mysqlbinlog ${MYSQLBINLOG_ARGS[*]} /dev/stdin \
        | mariadb --user=root --password='${DB_ROOT_PASS}'" \
      < "${DECRYPTED_BINLOG}" 2>>"${LOG_FILE}"

    rm -f "${DECRYPTED_BINLOG}"
    log "  Replayed ${BASENAME}"
  done

  log "Binlog replay complete"
else
  log "No binlog archives to replay — restore is at full dump state"
fi

# ── 10. Restart app containers ────────────────────────────────────────────────
log "Restarting app containers..."
docker compose -f "${COMPOSE_FILE}" start php_prod worker_prod 2>>"${LOG_FILE}"
log "App containers started"

log "======================================================"
log "PITR restore COMPLETE — database restored to: ${TARGET_DATETIME}"
log "======================================================"
log "Next steps:"
log "  1. Verify Drupal is healthy: actools health"
log "  2. Check logs: actools logs php_prod --tail=50"
log "  3. Run smoke tests before re-enabling external traffic"
