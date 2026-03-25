#!/usr/bin/env bash
# =============================================================================
# modules/worker/queue.sh — Queue Worker Configuration
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

worker_status() {
  cd "$INSTALL_DIR"
  docker compose exec worker_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush queue:list" \
    2>/dev/null || warn "Worker container not ready or drush not installed yet."
}

worker_run() {
  cd "$INSTALL_DIR"
  log "Running queue worker manually on prod..."
  docker compose exec worker_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush queue:run actools_document_export"
}
