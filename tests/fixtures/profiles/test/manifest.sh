#!/usr/bin/env bash
# =============================================================================
# tests/fixtures/profiles/test/manifest.sh — Test fixture profile.
#
# Used ONLY by D.0+ bats tests to exercise resolver dispatch against a
# non-default, non-production profile. Must not be activated outside tests.
#
# Structural shape mirrors production profiles (community-plus will follow
# the same pattern when D.1 modules arrive). Tests verify a real contract.
#
# P0-I: each handler also touches a uniquely-named marker when ACTOOLS_MARKER_DIR
# is set, so the fake-profile e2e can assert dispatch fired. The touch is a no-op
# when the var is unset (the D.0 tests that assert only the sentinel), and it
# happens at CALL time — sourcing this file still only defines functions + exports.
# =============================================================================

export ACTOOLS_PROFILE=test
export _ACTOOLS_TEST_FIXTURE_VERSION="d0"

# Handler stubs — each echoes a sentinel value so tests can assert
# the resolver returned the correct token AND the token maps to a real function.

test_feature() {
    [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/feature.marker"
    echo "TEST_FEATURE_DISPATCHED:${1:-}"
}

test_preflight_check() {
    [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/preflight_check.marker"
    echo "TEST_PREFLIGHT_DISPATCHED:${1:-}"
}

test_doctor_check() {
    [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/doctor_check.marker"
    echo "TEST_DOCTOR_DISPATCHED:${1:-}"
}

test_handoff_section() {
    [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/handoff_section.marker"
    echo "TEST_HANDOFF_DISPATCHED:${1:-}"
}
