#!/usr/bin/env bash
# =============================================================================
# modules/drupal/provision.sh — Stage 2: Composer + Drupal Site Install
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

drupal_provision() {
  local env="$1"
  local db_name="actools_${env}"
  local db_pass
  db_pass=$(get_db_pass "$env")

  section "Stage 2: Provision — ${env}"

  # Install mysql client for drush DB operations
  docker compose exec -T "php_${env}" bash -c \
    "apt-get update -qq && apt-get install -y -qq default-mysql-client 2>/dev/null || true" \
    2>/dev/null || true

  # Composer + Drupal
  log "Composing Drupal ${DRUPAL_VERSION} for ${env}..."
  docker compose exec -T "php_${env}" bash -c "
    export COMPOSER_PROCESS_TIMEOUT=${COMPOSER_PROCESS_TIMEOUT:-600}
    set -euo pipefail
    mkdir -p /var/www/html/${env}
    cd /var/www/html/${env}

    if ! command -v composer &>/dev/null; then
      curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi

    if [[ ! -f composer.json ]]; then
      composer create-project drupal/recommended-project:^${DRUPAL_VERSION} . --no-interaction
      composer require drush/drush --no-interaction
    fi

    EXTRA='${EXTRA_PACKAGES:-}'
    [[ -n \"\$EXTRA\" ]] && composer require \$EXTRA --no-interaction || true
  "

  # Drush site install
  log "drush site:install for ${env}..."
  docker compose exec -T "php_${env}" bash -c "
    set -euo pipefail
    cd /var/www/html/${env}
    ./vendor/bin/drush site:install standard \
      --db-url=mysql://${db_name}:${db_pass}@db/${db_name} \
      --account-name=${DRUPAL_ADMIN_USER:-admin} \
      --account-pass=${DRUPAL_ADMIN_PASS} \
      --account-mail=${DRUPAL_ADMIN_EMAIL} \
      --site-name='AcTools ${env^}' \
      --yes
    ./vendor/bin/drush cr

    # File system permissions
    chown -R www-data:www-data web/sites/default/files
    chmod 775 web/sites/default/files
    mkdir -p private
    chown -R www-data:www-data private
    chmod 775 private
    ./vendor/bin/drush php:eval "\Drupal::service('config.factory')->getEditable('system.file')->set('path.private', '/var/www/html/${env}/private')->save();"
    ./vendor/bin/drush php:eval "\Drupal\user\Entity\Role::load('administrator')->set('is_admin', TRUE)->save();"
    ./vendor/bin/drush cr
  "

  log "Stage 2 complete: Drupal provisioned for ${env}."
}
