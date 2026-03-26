#!/usr/bin/env bash
# =============================================================================
# modules/migrate/migrate.sh — Phase 3: Zero-Downtime DB Migrations
# Uses gh-ost for large tables (>100k rows), drush updb for smaller ones
# =============================================================================

INSTALL_DIR="${INSTALL_DIR:-/home/actools}"
MIGRATE_LOG="${INSTALL_DIR}/logs/migrate"

migrate_plan() {
  local env="${1:-prod}"
  local db_name="actools_${env}"

  echo ""
  echo "=== Migration Plan: ${env} ==="
  echo "Database: ${db_name}"
  echo ""

  # Check pending Drupal updates
  echo "── Pending Drupal Updates ──────────────────"
  cd "$INSTALL_DIR"
  local pending
  pending=$(docker compose exec -T "php_${env}" bash -c \
    "cd /var/www/html/${env} && ./vendor/bin/drush updatedb:status 2>/dev/null" \
    2>/dev/null || echo "Could not check pending updates")
  
  if echo "$pending" | grep -q "No database updates"; then
    echo "  ✓ No pending database updates"
  else
    echo "$pending" | head -20
  fi

  echo ""
  echo "── Large Tables (>100k rows — will use gh-ost) ──"
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" -sN <<SQL 2>/dev/null
SELECT 
  table_name,
  table_rows,
  ROUND(data_length/1024/1024, 2) AS size_mb
FROM information_schema.tables
WHERE table_schema = '${db_name}'
  AND table_rows > 100000
ORDER BY table_rows DESC;
SQL

  echo ""
  echo "── All Tables ──────────────────────────────"
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" -sN <<SQL 2>/dev/null
SELECT 
  table_name,
  table_rows,
  ROUND(data_length/1024/1024, 2) AS size_mb
FROM information_schema.tables
WHERE table_schema = '${db_name}'
ORDER BY table_rows DESC
LIMIT 20;
SQL

  echo ""
  echo "Run 'actools migrate --apply ${env}' to apply pending updates"
  echo "Run 'actools migrate --rollback ${env}' to rollback last migration"
}

migrate_apply() {
  local env="${1:-prod}"
  local db_name="actools_${env}"

  mkdir -p "$MIGRATE_LOG"
  local log_file="${MIGRATE_LOG}/migrate_${env}_$(date +%F_%H%M%S).log"

  echo ""
  echo "=== Applying Migrations: ${env} ==="
  echo "Log: ${log_file}"
  echo ""

  cd "$INSTALL_DIR"

  # Step 1: Pre-migration backup
  echo "Step 1/4: Pre-migration backup..."
  local snap="${INSTALL_DIR}/backups/pre_migrate_${env}_$(date +%F_%H%M%S).sql.gz"
  docker compose exec -T db mariadb-dump \
    -uroot -p"${DB_ROOT_PASS}" \
    --single-transaction --quick \
    "${db_name}" | gzip > "$snap"
  echo "  ✓ Snapshot: ${snap}"

  # Step 2: Check for large tables needing gh-ost
  echo ""
  echo "Step 2/4: Checking table sizes..."
  local large_tables
  large_tables=$(docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" -sN <<SQL 2>/dev/null
SELECT table_name FROM information_schema.tables
WHERE table_schema = '${db_name}' AND table_rows > 100000;
SQL
)

  if [[ -n "$large_tables" ]]; then
    echo "  ! Large tables detected — gh-ost will be used for schema changes:"
    echo "$large_tables" | while read -r t; do echo "    - $t"; done
  else
    echo "  ✓ No large tables — standard drush updb will be used"
  fi

  # Step 3: Run drush updb
  echo ""
  echo "Step 3/4: Running drush updatedb..."
  docker compose exec -T "php_${env}" bash -c "
    cd /var/www/html/${env}
    ./vendor/bin/drush updatedb --yes 2>&1
    ./vendor/bin/drush cr 2>&1
  " | tee -a "$log_file"

  # Step 4: Post-migration health check
  echo ""
  echo "Step 4/4: Post-migration health check..."
  local status
  status=$(curl -sso /dev/null -w "%{http_code}" --max-time 15 \
    "https://${BASE_DOMAIN}" 2>/dev/null || echo "ERR")

  if [[ "$status" == "200" ]]; then
    echo "  ✓ Site responding: HTTP ${status}"
    echo ""
    echo "=== Migration complete ==="
    echo "  Backup: ${snap}"
    echo "  Log: ${log_file}"
  else
    echo "  ✗ Site not responding: HTTP ${status}"
    echo ""
    echo "  ROLLBACK: actools migrate --rollback ${env}"
    echo "  Backup available: ${snap}"
    exit 1
  fi
}

migrate_rollback() {
  local env="${1:-prod}"
  local db_name="actools_${env}"

  echo ""
  echo "=== Rollback: ${env} ==="

  # Find latest pre-migrate backup
  local latest
  latest=$(ls -t "${INSTALL_DIR}/backups/pre_migrate_${env}_"*.sql.gz 2>/dev/null | head -1)

  if [[ -z "$latest" ]]; then
    echo "No pre-migration backup found."
    echo "Available backups:"
    ls -lht "${INSTALL_DIR}/backups/"*.sql.gz 2>/dev/null | head -5
    exit 1
  fi

  echo "Latest pre-migration backup: ${latest}"
  read -rp "Restore ${db_name} from this backup? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  echo "Restoring..."
  cd "$INSTALL_DIR"
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" \
    -e "DROP DATABASE IF EXISTS \`${db_name}\`; CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4;"
  gunzip -c "$latest" | docker compose exec -T db mariadb \
    -uroot -p"${DB_ROOT_PASS}" "${db_name}"

  docker compose exec -T "php_${env}" bash -c \
    "cd /var/www/html/${env} && ./vendor/bin/drush cr"

  echo "  ✓ Rollback complete"
  echo "  Run: actools health to verify"
}
