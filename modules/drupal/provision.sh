#!/usr/bin/env bash
# =============================================================================
# modules/drupal/provision.sh — Stage 2: Drupal Install + Configuration
# Called by install_env() in actools.sh after DB is created
# =============================================================================
drupal_provision() {
  local env="$1"
  local php_svc="php_${env}"
  local db_name="actools_${env}"
  local db_pass
  db_pass=$(get_db_pass "$env")


  # Resolve Drupal version constraint
  # Supports: 11 (latest 11.x) | 11.3 (latest 11.3.x) | 11.3.5 (exact)
  local DV="${DRUPAL_VERSION:-11}"
  local DRUPAL_CONSTRAINT
  if [[ "$DV" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    DRUPAL_CONSTRAINT="$DV"
    log "Drupal version: exact ${DV}"
  elif [[ "$DV" =~ ^[0-9]+\.[0-9]+$ ]]; then
    DRUPAL_CONSTRAINT="~${DV}"
    log "Drupal version: latest ${DV}.x"
  else
    DRUPAL_CONSTRAINT="^${DV}"
    log "Drupal version: latest ${DV}.x.x"
  fi

  log "Composing Drupal ${DV} for ${env}..."
  docker compose exec -T "$php_svc" bash -c "
    export COMPOSER_PROCESS_TIMEOUT=${COMPOSER_PROCESS_TIMEOUT:-600}
    set -euo pipefail
    mkdir -p /var/www/html/${env}
    cd /var/www/html/${env}

    if ! command -v composer &>/dev/null; then
      curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi

    if [[ ! -f composer.json ]]; then
      composer create-project drupal/recommended-project:${DRUPAL_CONSTRAINT} . --no-interaction
      composer require drush/drush --no-interaction
      composer require drupal/redis --no-interaction
    fi

    EXTRA='${EXTRA_PACKAGES:-}'
    [[ -n \"\$EXTRA\" ]] && composer require \$EXTRA --no-interaction || true
  "

  if [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]]; then
    log "Installing S3FS module for ${env}..."
    docker compose exec -T "$php_svc" bash -c "
      cd /var/www/html/${env}
      composer require drupal/s3fs --no-interaction
      ./vendor/bin/drush en s3fs --yes 2>/dev/null || true
    " 2>/dev/null || warn "S3FS installation failed -- configure manually after install"
  fi

  docker compose exec -T "$php_svc" bash -c \
    "apt-get update -qq && apt-get install -y -qq default-mysql-client 2>/dev/null || true" \
    2>/dev/null || true

  log "drush site:install for ${env}..."
  docker compose exec -T "$php_svc" bash -c "
    set -euo pipefail
    cd /var/www/html/${env}
    ./vendor/bin/drush site:install standard \
      --db-url=mysql://${db_name}:${db_pass}@db/${db_name} \
      --account-name=${DRUPAL_ADMIN_USER:-admin} \
      --account-pass=${DRUPAL_ADMIN_PASS} \
      --account-mail=${DRUPAL_ADMIN_EMAIL} \
      --site-name='${SITE_NAME:-AcTools}' \
      --yes
    ./vendor/bin/drush cr
  "

  local domain_escaped="${BASE_DOMAIN//./\\.}"
  docker compose exec -T "$php_svc" bash -c "cat > /tmp/php_inject.php << 'PHPEOF'
\$settings['trusted_host_patterns'] = array('^${domain_escaped}\$', '^.*\\.${domain_escaped}\$');
// trusted_host_patterns_active
PHPEOF
grep -q trusted_host_patterns_active /opt/drupal/web/${env}/web/sites/default/settings.php 2>/dev/null || cat /tmp/php_inject.php >> /opt/drupal/web/${env}/web/sites/default/settings.php
rm -f /tmp/php_inject.php" 2>/dev/null && log "trusted_host_patterns set for ${env}" || warn "trusted_host_patterns injection failed for ${env}"
  docker compose exec -T "$php_svc" bash -c "
cat > /tmp/php_inject2.php << 'PHPEOF'
\$settings['file_private_path'] = '/opt/drupal/web/${env}/private';
// file_private_path_active
PHPEOF
grep -q file_private_path_active /opt/drupal/web/${env}/web/sites/default/settings.php 2>/dev/null || cat /tmp/php_inject2.php >> /opt/drupal/web/${env}/web/sites/default/settings.php
rm -f /tmp/php_inject2.php" 2>/dev/null && log "file_private_path set for ${env}" || warn "file_private_path injection failed for ${env}"
  docker compose exec -T "$php_svc" mkdir -p /opt/drupal/web/${env}/private 2>/dev/null || true
  docker compose exec -T "$php_svc" bash -c "cd /opt/drupal/web/${env} && ./vendor/bin/drush cr" 2>/dev/null && log "Cache rebuilt after settings injection for ${env}" || true

  if [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]]; then
    log "Injecting S3 credentials into settings.php for ${env}..."
    docker compose exec -T "$php_svc" bash -c "
      CONFIG_FILE=/opt/drupal/web/${env}/web/sites/default/settings.php
      cat >> \"\$CONFIG_FILE\" <<'SETTINGS'

// S3FS configuration -- injected by actools installer (v9.2).
\$config['s3fs.settings']['access_key']        = getenv('AWS_ACCESS_KEY_ID') ?: '';
\$config['s3fs.settings']['secret_key']        = getenv('AWS_SECRET_ACCESS_KEY') ?: '';
\$config['s3fs.settings']['bucket']            = getenv('S3_BUCKET') ?: '';
\$config['s3fs.settings']['region']            = getenv('AWS_REGION') ?: 'us-east-1';
\$config['s3fs.settings']['use_s3_for_public'] = TRUE;
\$config['s3fs.settings']['use_s3_for_private'] = TRUE;

\$_s3_endpoint = getenv('S3_ENDPOINT_URL');
if (!empty(\$_s3_endpoint)) {
  \$config['s3fs.settings']['use_customhost'] = TRUE;
  \$config['s3fs.settings']['hostname']       = \$_s3_endpoint;
}

\$_cdn_host = getenv('ASSET_CDN_HOST');
if (!empty(\$_cdn_host)) {
  \$config['s3fs.settings']['use_cname'] = TRUE;
  \$config['s3fs.settings']['domain']    = \$_cdn_host;
}
SETTINGS
    " 2>/dev/null || warn "S3 settings.php injection failed for ${env}"
    log "S3 settings.php injection complete for ${env} (provider: ${STORAGE_PROVIDER})"
    [[ -n "${ASSET_CDN_HOST:-}" ]] && log "CDN: ${ASSET_CDN_HOST}"
    [[ -n "${S3_ENDPOINT_URL:-}" ]] && log "Endpoint: ${S3_ENDPOINT_URL}"
  fi

  docker compose exec -T "$php_svc" bash -c "
    if [[ -f /usr/local/etc/php-fpm.d/www.conf ]]; then
      echo 'slowlog = /var/log/php/www-slow.log' >> /usr/local/etc/php-fpm.d/www.conf
      echo 'request_slowlog_timeout = 5s' >> /usr/local/etc/php-fpm.d/www.conf
      kill -USR2 1 2>/dev/null || true
    fi
  " 2>/dev/null || true

  docker compose exec -T "$php_svc" bash -c "
    chown -R www-data:www-data /var/www/html/${env}/web/sites/default/files 2>/dev/null || true
  " 2>/dev/null || true
  chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR/docroot/${env}" 2>/dev/null || true
  if id www-data &>/dev/null; then
    chown -R www-data:www-data "$INSTALL_DIR/docroot/${env}/web/sites/default/files" 2>/dev/null || true
    chown -R www-data:www-data "$INSTALL_DIR/docroot/${env}/private" 2>/dev/null || true
  fi

  # Inject Redis cache and session settings using same pattern as trusted_host
  docker compose exec -T "$php_svc" bash -c "
    CONFIG_FILE=/opt/drupal/web/${env}/web/sites/default/settings.php
    if ! grep -q redis_cache_active \"\$CONFIG_FILE\" 2>/dev/null; then
      cd /opt/drupal/web/${env} && ./vendor/bin/drush en redis --yes 2>/dev/null || true
      cat >> \"\$CONFIG_FILE\" << 'PHPEOF'

// Redis cache backend - injected by actools installer
// redis_cache_active
\$settings['redis.connection']['interface'] = 'PhpRedis';
\$settings['redis.connection']['host'] = 'redis';
\$settings['redis.connection']['port'] = 6379;
\$settings['cache']['default'] = 'cache.backend.redis';
\$settings['cache']['bins']['bootstrap'] = 'cache.backend.chainedfast';
\$settings['cache']['bins']['discovery'] = 'cache.backend.chainedfast';
\$settings['cache']['bins']['config'] = 'cache.backend.chainedfast';
// Session cookie security - injected by actools installer
ini_set('session.cookie_secure', TRUE);
\$settings['session_write_interval'] = 180;
PHPEOF
      ./vendor/bin/drush cr 2>/dev/null || true
    fi
  " 2>/dev/null && log "Redis cache and session settings injected for ${env}" || warn "Redis injection failed for ${env}"

}
