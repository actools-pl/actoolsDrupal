#!/usr/bin/env bash
# tests/fixtures/profiles/test/plus_doctor_check.sh
# Test stub for doctor resolver dispatch (D.0 fixture; marker-extended P0-I).
# NOTE: doctor's per-check PROFILE_DOCTOR_EXTRA loop is deliberately deferred
# (P0-H Entry 013) — doctor's live dispatch point is the deep handler resolved
# via resolve_feature_handler. This stub is retained for resolver-token tests;
# its marker is NOT asserted by the e2e (no live consumer in Phase 0).

test_doctor_check() {
    [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/doctor_check.marker"
    echo "TEST_DOCTOR_DISPATCHED:${1:-}"
}
