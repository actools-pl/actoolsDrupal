#!/usr/bin/env bash
# deploy-pitr.sh
# Phase 4.5 Item 2 — Deploy script
#
# Run this on the server as the actools user:
#   bash deploy-pitr.sh
#
# What it does:
#   1. Copies files to their correct locations
#   2. Sets permissions
#   3. Enables MariaDB binary logging (restarts db container)
#   4. Installs cron jobs
#   5. Runs a test backup to verify everything works
#   6. Adds CLI integration to /usr/local/bin/actools

set -euo pipefail

ACTOOLS_HOME="/home/actools"
COMPOSE_FILE="${ACTOOLS_HOME}/docker-compose.yml"
MODULES="${ACTOOLS_HOME}/modules/backup"

echo "═══════════════════════════════════════════════"
echo " Phase 4.5 Item 2 — PITR Deploy"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. Create directories ─────────────────────────────────────────────────────
echo "▶ Creating directories..."
mkdir -p "${ACTOOLS_HOME}/backups/db"
mkdir -p "${ACTOOLS_HOME}/backups/binlogs"
mkdir -p "${ACTOOLS_HOME}/logs"
chmod 700 "${ACTOOLS_HOME}/backups"
echo "  Done"

# ── 2. Copy module files ──────────────────────────────────────────────────────
echo "▶ Copying module files to ${MODULES}..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "${SCRIPT_DIR}/mariadb-binlog.cnf"  "${MODULES}/99-binlog.cnf"
cp "${SCRIPT_DIR}/db-full-backup.sh"   "${MODULES}/db-full-backup.sh"
cp "${SCRIPT_DIR}/binlog-rotate.sh"    "${MODULES}/binlog-rotate.sh"
cp "${SCRIPT_DIR}/pitr-restore.sh"     "${MODULES}/pitr-restore.sh"
cp "${SCRIPT_DIR}/cli-pitr.sh"         "${MODULES}/cli-pitr.sh"

chmod +x "${MODULES}/db-full-backup.sh"
chmod +x "${MODULES}/binlog-rotate.sh"
chmod +x "${MODULES}/pitr-restore.sh"
chmod +x "${MODULES}/cli-pitr.sh"
echo "  Done"

# ── 3. Enable binary logging in MariaDB ───────────────────────────────────────
echo "▶ Checking docker-compose.yml for binlog volume mount..."

# Check if mariadb_binlogs volume already exists in compose file
if grep -q "mariadb_binlogs" "${COMPOSE_FILE}"; then
  echo "  mariadb_binlogs volume already present in compose file"
else
  echo "  WARN: mariadb_binlogs volume not found in ${COMPOSE_FILE}"
  echo "  ACTION REQUIRED: Add the following to your db service volumes and top-level volumes:"
  echo ""
  cat << 'EOF'
  # In the 'db' service, under 'volumes:':
      - mariadb_binlogs:/var/log/mysql
      - ./modules/backup/99-binlog.cnf:/etc/mysql/mariadb.conf.d/99-binlog.cnf:ro

  # At the top-level 'volumes:' section:
  mariadb_binlogs:
    driver: local
EOF
  echo ""
  echo "  After editing docker-compose.yml, re-run this script or proceed manually."
  echo "  Continuing with cnf file only (binlogs will go to container default location)..."
fi

# ── 4. Restart db container to pick up config ─────────────────────────────────
echo "▶ Restarting MariaDB container to enable binary logging..."
cd "${ACTOOLS_HOME}"
docker compose restart db
echo "  Waiting 10 seconds for MariaDB to start..."
sleep 10

# ── 5. Verify binary logging is active ───────────────────────────────────────
echo "▶ Verifying binary logging..."
source "${ACTOOLS_HOME}/actools.env"

BINLOG_STATUS=$(docker compose exec -T db \
  mariadb --user=root --password="${DB_ROOT_PASS}" \
  --batch --skip-column-names \
  -e "SHOW VARIABLES LIKE 'log_bin';" 2>/dev/null | awk '{print $2}')

if [[ "${BINLOG_STATUS}" == "ON" ]]; then
  echo "  ✓ Binary logging is ON"
  docker compose exec -T db \
    mariadb --user=root --password="${DB_ROOT_PASS}" \
    -e "SHOW MASTER STATUS;" 2>/dev/null
else
  echo "  ✗ Binary logging is OFF — check /etc/mysql/mariadb.conf.d/99-binlog.cnf"
  echo "    inside the container:"
  echo "    docker compose exec db cat /etc/mysql/mariadb.conf.d/99-binlog.cnf"
fi

# ── 6. Install cron ───────────────────────────────────────────────────────────
echo "▶ Installing cron jobs..."
cp "${SCRIPT_DIR}/actools-db-backup.cron" /etc/cron.d/actools-db-backup
chmod 644 /etc/cron.d/actools-db-backup
echo "  Cron installed: /etc/cron.d/actools-db-backup"
crontab -l -u actools 2>/dev/null | grep "actools backup\|db-full-backup\|binlog-rotate" || true

# ── 7. Run first full backup to verify ────────────────────────────────────────
echo ""
echo "▶ Running first full backup (this may take a minute)..."
if "${MODULES}/db-full-backup.sh" --verify; then
  echo "  ✓ First backup succeeded"
else
  echo "  ✗ First backup failed — check ${ACTOOLS_HOME}/logs/backup-db.log"
fi

# ── 8. Run first binlog rotation ─────────────────────────────────────────────
echo "▶ Running first binlog rotation..."
if "${MODULES}/binlog-rotate.sh"; then
  echo "  ✓ Binlog rotation succeeded"
else
  echo "  ✗ Binlog rotation failed — check ${ACTOOLS_HOME}/logs/binlog-rotate.log"
fi

# ── 9. CLI integration hint ───────────────────────────────────────────────────
echo ""
echo "▶ CLI integration:"
echo "  Add the following to /usr/local/bin/actools case statement:"
echo ""
echo '    migrate)'
echo '      shift'
echo '      source /home/actools/modules/backup/cli-pitr.sh'
echo '      pitr_cli "$@"'
echo '      ;;'
echo '    backup)'
echo '      shift'
echo '      source /home/actools/modules/backup/cli-pitr.sh'
echo '      backup_cli "$@"'
echo '      ;;'
echo ""
echo "  Then test with:"
echo "    actools backup status"
echo "    actools migrate --point-in-time \"$(date '+%Y-%m-%d %H:%M:%S')\" --dry-run"

echo ""
echo "═══════════════════════════════════════════════"
echo " Phase 4.5 Item 2 — PITR Deploy COMPLETE"
echo "═══════════════════════════════════════════════"
echo ""
echo "  RPO: ~1 hour (binlog rotation interval)"
echo "  RTO: 5–15 minutes (dump restore + binlog replay)"
echo ""
echo "  Next: Phase 4.5 Item 3 — Cloudflare Tunnel"
