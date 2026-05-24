#!/usr/bin/env bats
# =============================================================================
# tests/installer/preflight_test.bats — Tests for installer/preflight.sh
#
# preflight wraps real system calls (df, free, curl, ss) — full unit tests
# would require mocking each one. These tests cover the deterministic
# control-flow paths: missing env file, malformed env vars.
#
# End-to-end coverage of the happy preflight path lives in
# .github/workflows/e2e.yml — a real Hetzner CX22 provision.
# =============================================================================

setup() {
  export INSTALL_DIR
  INSTALL_DIR="$(mktemp -d)"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export STATE_FILE="${INSTALL_DIR}/.actools-state.json"
  export ACTOOLS_PLAIN=1

  source "${BATS_TEST_DIRNAME}/../../installer/output.sh"
  source "${BATS_TEST_DIRNAME}/../../installer/preflight.sh"
}

teardown() {
  rm -rf "$INSTALL_DIR"
}

@test "preflight: missing actools.env returns 1 with init suggestion" {
  run run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"actools.env"*"missing"* ]]
  [[ "$output" == *"sudo ./actools.sh init"* ]]
}

@test "preflight: placeholder BASE_DOMAIN is a failure" {
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=example.com
DRUPAL_ADMIN_EMAIL=admin@example.com
EOF
  run run_preflight
  # Returns 1 (failures) because example.com is rejected as placeholder.
  [ "$status" -eq 1 ]
  [[ "$output" == *"BASE_DOMAIN"*"placeholder"* ]]
}

@test "preflight: invalid DRUPAL_ADMIN_EMAIL is a failure" {
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=real-domain.example.org
DRUPAL_ADMIN_EMAIL=not-an-email
EOF
  run run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRUPAL_ADMIN_EMAIL"*"invalid"* ]]
}

@test "preflight: empty BASE_DOMAIN is a failure" {
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=
DRUPAL_ADMIN_EMAIL=admin@example.com
EOF
  run run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"BASE_DOMAIN"*"not set"*"placeholder"* ]]
}

@test "preflight: empty DRUPAL_ADMIN_EMAIL is a failure" {
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=real-domain.example.org
DRUPAL_ADMIN_EMAIL=
EOF
  run run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRUPAL_ADMIN_EMAIL"*"not set"* ]]
}

@test "preflight: no state file means 'fresh server'" {
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=real-domain.example.org
DRUPAL_ADMIN_EMAIL=admin@example.com
EOF
  # No STATE_FILE on disk
  run run_preflight
  [[ "$output" == *"Install state"* ]]
  [[ "$output" == *"fresh server"* ]]
}
