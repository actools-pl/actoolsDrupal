#!/usr/bin/env bash
# tests/fixtures/profiles/test/plus_preflight_check.sh
# Test stub for preflight resolver dispatch (D.0 fixture).
# Provides the handler function the resolver would name for preflight checks.

test_preflight_check() {
    echo "TEST_PREFLIGHT_DISPATCHED:${1:-}"
}
