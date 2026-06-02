#!/usr/bin/env bash
# =============================================================================
# cli/commands/update.sh — Update Command
# =============================================================================

# Container-exec mariadb-dump as the least-privilege 'backup' user, with the backup password
# fed via a transient 0600 defaults-file written from a heredoc on stdin (never on any argv).
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

cmd_update() {
  cd "$INSTALL_DIR"
  echo "Taking pre-update prod snapshot..."
  SNAP="${INSTALL_DIR}/backups/pre_update_prod_$(date +%F_%H%M%S).sql.gz"
  db_dump_container "${BACKUP_PASS}" --single-transaction --quick actools_prod \
    | gzip > "$SNAP" && echo "Snapshot: $SNAP" || echo "Snapshot failed (non-fatal)"
  docker compose pull db redis php_prod
  docker compose up -d
  docker compose exec -T php_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush updb --yes && ./vendor/bin/drush cr" \
    2>&1 || {
      echo "ERROR: drush updb failed for prod — update aborted before caddy reload"
      echo "Pre-update snapshot retained at: ${SNAP}"
      echo "Manual rollback: actools restore prod ${SNAP}"
      exit 1
    }
  docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
  echo "Update complete."
}
