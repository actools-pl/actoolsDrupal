#!/usr/bin/env bash
# =============================================================================
# modules/stack/mycnf.sh — MariaDB my.cnf Generation
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact my.cnf generation logic,
# extracted verbatim from actools.sh setup_stack(). Sourced by actools.sh and
# called by setup_stack (and, in tests, by the golden-capture harness). The
# buffer-pool size derives from ${INNODB_BUFFER_POOL:-1G} (env-default, NOT
# RAM-derived — this matches the current monolith).
# =============================================================================

generate_mycnf() {
  local innodb_buf="${INNODB_BUFFER_POOL:-1G}"
  local innodb_log="${INNODB_LOG_FILE_SIZE:-256M}"
  local max_conn="${MARIADB_MAX_CONNECTIONS:-100}"

  cat > "$INSTALL_DIR/my.cnf" <<MYCNF
[mysqld]
innodb_buffer_pool_size = ${innodb_buf}
innodb_log_file_size    = ${innodb_log}
max_connections         = ${max_conn}
innodb_flush_log_at_trx_commit = 1
slow_query_log          = 1
slow_query_log_file     = /var/log/mysql/slow.log
long_query_time         = 2
MYCNF
}
