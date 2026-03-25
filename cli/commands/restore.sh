#!/usr/bin/env bash
# =============================================================================
# cli/commands/restore.sh — Restore Commands
# =============================================================================

cmd_restore_test() {
  cd "$INSTALL_DIR"
  LATEST=$(ls -t "${INSTALL_DIR}/backups"/prod_db_*.sql.gz 2>/dev/null | head -1)
  [[ -z "$LATEST" ]] && { echo "No prod DB backups found"; exit 1; }
  echo "Testing DB restore: $LATEST"
  sha256sum -c "$LATEST.sha256" && echo "Checksum OK" || { echo "CHECKSUM FAILED"; exit 1; }
  docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" \
    -e "CREATE DATABASE IF NOT EXISTS actools_restore_test CHARACTER SET utf8mb4;"
  gunzip -c "$LATEST" | docker exec -i actools_db mariadb \
    -uroot -p"${DB_ROOT_PASS}" actools_restore_test
  TC=$(docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN \
    -e "SELECT count(*) FROM information_schema.tables WHERE table_schema='actools_restore_test';")
  docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" \
    -e "DROP DATABASE IF EXISTS actools_restore_test;"
  echo "DB restore test OK -- ${TC} tables restored."
}

cmd_restore() {
  cd "$INSTALL_DIR"
  local env="${1:-prod}"
  local db="actools_${env}"
  local BACKUP_FILE="${2:-}"
  [[ -z "$BACKUP_FILE" ]] && \
    BACKUP_FILE=$(ls -t "${INSTALL_DIR}/backups/${env}_db_"*.sql.gz 2>/dev/null | head -1)
  [[ -z "$BACKUP_FILE" ]] && { echo "No backups found for $env"; exit 1; }
  echo "Restoring $env from: $BACKUP_FILE"
  sha256sum -c "$BACKUP_FILE.sha256" 2>/dev/null && echo "Checksum OK" \
    || echo "WARNING: no checksum file"
  read -rp "OVERWRITE actools_${env}? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" \
    -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET utf8mb4;"
  gunzip -c "$BACKUP_FILE" | docker exec -i actools_db mariadb \
    -uroot -p"${DB_ROOT_PASS}" "$db"
  echo "Restore complete. Run: actools drush $env cr"
}
