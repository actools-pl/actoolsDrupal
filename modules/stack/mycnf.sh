#!/usr/bin/env bash
# =============================================================================
# modules/stack/mycnf.sh — MariaDB my.cnf Generation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
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
  log "my.cnf generated."
}
