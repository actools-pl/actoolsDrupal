#!/usr/bin/env bash
# =============================================================================
# modules/db/core.sh — the stateful DB layer (root exec, dump, backup user,
# readiness wait, credential probe)
#
# LIVE AUTHORITY (P0-M): carries the monolith's exact db_exec_root(),
# db_exec_root_stdin(), db_dump_container(), setup_backup_db_user(),
# wait_db() and check_db_creds() definitions, extracted VERBATIM from the
# inline v14 blocks in actools.sh (per-function byte-identity verified; the
# contract/mock tests in tests/db/ pinned the commands and SQL each function
# issues BEFORE the move and stayed green across it). Sourced by actools.sh
# on the live install path.
#
# The stale v9.2 twins modules/db/{backup_user,credentials,wait}.sh were
# retired at P0-M; their content (including a divergent check_db_creds error
# message and a wait_db with `cd || exit`) did NOT survive — the inline v14
# code below is authoritative.
#
# Required globals (set by actools.sh BEFORE these functions are called):
#   INSTALL_DIR   — install root (wait_db / check_db_creds `cd` here)
#   DB_ROOT_PASS  — DB root password (wait_db's readiness probe)
#
# Collaborators (must be defined when the functions RUN):
#   log/error — core/bootstrap.sh
#
# Functions only — no variable assignments — so the module is inert under
# `set -u` at source time.
# =============================================================================

# =============================================================================
# DB ACCESS HELPERS — remove password from host argv (3a)
# =============================================================================
# Run a root mariadb command inside the db container with no password on the host argv.
# The container already holds MARIADB_ROOT_PASSWORD; we expose it to the client as MYSQL_PWD
# *inside* the container. Caller passes mariadb args ($@), e.g. -e "..." or a heredoc on stdin.
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}

# Pipe-fed root mariadb (e.g. restore): stdin is the piped SQL; $1 is the target database.
# Password from container env (MYSQL_PWD); db name passed positionally. No password on host argv.
db_exec_root_stdin() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$1"' _ "$1"
}

# Backup-user dump inside the db container, least-privilege preserved.
# Password fed via a transient 0600 defaults-file written from a heredoc on stdin (never on any argv).
# $1 = backup password; remaining args = dump args (db name, --single-transaction, etc.).
# Caller pipes stdout to gzip as before.
db_dump_container() {
  local _bp="$1"; shift
  docker exec -i actools_db sh -c '
    umask 077
    tmp="$(mktemp /tmp/actools-dump.XXXXXX.cnf)"
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp"
    mariadb-dump --defaults-extra-file="$tmp" "$@"
  ' _ "$@" <<EOF
[mariadb-dump]
user=backup
password=${_bp}
EOF
}

# =============================================================================
# BACKUP DB USER
# =============================================================================
setup_backup_db_user() {
  local backup_pass="$1"
  wait_db
  # [v9.2 fix1] Use mariadb client (mysql removed in MariaDB 11.4)
  db_exec_root <<SQL
CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY '${backup_pass}';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* TO 'backup'@'%';
FLUSH PRIVILEGES;
SQL
  log "DB backup user created."
}

# =============================================================================
# WAIT FOR DB
# [v9.2 fix4] Rewritten without timeout+subshell -- DB_ROOT_PASS was unbound
#             under set -u when passed into a spawned bash -c process.
# =============================================================================
wait_db() {
  cd "$INSTALL_DIR"
  log "Waiting for MariaDB (write-check)..."
  local _wp="${DB_ROOT_PASS}"
  local _tries=0
  until docker compose exec -T db mariadb -uroot -p"${_wp}" \
    -e "CREATE TABLE IF NOT EXISTS mysql.actools_write_check (id INT); DROP TABLE IF EXISTS mysql.actools_write_check;" \
    &>/dev/null 2>&1; do
    _tries=$(( _tries + 1 ))
    [[ $_tries -ge 50 ]] && error "MariaDB did not become ready within 150s."
    sleep 3
  done
  log "MariaDB ready."
}

# =============================================================================
# DB CREDENTIAL PROBE
# =============================================================================
check_db_creds() {
  cd "$INSTALL_DIR"
  db_exec_root -e "SELECT 1;" &>/dev/null 2>&1 \
    || error "Cannot authenticate to MariaDB with current DB_ROOT_PASS.
  Revert DB_ROOT_PASS in actools.env to the previously generated value, or:
  docker compose exec db mariadb -uroot -p<old_pass> -e \"ALTER USER 'root'@'%' IDENTIFIED BY '<new_pass>';\""
  log "DB credentials verified."
}
