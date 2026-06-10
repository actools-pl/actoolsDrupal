#!/usr/bin/env bats
# =============================================================================
# tests/test_p0h_dispatch.bats — P0-H: profile-aware operator surfaces.
#
# One test file per phase (consolidation discipline; mirrors
# tests/test_d0_dispatch.bats). Proves that the operator surfaces consume the
# P0-E resolvers so a non-default profile routes to its handlers, AND that the
# community profile routes through NONE of them (byte-identical behaviour).
#
# Surfaces wired in P0-H and exercised here:
#   - doctor    cli/commands/doctor.sh   — `--deep` via resolve_feature_handler
#               (Tier-1 override) with a baseline fallback to the built-in
#               doctor_deep.sh gate. (PROFILE_DOCTOR_EXTRA per-check loop is
#               deliberately deferred — resolve_doctor_check exists and is
#               tested in test_d0_dispatch.bats; no Phase-0 consumer.)
#   - preflight installer/preflight.sh    — extras via resolve_profile_check
#               "preflight": resolved handler runs; an unknown check is a hard
#               FAIL for a non-default profile (not a silent skip).
#   - handoff   installer/handoff.sh       — the silent `*)` now routes through
#               resolve_handoff_section; resolved handler renders the section,
#               an unresolved section gets a visible (non-fatal) notice.
#   - init      installer/init.sh          — already profile-aware (P0-E);
#               confirmed here via a fake profile that declares an extra
#               PROFILE_INIT_FIELDS entry (Phase-0 collects extras as a no-op:
#               init still succeeds and the extra is NOT persisted).
#
# Community-unchanged proof: behaviour tests live in doctor_test.bats /
# preflight_test.bats / init_profile_test.bats (untouched, still green). This
# file adds the dispatch proofs and explicit "community routes through none"
# assertions at each surface.
# =============================================================================

setup() {
  REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="${REPO_DIR}/tests/fixtures/profiles"
  export ACTOOLS_PLAIN=1
  # Each test starts from a clean profile/domain environment to prevent leakage.
  unset ACTOOLS_PROFILE 2>/dev/null || true
  unset BASE_DOMAIN 2>/dev/null || true
}

teardown() {
  [[ -n "${INSTALL_DIR:-}" && -d "${INSTALL_DIR}" ]] && rm -rf "${INSTALL_DIR}"
  return 0
}

# Fresh sandbox INSTALL_DIR with the common loaders (dispatch + profile + output).
_new_sandbox() {
  INSTALL_DIR="$(mktemp -d)"
  export INSTALL_DIR
  mkdir -p "${INSTALL_DIR}/installer" "${INSTALL_DIR}/cli/commands" "${INSTALL_DIR}/profiles"
  cp "${REPO_DIR}/installer/dispatch.sh" "${INSTALL_DIR}/installer/dispatch.sh"
  cp "${REPO_DIR}/installer/profile.sh"  "${INSTALL_DIR}/installer/profile.sh"
  cp "${REPO_DIR}/installer/output.sh"   "${INSTALL_DIR}/installer/output.sh"
}

# ===========================================================================
# DOCTOR — resolve_feature_handler (Tier-1 override) + baseline fallback
# ===========================================================================

@test "doctor --deep: non-default profile override is resolved and run (override wins)" {
  _new_sandbox
  cp "${REPO_DIR}/cli/commands/doctor.sh"      "${INSTALL_DIR}/cli/commands/doctor.sh"
  cp "${REPO_DIR}/cli/commands/doctor_deep.sh" "${INSTALL_DIR}/cli/commands/doctor_deep.sh"  # baseline present
  # Stage the Tier-1 override at resolve_feature_handler's override location.
  mkdir -p "${INSTALL_DIR}/profiles.d/test/commands"
  cp "${FIXTURES}/test/commands/doctor_deep.sh" "${INSTALL_DIR}/profiles.d/test/commands/doctor_deep.sh"
  printf 'ACTOOLS_PROFILE=test\n' > "${INSTALL_DIR}/actools.env"

  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  # The profile's deep handler ran (sentinel) and its exit code propagated.
  [ "$status" -eq 7 ]
  [[ "$output" == *"TEST_DOCTOR_DEEP_OVERRIDE_DISPATCHED"* ]]
  # The built-in gate notice must NOT appear — the override replaced it.
  [[ "$output" != *"not available in this edition"* ]]
}

