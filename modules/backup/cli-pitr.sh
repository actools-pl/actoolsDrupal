#!/usr/bin/env bash
# /home/actools/modules/backup/cli-pitr.sh
# Phase 4.5 Item 2 — actools CLI integration for PITR commands
#
# Source this file from the main /usr/local/bin/actools dispatcher,
# or copy the case blocks into the existing migrate/backup command handlers.
#
# Adds these CLI commands:
#   actools migrate --point-in-time "YYYY-MM-DD HH:MM:SS" [--dry-run]
#   actools backup db [--verify]
#   actools backup binlogs
#   actools backup status

ACTOOLS_HOME="/home/actools"
MODULES="${ACTOOLS_HOME}/modules/backup"

pitr_cli() {
  local subcmd="${1:-}"
  shift || true

  case "${subcmd}" in
    --point-in-time|-p)
      local target="${1:-}"
      [[ -z "${target}" ]] && {
        echo "Usage: actools migrate --point-in-time \"YYYY-MM-DD HH:MM:SS\" [--dry-run]"
        exit 1
      }
      shift
      echo "▶ Point-in-time recovery to: ${target}"
      echo "  This will RESTORE your database. Data after ${target} will be lost."
      echo ""
      read -r -p "  Type YES to confirm: " confirm
      [[ "${confirm}" == "YES" ]] || { echo "Aborted."; exit 0; }
      exec "${MODULES}/pitr-restore.sh" --target "${target}" "$@"
      ;;
    *)
      echo "Usage: actools migrate --point-in-time \"YYYY-MM-DD HH:MM:SS\" [--dry-run]"
      exit 1
      ;;
  esac
}

backup_cli() {
  local subcmd="${1:-status}"
  shift || true

  case "${subcmd}" in
    db)
      echo "▶ Running full database backup..."
      exec "${MODULES}/db-full-backup.sh" "$@"
      ;;
    binlogs)
      echo "▶ Rotating and archiving binary logs..."
      exec "${MODULES}/binlog-rotate.sh"
      ;;
    status)
      echo "── Database backup status ───────────────────────────"
      echo ""
      echo "Latest full dump:"
      LATEST_DUMP=$(find "${ACTOOLS_HOME}/backups/db" -name "*.sql.gz.age" \
        2>/dev/null | sort | tail -1)
      if [[ -n "${LATEST_DUMP}" ]]; then
        DUMP_DATE=$(stat -c %y "${LATEST_DUMP}" | cut -d'.' -f1)
        DUMP_SIZE=$(du -sh "${LATEST_DUMP}" | cut -f1)
        echo "  File: $(basename "${LATEST_DUMP}")"
        echo "  Date: ${DUMP_DATE}"
        echo "  Size: ${DUMP_SIZE}"
      else
        echo "  No dumps found — run: actools backup db"
      fi
      echo ""
      echo "Binlog archives:"
      BINLOG_COUNT=$(find "${ACTOOLS_HOME}/backups/binlogs" -name "*.gz.age" \
        2>/dev/null | wc -l)
      BINLOG_SIZE=$(du -sh "${ACTOOLS_HOME}/backups/binlogs" 2>/dev/null | cut -f1 || echo "0")
      echo "  Count: ${BINLOG_COUNT}"
      echo "  Total: ${BINLOG_SIZE}"
      LATEST_BINLOG=$(find "${ACTOOLS_HOME}/backups/binlogs" -name "*.gz.age" \
        2>/dev/null | sort | tail -1)
      if [[ -n "${LATEST_BINLOG}" ]]; then
        BINLOG_DATE=$(stat -c %y "${LATEST_BINLOG}" | cut -d'.' -f1)
        echo "  Latest: $(basename "${LATEST_BINLOG}") @ ${BINLOG_DATE}"
      fi
      echo ""
      echo "MariaDB binlog status:"
      docker compose -f "${ACTOOLS_HOME}/docker-compose.yml" exec -T db \
        mariadb --user=root --password="${DB_ROOT_PASS}" \
        -e "SHOW MASTER STATUS; SHOW BINARY LOGS;" 2>/dev/null \
        || echo "  (could not connect to MariaDB)"
      echo ""
      echo "Recent backup log (last 10 lines):"
      tail -10 "${ACTOOLS_HOME}/logs/backup-db.log" 2>/dev/null || echo "  No log yet"
      ;;
    *)
      echo "Usage: actools backup [db|binlogs|status]"
      exit 1
      ;;
  esac
}

# ── Integration instructions ──────────────────────────────────────────────────
#
# In /usr/local/bin/actools, add to the main case statement:
#
#   migrate)
#     shift
#     source /home/actools/modules/backup/cli-pitr.sh
#     pitr_cli "$@"
#     ;;
#
#   backup)
#     shift
#     source /home/actools/modules/backup/cli-pitr.sh
#     backup_cli "$@"
#     ;;
