#!/usr/bin/env bash
# =============================================================================
# modules/drupal/secure.sh — Stage 3: trusted_hosts + S3 + FPM + Ownership
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

drupal_secure() {
  local env="$1"

  section "Stage 3: Secure — ${env}"

  # Inject trusted_host_patterns
  local domain_escaped="${BASE_DOMAIN//./\\.}"
  docker compose exec -T "php_${env}" bash -c "
    cd /var/www/html/${env}
    ./vendor/bin/drush php:eval \"
      \\\$config_file = DRUPAL_ROOT . '/../sites/default/settings.php';
      \\\$trusted = ['^${domain_escaped}$', '^.*\\.${domain_escaped}$'];
      \\\$line = \\\"\\\\\\\$settings['trusted_host_patterns'] = \" . var_export(\\\$trusted, true) . \";\\\";
      file_put_contents(\\\$config_file, PHP_EOL . \\\$line, FILE_APPEND);
    \" 2>/dev/null || true
  " 2>/dev/null || warn "trusted_host_patterns injection failed for ${env} -- set manually in settings.php"

  # S3 settings injection
  if [[ "${ENABLE_S3_STORAGE:-false}" == "true" ]]; then
    log "Injecting S3 credentials into settings.php for ${env}..."
    docker compose exec -T "php_${env}" bash -c "
      CONFIG_FILE=/var/www/html/${env}/sites/default/settings.php
      cat >> \"\$CONFIG_FILE\" <<'SETTINGS'

// S3FS configuration -- injected by actools installer (v9.2)
\$config['s3fs.settings']['access_key']         = getenv('AWS_ACCESS_KEY_ID') ?: '';
\$config['s3fs.settings']['secret_key']         = getenv('AWS_SECRET_ACCESS_KEY') ?: '';
\$config['s3fs.settings']['bucket']             = getenv('S3_BUCKET') ?: '';
\$config['s3fs.settings']['region']             = getenv('AWS_REGION') ?: 'us-east-1';
\$config['s3fs.settings']['use_s3_for_public']  = TRUE;
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
    log "S3 settings injected for ${env}."
  fi

  # PHP-FPM slow log
  docker compose exec -T "php_${env}" bash -c "
    if [[ -f /usr/local/etc/php-fpm.d/www.conf ]]; then
      echo 'slowlog = /var/log/php/www-slow.log' >> /usr/local/etc/php-fpm.d/www.conf
      echo 'request_slowlog_timeout = 5s' >> /usr/local/etc/php-fpm.d/www.conf
      kill -USR2 1 2>/dev/null || true
    fi
  " 2>/dev/null || true

  # File ownership
  docker compose exec -T "php_${env}" bash -c "
    chown -R www-data:www-data /var/www/html/${env}/web/sites/default/files 2>/dev/null || true
  " 2>/dev/null || true
  chown -R "$REAL_USER:$REAL_USER" "${INSTALL_DIR}/docroot/${env}" 2>/dev/null || true

  # Save credentials
  mark_installed "$env"
  local db_pass
  db_pass=$(get_db_pass "$env")
  set_state ".db_passes.${env}=\"${db_pass}\""
  echo "[${env}] DB: actools_${env}  User: actools_${env}  Pass: ${db_pass}" \
    >> "$REAL_HOME/.actools-db-creds"
  chmod 600 "$REAL_HOME/.actools-db-creds" 2>/dev/null || true

  log "Stage 3 complete: ${env} secured and hardened."
}