@test "doctor --deep: community routes through NONE — built-in gate, override ignored" {
  _new_sandbox
  cp "${REPO_DIR}/cli/commands/doctor.sh"      "${INSTALL_DIR}/cli/commands/doctor.sh"
  cp "${REPO_DIR}/cli/commands/doctor_deep.sh" "${INSTALL_DIR}/cli/commands/doctor_deep.sh"
  # Even with a 'test' override physically present, community must short-circuit.
  mkdir -p "${INSTALL_DIR}/profiles.d/test/commands"
  cp "${FIXTURES}/test/commands/doctor_deep.sh" "${INSTALL_DIR}/profiles.d/test/commands/doctor_deep.sh"
  printf 'ACTOOLS_PROFILE=community\n' > "${INSTALL_DIR}/actools.env"

  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  # Built-in in-development gate (exit 2), NOT the override (would be exit 7).
  [ "$status" -eq 2 ]
  [[ "$output" == *"not available in this edition"* ]]
  [[ "$output" != *"TEST_DOCTOR_DEEP_OVERRIDE_DISPATCHED"* ]]
}

# ===========================================================================
# PREFLIGHT — resolve_profile_check "preflight": resolved runs, unknown fails
# ===========================================================================

@test "preflight: non-default profile runs a resolved extra and HARD-FAILS an unknown one" {
  _new_sandbox
  cp "${FIXTURES}/fake-surfaces.profile" "${INSTALL_DIR}/profiles/test.profile"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export STATE_FILE="${INSTALL_DIR}/.actools-state.json"
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=p0h-test.invalid
DRUPAL_ADMIN_EMAIL=admin@example.com
ACTOOLS_PROFILE=test
EOF
  # Install the handler for the resolved check ('check' -> test_preflight_check);
  # leave 'missing' with no handler so it must fail.
  source "${FIXTURES}/test/plus_preflight_check.sh"
  source "${REPO_DIR}/installer/output.sh"
  source "${REPO_DIR}/installer/preflight.sh"

  run run_preflight
  # Resolved extra dispatched to its handler (with the check id as arg).
  [[ "$output" == *"TEST_PREFLIGHT_DISPATCHED:check"* ]]
  # Unknown extra is a FAILURE, not a silent skip.
  [[ "$output" == *"missing"*"no handler installed"* ]]
  [[ "$output" != *"missing"*"SKIP"* ]]
  # The unknown-check failure forces a non-zero (failure) exit.
  [ "$status" -eq 1 ]
}

@test "preflight: community routes through NONE — no profile-check output at all" {
  _new_sandbox
  cp "${REPO_DIR}/profiles/community.profile" "${INSTALL_DIR}/profiles/community.profile"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export STATE_FILE="${INSTALL_DIR}/.actools-state.json"
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=p0h-test.invalid
DRUPAL_ADMIN_EMAIL=admin@example.com
ACTOOLS_PROFILE=community
EOF
  source "${REPO_DIR}/installer/output.sh"
  source "${REPO_DIR}/installer/preflight.sh"

  run run_preflight
  # community's PROFILE_PREFLIGHT_EXTRA is empty → the extra loop never runs.
  [[ "$output" != *"Profile check"* ]]
}

# ===========================================================================
# HANDOFF — resolve_handoff_section replaces the silent *)
# ===========================================================================

