#!/usr/bin/env bats
# =============================================================================
# tests/installer/init_test.bats — Tests for installer/init.sh
#
# Verifies the init contract from Doc 1 §9.2:
#   - missing --domain or --email is a hard fail
#   - invalid email format is a hard fail
#   - existing actools.env is not clobbered without --force
#   - the three operator-facing fields are written verbatim
#   - SITE_NAME is quoted (so values with spaces source cleanly)
# =============================================================================

setup() {
  # Sandbox: a temp INSTALL_DIR with a copy of the example file
  export INSTALL_DIR
  INSTALL_DIR="$(mktemp -d)"
  cp "${BATS_TEST_DIRNAME}/../../actools.env.example" "${INSTALL_DIR}/actools.env.example"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export REAL_USER="${USER:-root}"
  export REAL_HOME="${HOME:-/root}"

  # Source the helpers and the unit under test
  source "${BATS_TEST_DIRNAME}/../../installer/output.sh"
  source "${BATS_TEST_DIRNAME}/../../installer/init.sh"

  # Silence the styled output during tests
  export ACTOOLS_PLAIN=1
}

teardown() {
  rm -rf "$INSTALL_DIR"
}

@test "init: missing --domain fails" {
  run run_init --email admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--domain"*"required"* ]]
}

@test "init: missing --email fails" {
  run run_init --domain example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--email"*"required"* ]]
}

@test "init: malformed email is rejected" {
  run run_init --domain example.com --email not-an-email
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid format"* ]]
}

@test "init: valid args create the env file" {
  run run_init --domain example.com --email admin@example.com --site-name "Example"
  [ "$status" -eq 0 ]
  [ -f "$ENV_FILE" ]
}

@test "init: writes BASE_DOMAIN verbatim" {
  run run_init --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  grep -q '^BASE_DOMAIN=example.com$' "$ENV_FILE"
}

@test "init: writes DRUPAL_ADMIN_EMAIL verbatim" {
  run run_init --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  grep -q '^DRUPAL_ADMIN_EMAIL=admin@example.com$' "$ENV_FILE"
}

@test "init: site-name defaults to domain when omitted" {
  run run_init --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  grep -q '^SITE_NAME="example.com"$' "$ENV_FILE"
}

@test "init: site-name with spaces is quoted" {
  run run_init --domain example.com --email admin@example.com --site-name "Example Site"
  [ "$status" -eq 0 ]
  grep -q '^SITE_NAME="Example Site"$' "$ENV_FILE"
  # And the env file must still source cleanly
  set -a
  source "$ENV_FILE"
  set +a
  [ "$SITE_NAME" = "Example Site" ]
}

@test "init: refuses to overwrite without --force" {
  echo "BASE_DOMAIN=original.example.com" > "$ENV_FILE"
  run run_init --domain new.example.com --email admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
  # Original content untouched
  grep -q '^BASE_DOMAIN=original.example.com$' "$ENV_FILE"
}

@test "init: --force overwrites" {
  cp "${INSTALL_DIR}/actools.env.example" "$ENV_FILE"
  run run_init --domain new.example.com --email admin@example.com --force
  [ "$status" -eq 0 ]
  grep -q '^BASE_DOMAIN=new.example.com$' "$ENV_FILE"
}

@test "init: missing template is a hard fail" {
  rm "${INSTALL_DIR}/actools.env.example"
  run run_init --domain example.com --email admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"actools.env.example"*"missing"* ]]
}
