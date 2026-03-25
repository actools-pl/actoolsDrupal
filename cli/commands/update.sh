#!/usr/bin/env bash
# =============================================================================
# cli/commands/update.sh — Update Command
# =============================================================================

cmd_update() {
  cd "$INSTALL_DIR"
  echo "Taking pre-update prod snapshot..."
  SNAP="${INSTALL_DIR}/backups/pre_update_prod_$(date +%F_%H%M%S).sql.gz"
  docker exec actools_db mariadb-dump --single-transaction --quick \
    -ubackup actools_prod \
    | gzip > "$SNAP" && echo "Snapshot: $SNAP" || echo "Snapshot failed (non-fatal)"
  docker compose pull db redis php_prod
  docker compose up -d
  docker compose exec -T php_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush updb --yes && ./vendor/bin/drush cr" \
    2>&1 || echo "drush updb failed -- check manually"
  docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
  echo "Update complete."
}