@test "handoff: non-default profile section is resolved and rendered by its handler" {
  _new_sandbox
  cp "${FIXTURES}/fake-surfaces.profile" "${INSTALL_DIR}/profiles/test.profile"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export REAL_HOME="${INSTALL_DIR}"
  export LOG_DIR="${INSTALL_DIR}/logs"
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=p0h-test.invalid
ACTOOLS_PROFILE=test
EOF
  # Install the handler for the extra section ('section' -> test_handoff_section).
  source "${FIXTURES}/test/plus_handoff_section.sh"
  source "${REPO_DIR}/installer/output.sh"
  source "${REPO_DIR}/installer/handoff.sh"

  run run_handoff
  [ "$status" -eq 0 ]
  # The *) arm resolved 'section' and ran its handler (with the section as arg).
  [[ "$output" == *"TEST_HANDOFF_DISPATCHED:section"* ]]
}

@test "handoff: community routes through NONE — no dispatch and no unresolved notice" {
  _new_sandbox
  cp "${REPO_DIR}/profiles/community.profile" "${INSTALL_DIR}/profiles/community.profile"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export REAL_HOME="${INSTALL_DIR}"
  export LOG_DIR="${INSTALL_DIR}/logs"
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=p0h-test.invalid
ACTOOLS_PROFILE=community
EOF
  source "${REPO_DIR}/installer/output.sh"
  source "${REPO_DIR}/installer/handoff.sh"

  run run_handoff
  [ "$status" -eq 0 ]
  # All community sections hit explicit arms; *) never fires.
  [[ "$output" != *"TEST_HANDOFF_DISPATCHED"* ]]
  [[ "$output" != *"no handler is installed"* ]]
  # The built-in sections still render (behaviour preserved).
  [[ "$output" == *"Site:"* ]]
  [[ "$output" == *"Useful commands:"* ]]
}

# ===========================================================================
# INIT — already profile-aware (P0-E); confirm fake-profile init-field flow
# ===========================================================================

@test "init: fake profile with an extra PROFILE_INIT_FIELDS entry succeeds; extra not persisted" {
  _new_sandbox
  cp "${REPO_DIR}/actools.env.example"        "${INSTALL_DIR}/actools.env.example"
  cp "${REPO_DIR}/profiles/community.profile" "${INSTALL_DIR}/profiles/community.profile"
  cp "${FIXTURES}/fake-surfaces.profile"      "${INSTALL_DIR}/profiles/test.profile"
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export REAL_USER="${USER:-root}"
  export REAL_HOME="${HOME:-/root}"
  source "${REPO_DIR}/installer/output.sh"
  source "${REPO_DIR}/installer/init.sh"

  run run_init --profile test --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  [ -f "$ENV_FILE" ]
  grep -q '^ACTOOLS_PROFILE=test$' "$ENV_FILE"
  # Phase-0 collects PROFILE_INIT_FIELDS extras as a no-op — the declared extra
  # field name must NOT be written into actools.env.
  ! grep -q 'extra_field' "$ENV_FILE"
}

# ===========================================================================
# Resolver-level community baseline (the seam stays empty for community)
# ===========================================================================

@test "community routes through none: all four resolvers return empty for community" {
  result="$(bash -c '
    ACTOOLS_PROFILE=community
    INSTALL_DIR="'"${REPO_DIR}"'"
    source "'"${REPO_DIR}"'/installer/dispatch.sh"
    f=$(actools::dispatch::resolve_feature_handler doctor_deep)
    p=$(actools::dispatch::resolve_profile_check preflight check)
    d=$(actools::dispatch::resolve_profile_check doctor tls)
    s=$(actools::dispatch::resolve_handoff_section section)
    echo "${f}|${p}|${d}|${s}"
  ')"
  [ "$result" = "|||" ]
}

# ===========================================================================
# Fixture hygiene — the new fixture must be pure data (no side effects)
# ===========================================================================

@test "fixture: fake-surfaces.profile sources with no executable side effects" {
  local wd out rc produced created
  wd="$(mktemp -d)"; out="$(mktemp)"
  bash -c 'cd "$1" && set -u && . "$2"' _ "${wd}" "${FIXTURES}/fake-surfaces.profile" >"${out}" 2>&1; rc=$?
  produced="$(cat "${out}")"
  created="$(find "${wd}" -mindepth 1 2>/dev/null)"
  rm -rf "${wd}" "${out}"
  [ "$rc" -eq 0 ]
  [ -z "$produced" ]
  [ -z "$created" ]
}
