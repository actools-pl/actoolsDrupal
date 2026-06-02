#!/usr/bin/env bash
# =============================================================================
# modules/db/credentials.sh — DB Credential Management
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

# Run a root mariadb command inside the db container with no password on the host argv.
# The container already holds MARIADB_ROOT_PASSWORD; we expose it to the client as MYSQL_PWD
# *inside* the container. Caller passes mariadb args ($@), e.g. -e "..." or a heredoc on stdin.
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}



check_db_creds() {
  cd "$INSTALL_DIR" || exit
  db_exec_root \
    -e "SELECT 1;" &>/dev/null 2>&1 \
    || error "Cannot authenticate to MariaDB with current DB_ROOT_PASS.
  Check DB_ROOT_PASS in actools.env matches the running container."
  log "DB credentials verified."
}

create_db_and_user() {
  local env="$1"
  local db_name="actools_${env}"
  local db_pass
  db_pass=$(get_db_pass "$env")

  db_exec_root <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_name}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_name}'@'%';
FLUSH PRIVILEGES;
SQL
  log "Database and user created for ${env}."
}
