#!/usr/bin/env bats
# =============================================================================
# tests/core/secrets_test.bats — Tests for core/secrets.sh
# =============================================================================

setup() {
  TEST_ENV=$(mktemp)
  log()  { echo "LOG: $*"; }
  warn() { echo "WARN: $*"; }
  error() { echo "ERROR: $*"; exit 1; }
}

teardown() {
  rm -f "$TEST_ENV"
}

# --- rand_pass tests ---

@test "rand_pass generates a non-empty string" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  result=$(rand_pass)
  [ -n "$result" ]
}

@test "rand_pass generates exactly 22 characters" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  result=$(rand_pass)
  [ "${#result}" -eq 22 ]
}

@test "rand_pass generates only alphanumeric characters" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  result=$(rand_pass)
  [[ "$result" =~ ^[A-Za-z0-9]+$ ]]
}

@test "rand_pass generates different values each time" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  pass1=$(rand_pass)
  pass2=$(rand_pass)
  [ "$pass1" != "$pass2" ]
}

# --- gen_if_empty tests ---

@test "gen_if_empty leaves existing value unchanged" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  MY_VAR="existing_value"
  gen_if_empty MY_VAR
  [ "$MY_VAR" = "existing_value" ]
}

@test "gen_if_empty generates value when empty" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  MY_VAR=""
  gen_if_empty MY_VAR
  [ -n "$MY_VAR" ]
}

@test "gen_if_empty errors on CHANGEME value" {
  source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
  MY_VAR="CHANGEME"
  run bash -c "
    source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    MY_VAR='CHANGEME'
    gen_if_empty MY_VAR
  "
  [ "$status" -ne 0 ]
}

# --- writeback_secrets tests ---

@test "writeback replaces empty DB_ROOT_PASS line" {
  echo "DB_ROOT_PASS=" > "$TEST_ENV"
  echo "DRUPAL_ADMIN_PASS=" >> "$TEST_ENV"
  run bash -c "
    source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    ENV_FILE='${TEST_ENV}'
    DB_ROOT_PASS='newpassword123'
    DRUPAL_ADMIN_PASS='adminpass456'
    writeback_secrets
    grep 'DB_ROOT_PASS=newpassword123' '${TEST_ENV}'
  "
  [ "$status" -eq 0 ]
}

@test "writeback does not overwrite existing DB_ROOT_PASS" {
  echo "DB_ROOT_PASS=alreadyset" > "$TEST_ENV"
  run bash -c "
    source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    ENV_FILE='${TEST_ENV}'
    DB_ROOT_PASS='shouldnotreplace'
    writeback_secrets
    grep 'DB_ROOT_PASS=alreadyset' '${TEST_ENV}'
  "
  [ "$status" -eq 0 ]
}

@test "writeback handles trailing comment on empty line" {
  echo "DB_ROOT_PASS=   # set before install" > "$TEST_ENV"
  echo "DRUPAL_ADMIN_PASS=" >> "$TEST_ENV"
  run bash -c "
    source "${BATS_TEST_DIRNAME}/../../core/secrets.sh"
    log()  { echo \"LOG: \$*\"; }
    warn() { echo \"WARN: \$*\"; }
    error() { echo \"ERROR: \$*\"; exit 1; }
    ENV_FILE='${TEST_ENV}'
    DB_ROOT_PASS='newpass999'
    DRUPAL_ADMIN_PASS='adminpass'
    writeback_secrets
    grep 'DB_ROOT_PASS=newpass999' '${TEST_ENV}'
  "
  [ "$status" -eq 0 ]
}
