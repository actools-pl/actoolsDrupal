#!/usr/bin/env bats
# =============================================================================
# tests/generated/golden_drift_test.bats
# P0-C — Golden drift detection tests
#
# Re-renders each variant's generated files by calling the capture helper,
# then diffs against the stored golden fixtures.  Any unexplained difference
# is a test failure.
#
# Acceptance rule (see docs/tests/P0-C-golden-behavior-capture.md):
#   A later refactor PASSES only if:
#     (a) The re-rendered output matches the stored fixture sha256, OR
#     (b) The difference is listed in the intentional-difference table in
#         docs/tests/P0-C-golden-behavior-capture.md with a release note.
#   "Unexplained difference" = sha256 mismatch not listed in that table.
#
# Test count: 5 variants × 1 test each = 5 tests.
#
# Run:
#   bats tests/generated/golden_drift_test.bats
# =============================================================================

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CAPTURE_HELPER="${REPO_DIR}/tests/helpers/capture_golden_outputs.sh"
    GOLDEN_DIR="${REPO_DIR}/tests/fixtures/golden"

    # Each test gets a fresh temp dir for re-render output
    RENDER_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "${RENDER_TMP:-}"
}

# ---------------------------------------------------------------------------
# Helper: render one variant to RENDER_TMP and compare against golden fixtures.
# Fails (with diff output) on any unexplained sha256 mismatch.
# ---------------------------------------------------------------------------
_assert_no_drift() {
    local variant="$1"
    local golden_dir="${GOLDEN_DIR}/${variant}"
    local render_dir="${RENDER_TMP}/${variant}"

    # Golden fixture must exist (fail clearly if P0-C was never run)
    [[ -d "$golden_dir" ]] || {
        echo "Golden fixture missing: ${golden_dir}"
        echo "Run: bash tests/helpers/capture_golden_outputs.sh ${variant}"
        return 1
    }
    [[ -f "${golden_dir}/SHA256SUMS" ]] || {
        echo "SHA256SUMS manifest missing in: ${golden_dir}"
        return 1
    }

    # Re-render the variant to a fresh temp directory
    bash "$CAPTURE_HELPER" "$variant" "$RENDER_TMP" >/dev/null 2>&1 || {
        echo "Capture helper failed for variant '${variant}'"
        echo "Run manually for details: bash ${CAPTURE_HELPER} ${variant}"
        return 1
    }

    # Compare every file listed in the stored SHA256SUMS manifest
    local any_drift=false
    while IFS= read -r line; do
        local stored_sum filename rendered_sum
        stored_sum="${line%% *}"
        filename="${line##* }"
        rendered_sum=$(sha256sum "${render_dir}/${filename}" 2>/dev/null | cut -d' ' -f1)

        if [[ "$stored_sum" != "$rendered_sum" ]]; then
            echo "DRIFT: ${variant}/${filename}"
            echo "  Golden sha256  : ${stored_sum}"
            echo "  Rendered sha256: ${rendered_sum:-FILE_MISSING}"
            echo ""
            echo "  Diff:"
            diff "${golden_dir}/${filename}" "${render_dir}/${filename}" || true
            echo ""
            echo "To accept this change, update tests/fixtures/golden/${variant}/${filename}"
            echo "and add an entry to the intentional-difference table in"
            echo "docs/tests/P0-C-golden-behavior-capture.md with a release note."
            any_drift=true
        fi
    done < "${golden_dir}/SHA256SUMS"

    [[ "$any_drift" == "false" ]] || return 1
}

# ---------------------------------------------------------------------------
# Tests — one per variant in the fixture matrix
# ---------------------------------------------------------------------------

@test "variant 'default' matches golden fixture (no drift)" {
    _assert_no_drift "default"
}

@test "variant 'redis-off' matches golden fixture (no drift)" {
    _assert_no_drift "redis-off"
}

@test "variant 's3-on' matches golden fixture (no drift)" {
    _assert_no_drift "s3-on"
}

@test "variant 'cadvisor-on' matches golden fixture (no drift)" {
    _assert_no_drift "cadvisor-on"
}

@test "variant 'all-in-one' matches golden fixture (no drift)" {
    _assert_no_drift "all-in-one"
}

# ---------------------------------------------------------------------------
# Meta test — the fixture directory must contain exactly the 5 expected variants
# Each manifest lists the 6 generated STACK files. (P0-F: the CLI is no longer a
# generated fixture — it is installed by copying cli/actools verbatim and is
# verified by tests/installer/cli_authority_test.bats instead.)
# ---------------------------------------------------------------------------

@test "fixture directory contains all 5 expected variants" {
    local -a expected=(default redis-off s3-on cadvisor-on all-in-one)
    for v in "${expected[@]}"; do
        [[ -d "${GOLDEN_DIR}/${v}" ]] || {
            echo "Missing variant directory: ${GOLDEN_DIR}/${v}"
            return 1
        }
        [[ -f "${GOLDEN_DIR}/${v}/SHA256SUMS" ]] || {
            echo "Missing SHA256SUMS in: ${GOLDEN_DIR}/${v}"
            return 1
        }
        local count
        count=$(wc -l < "${GOLDEN_DIR}/${v}/SHA256SUMS")
        [[ "$count" -eq 6 ]] || {
            echo "Expected 6 entries in SHA256SUMS for ${v}, got ${count}"
            return 1
        }
    done
}
