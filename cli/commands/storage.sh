#!/usr/bin/env bash
# =============================================================================
# cli/commands/storage.sh — Storage Commands
# =============================================================================

cmd_storage_test() {
  cd "$INSTALL_DIR"
  echo "=== S3 Storage Round-Trip Test ==="
  docker compose exec php_prod bash -c "
    cd /var/www/html/prod
    ./vendor/bin/drush php:eval \"
      \\\$test_content = 'actools-storage-test-' . time();
      \\\$uri = 's3://actools-roundtrip-test.txt';
      \\\$written = file_put_contents(\\\$uri, \\\$test_content);
      if (\\\$written === false) { echo 'WRITE FAILED'; exit(1); }
      echo 'WRITE OK (' . \\\$written . ' bytes)';
      \\\$read = file_get_contents(\\\$uri);
      echo \\\$read === \\\$test_content ? 'READ OK' : 'READ FAILED';
      \\\$deleted = unlink(\\\$uri);
      echo \\\$deleted ? 'DELETE OK' : 'DELETE FAILED';
      echo 'Round-trip: ' . (\\\$read === \\\$test_content && \\\$deleted ? 'PASS' : 'FAIL');
    \" 2>/dev/null || echo 'S3 stream test failed'
  " 2>/dev/null || echo "Could not connect to php_prod"
}

cmd_storage_info() {
  ENV_FILE="${INSTALL_DIR}/actools.env"
  [[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }
  echo "=== S3 Storage Configuration ==="
  echo "Provider  : ${STORAGE_PROVIDER:-not set}"
  echo "Bucket    : ${S3_BUCKET:-not set}"
  echo "Endpoint  : ${S3_ENDPOINT_URL:-not set}"
  echo "CDN host  : ${ASSET_CDN_HOST:-not set}"
  echo "XeLaTeX   : ${XELATEX_MODE:-local}"
}
