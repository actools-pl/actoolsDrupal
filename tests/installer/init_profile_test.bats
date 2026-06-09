#!/usr/bin/env bats
# =============================================================================
# tests/installer/init_profile_test.bats — P0-E profile validation at init.
#
# Verifies the init-time profile safety added in P0-E (alignment §4.3):
#   - an unknown profile name fails cleanly (exit 3)
#   - a known-but-unshipped profile (community-plus) fails BEFORE persisting
#     actools.env — the file is never written (exit 3)
#   - a profile that REQUIRES an actor id fails without --actor-id and
#     succeeds with it
#   - a profile that REQUIRES a change ticket fails without --change-ticket and
#     succeeds with it
#   - the default (community) profile requires NEITHER (behavior preserved)
#   - governance flags are VALIDATED but NOT persisted to actools.env
#
# Fake-profile mechanism: the only test-friendly allowed profile name is 'test'
# (see _ACTOOLS_ALLOWED_PROFILES in installer/dispatch.sh). Tests that need a
# governance-requiring profile stage a fixture from tests/fixtures/profiles/
# into the sandbox as profiles/test.profile, then run `init --profile test`.
# =============================================================================

setup() {
  export INSTALL_DIR
  INSTALL_DIR="$(mktemp -d)"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export REAL_USER="${USER:-root}"
  export REAL_HOME="${HOME:-/root}"

  # Stage the files init needs: the template, the dispatch + profile loaders,
  # and the default community profile. init sources dispatch.sh (which turns on
  # `set -u`) and profile.sh, exactly as in production.
  mkdir -p "${INSTALL_DIR}/installer" "${INSTALL_DIR}/profiles"
  cp "${BATS_TEST_DIRNAME}/../../actools.env.example"        "${INSTALL_DIR}/actools.env.example"
  cp "${BATS_TEST_DIRNAME}/../../installer/dispatch.sh"      "${INSTALL_DIR}/installer/dispatch.sh"
  cp "${BATS_TEST_DIRNAME}/../../installer/profile.sh"       "${INSTALL_DIR}/installer/profile.sh"
  cp "${BATS_TEST_DIRNAME}/../../profiles/community.profile" "${INSTALL_DIR}/profiles/community.profile"

  source "${BATS_TEST_DIRNAME}/../../installer/output.sh"
  source "${BATS_TEST_DIRNAME}/../../installer/init.sh"

  export ACTOOLS_PLAIN=1
  FIXTURES="${BATS_TEST_DIRNAME}/../fixtures/profiles"
}

teardown() {
  rm -rf "$INSTALL_DIR"
}

# Stage a fixture profile into the sandbox as profiles/test.profile.
_stage_test_profile() {
  cp "${FIXTURES}/$1" "${INSTALL_DIR}/profiles/test.profile"
}

# ---------------------------------------------------------------------------
# Unknown / unshipped profiles fail before persisting
# ---------------------------------------------------------------------------

@test "init: unknown profile name fails cleanly (exit 3)" {
  run run_init --profile not-a-real-profile --domain example.com --email admin@example.com
  [ "$status" -eq 3 ]
  [[ "$output" == *"--profile"* ]]
  [ ! -f "$ENV_FILE" ]
}

@test "init: community-plus fails before persisting (profile file absent, exit 3)" {
  # community-plus IS an allowed name but its .profile is a Phase-1 product that
  # does not ship here, so init must fail before writing actools.env.
  run run_init --profile community-plus --domain example.com --email admin@example.com
  [ "$status" -eq 3 ]
  [[ "$output" == *"profile file"* ]]
  # The latent break this closes: actools.env must NOT have been written.
  [ ! -f "$ENV_FILE" ]
}

# ---------------------------------------------------------------------------
# Actor-required fixture profile
# ---------------------------------------------------------------------------

@test "init: actor-required profile fails without --actor-id (exit 1)" {
  _stage_test_profile fake-actor.profile
  run run_init --profile test --domain example.com --email admin@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"--actor-id"* ]]
  [ ! -f "$ENV_FILE" ]
}

@test "init: actor-required profile succeeds with --actor-id" {
  _stage_test_profile fake-actor.profile
  run run_init --profile test --domain example.com --email admin@example.com --actor-id alice
  [ "$status" -eq 0 ]
  [ -f "$ENV_FILE" ]
  grep -q '^ACTOOLS_PROFILE=test$' "$ENV_FILE"
}

@test "init: actor id is validated but NOT persisted to actools.env" {
  _stage_test_profile fake-actor.profile
  run run_init --profile test --domain example.com --email admin@example.com --actor-id alice
  [ "$status" -eq 0 ]
  # P0-E records only the requirement, never the identity value.
  ! grep -q 'alice' "$ENV_FILE"
}

# ---------------------------------------------------------------------------
# Change-ticket-required fixture profile
# ---------------------------------------------------------------------------

@test "init: ticket-required profile fails without --change-ticket (exit 1)" {
  _stage_test_profile fake-ticket.profile
  run run_init --profile test --domain example.com --email admin@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"--change-ticket"* ]]
  [ ! -f "$ENV_FILE" ]
}

@test "init: ticket-required profile succeeds with --change-ticket" {
  _stage_test_profile fake-ticket.profile
  run run_init --profile test --domain example.com --email admin@example.com --change-ticket TICKET-42
  [ "$status" -eq 0 ]
  [ -f "$ENV_FILE" ]
  grep -q '^ACTOOLS_PROFILE=test$' "$ENV_FILE"
}

@test "init: change ticket is validated but NOT persisted to actools.env" {
  _stage_test_profile fake-ticket.profile
  run run_init --profile test --domain example.com --email admin@example.com --change-ticket TICKET-42
  [ "$status" -eq 0 ]
  ! grep -q 'TICKET-42' "$ENV_FILE"
}

# ---------------------------------------------------------------------------
# Default community profile — behavior preserved
# ---------------------------------------------------------------------------

@test "init: community profile requires neither actor nor ticket" {
  run run_init --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  [ -f "$ENV_FILE" ]
  grep -q '^ACTOOLS_PROFILE=community$' "$ENV_FILE"
}

@test "init: explicit --profile community also succeeds with no governance flags" {
  run run_init --profile community --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  grep -q '^ACTOOLS_PROFILE=community$' "$ENV_FILE"
}
