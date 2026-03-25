#!/usr/bin/env bash
# =============================================================================
# cli/commands/worker.sh — Worker Commands
# =============================================================================

cmd_worker_logs() {
  cd "$INSTALL_DIR"
  docker compose logs -f worker_prod
}

cmd_worker_status() {
  cd "$INSTALL_DIR"
  docker compose exec worker_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush queue:list"
}

cmd_worker_run() {
  cd "$INSTALL_DIR"
  log "Running queue worker manually on prod..."
  docker compose exec worker_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush queue:run actools_document_export"
}

cmd_pdf_test() {
  cd "$INSTALL_DIR"
  echo "=== XeLaTeX Test (inside worker container) ==="
  docker compose exec worker_prod xelatex --version 2>/dev/null \
    && echo "XeLaTeX: OK" \
    || echo "XeLaTeX: FAILED -- rebuild: docker build -t actools_worker:latest -f ~/Dockerfile.worker ~/"
  docker inspect actools_worker_prod \
    --format='  Health: {{.State.Health.Status}}' 2>/dev/null \
    || echo "  (container not running)"
}
