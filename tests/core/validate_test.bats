#!/usr/bin/env bats
# =============================================================================
# tests/core/validate_test.bats — Tests for core/validate.sh
# =============================================================================

setup() {
  source /home/actools/core/validate.sh
  # Stub log/warn/error for testing
  log()  { echo "LOG: $*"; }
  warn() { echo "WARN: $*"; }
  error() { echo "ERROR: $*"; exit 1; }
}

# --- validate_env tests ---

@test "PHP_MEMORY_LIMIT accepts 512m" {
  PHP_MEMORY_LIMIT=512m
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -eq 0 ]
}

@test "PHP_MEMORY_LIMIT accepts 2g" {
  PHP_MEMORY_LIMIT=2g
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -eq 0 ]
}

@test "PHP_MEMORY_LIMIT rejects 512MB" {
  PHP_MEMORY_LIMIT=512MB
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -ne 0 ]
}

@test "PHP_MEMORY_LIMIT rejects empty string" {
  PHP_MEMORY_LIMIT=bad
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -ne 0 ]
}

@test "PHP_VERSION accepts 8.3" {
  PHP_MEMORY_LIMIT=512m
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8.3
  run validate_env
  [ "$status" -eq 0 ]
}

@test "PHP_VERSION rejects 8" {
  PHP_MEMORY_LIMIT=512m
  WORKER_MEMORY_LIMIT=2g
  DB_MEMORY_LIMIT=2g
  PHP_VERSION=8
  run validate_env
  [ "$status" -ne 0 ]
}

# --- detect_s3_provider tests ---

@test "S3 provider auto-detected as backblaze" {
  STORAGE_PROVIDER=""
  S3_PROVIDER=""
  S3_ENDPOINT_URL="https://s3.us-west-000.backblazeb2.com"
  S3_ENDPOINT=""
  run bash -c "
    source /home/actools/core/validate.sh
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    STORAGE_PROVIDER=''
    S3_PROVIDER=''
    S3_ENDPOINT_URL='https://s3.us-west-000.backblazeb2.com'
    S3_ENDPOINT=''
    detect_s3_provider
    echo \"\$STORAGE_PROVIDER\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"backblaze"* ]]
}

@test "S3 provider auto-detected as wasabi" {
  run bash -c "
    source /home/actools/core/validate.sh
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    STORAGE_PROVIDER=''
    S3_PROVIDER=''
    S3_ENDPOINT_URL='https://s3.wasabisys.com'
    S3_ENDPOINT=''
    detect_s3_provider
    echo \"\$STORAGE_PROVIDER\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"wasabi"* ]]
}

@test "S3 provider auto-detected as aws" {
  run bash -c "
    source /home/actools/core/validate.sh
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    STORAGE_PROVIDER=''
    S3_PROVIDER=''
    S3_ENDPOINT_URL='https://s3.amazonaws.com'
    S3_ENDPOINT=''
    detect_s3_provider
    echo \"\$STORAGE_PROVIDER\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"aws"* ]]
}

@test "S3 provider defaults to aws when no endpoint set" {
  run bash -c "
    source /home/actools/core/validate.sh
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    STORAGE_PROVIDER=''
    S3_PROVIDER=''
    S3_ENDPOINT_URL=''
    S3_ENDPOINT=''
    detect_s3_provider
    echo \"\$STORAGE_PROVIDER\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"aws"* ]]
}

@test "S3 provider auto-detected as custom for unknown endpoint" {
  run bash -c "
    source /home/actools/core/validate.sh
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    STORAGE_PROVIDER=''
    S3_PROVIDER=''
    S3_ENDPOINT_URL='https://minio.myserver.com'
    S3_ENDPOINT=''
    detect_s3_provider
    echo \"\$STORAGE_PROVIDER\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom"* ]]
}
