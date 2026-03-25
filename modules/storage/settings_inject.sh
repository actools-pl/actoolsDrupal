#!/usr/bin/env bash
# =============================================================================
# modules/storage/settings_inject.sh — S3 settings.php Injection
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

inject_s3_settings() {
  local env="$1"

  log "Injecting S3 credentials into settings.php for ${env}..."
  docker compose exec -T "php_${env}" bash -c "
    CONFIG_FILE=/var/www/html/${env}/sites/default/settings.php
    cat >> \"\$CONFIG_FILE\" <<'SETTINGS'

// S3FS configuration -- injected by actools installer (v9.2)
// Credentials read from container env vars. Never in config export.
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
  log "S3 settings injected for ${env} (provider: ${STORAGE_PROVIDER})."
}
