#!/usr/bin/env bash
# =============================================================================
# tests/fixtures/profiles/test/manifest.sh — Test fixture profile.
#
# Used ONLY by D.0+ bats tests to exercise resolver dispatch against a
# non-default, non-production profile. Must not be activated outside tests.
#
# Structural shape mirrors production profiles (community-plus will follow
# the same pattern when D.1 modules arrive). Tests verify a real contract.
# =============================================================================

export ACTOOLS_PROFILE=test
export _ACTOOLS_TEST_FIXTURE_VERSION="d0"

# Handler stubs — each echoes a sentinel value so tests can assert
# the resolver returned the correct token AND the token maps to a real function.

test_feature() {
    echo "TEST_FEATURE_DISPATCHED:${1:-}"
}

test_preflight_check() {
    echo "TEST_PREFLIGHT_DISPATCHED:${1:-}"
}

test_doctor_check() {
    echo "TEST_DOCTOR_DISPATCHED:${1:-}"
}

test_handoff_section() {
    echo "TEST_HANDOFF_DISPATCHED:${1:-}"
}
