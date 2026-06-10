#!/usr/bin/env bash
# tests/fixtures/profiles/test/plus_preflight_check.sh
# Test stub for preflight resolver dispatch (D.0 fixture; marker-extended P0-I).
# Provides the handler function the resolver names for preflight checks. When
# ACTOOLS_MARKER_DIR is set (the P0-I e2e harness), it ALSO touches a uniquely-
# named marker so the e2e can assert the preflight-extra dispatch point fired.
# When unset (the D.0/P0-H tests that assert only the sentinel), the touch is a
# no-op, so those tests — and the side-effect-free source checks — are unchanged.

test_preflight_check() {
    [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/preflight_check.marker"
    echo "TEST_PREFLIGHT_DISPATCHED:${1:-}"
}
