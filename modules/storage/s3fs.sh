#!/usr/bin/env bash
# =============================================================================
# modules/storage/s3fs.sh — S3FS Module Installation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

install_s3fs() {
  local env="$1"

  if [[ "${ENABLE_S3_STORAGE:-false}" == "true" ]]; then
    log "Installing S3FS module for ${env}..."
    docker compose exec -T "php_${env}" bash -c "
      cd /var/www/html/${env}
      composer require drupal/s3fs --no-interaction
      ./vendor/bin/drush en s3fs --yes 2>/dev/null || true
    " 2>/dev/null || warn "S3FS installation failed -- configure manually after install"
    log "S3FS installed for ${env}."
  fi
}
