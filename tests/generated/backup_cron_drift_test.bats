#!/usr/bin/env bats
# =============================================================================
# tests/generated/backup_cron_drift_test.bats
# P0-L — Backup-cron golden drift detection
#
# Re-renders the daily backup cron from the LIVE setup_backup_cron generator
# (via tests/helpers/capture_backup_cron.sh — modules/backup/cron.sh once the
# P0-L extraction lands, the inline actools.sh block before it) and
# byte-compares against the stored golden fixture
# tests/fixtures/golden/backup-cron/actools-backup.
#
# The fixture was captured from the inline generator BEFORE the extraction;
# the renderer locates whichever file live-defines the function. A green run
# after the move is therefore the byte-identity proof that the extraction was
# verbatim ("no change to the generated cron's bytes" — the P0-L hard rule).
#
# Acceptance rule (same as golden_drift_test.bats / P0-C):
#   A later refactor PASSES only if the re-rendered output matches the stored
#   fixture sha256, OR the difference is intentional, fixture-updated, and
#   release-noted. "Unexplained difference" = mismatch with no such note.
#
# Secret-safety: the generated cron holds NO secret (the backup password is
# read from .actools-state.json at cron runtime), which is what makes the
# fixture committable — pinned by a test below.
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CRON_HELPER="${REPO_DIR}/tests/helpers/capture_backup_cron.sh"
    GOLDEN="${REPO_DIR}/tests/fixtures/golden/backup-cron/actools-backup"
    GOLDEN_SUMS="${REPO_DIR}/tests/fixtures/golden/backup-cron/SHA256SUMS"
    RENDER_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "${RENDER_TMP:-}"
}

@test "backup cron: re-render matches golden fixture byte-for-byte (no drift)" {
    [[ -f "$GOLDEN" ]] || {
        echo "Golden cron fixture missing: ${GOLDEN}"
        echo "Run: bash tests/helpers/capture_backup_cron.sh capture"
        return 1
    }

    run bash "$CRON_HELPER" render "${RENDER_TMP}/actools-backup"
    [ "$status" -eq 0 ] || {
        echo "Cron render failed:"
        echo "$output"
        return 1
    }

    local stored_sum rendered_sum
    stored_sum=$(sha256sum "$GOLDEN" | cut -d' ' -f1)
    rendered_sum=$(sha256sum "${RENDER_TMP}/actools-backup" | cut -d' ' -f1)

    if [[ "$stored_sum" != "$rendered_sum" ]]; then
        echo "DRIFT: backup-cron/actools-backup"
        echo "  Golden sha256  : ${stored_sum}"
        echo "  Rendered sha256: ${rendered_sum}"
        echo ""
        echo "  Diff:"
        diff "$GOLDEN" "${RENDER_TMP}/actools-backup" || true
        echo ""
        echo "P0-L hard rule: the generated cron's bytes must not change."
        echo "To accept an INTENTIONAL change (a later, explicitly-scoped phase):"
        echo "re-capture via tests/helpers/capture_backup_cron.sh capture and add"
        echo "a release note explaining the difference."
        return 1
    fi
}

@test "backup cron: stored SHA256SUMS manifest is self-consistent" {
    [[ -f "$GOLDEN_SUMS" ]] || {
        echo "SHA256SUMS manifest missing: ${GOLDEN_SUMS}"
        return 1
    }
    local count
    count=$(wc -l < "$GOLDEN_SUMS")
    [[ "$count" -eq 1 ]] || {
        echo "Expected exactly 1 entry in backup-cron SHA256SUMS, got ${count}"
        return 1
    }
    ( cd "$(dirname "$GOLDEN_SUMS")" && sha256sum -c SHA256SUMS >/dev/null ) || {
        echo "Stored fixture does not match its own SHA256SUMS manifest."
        return 1
    }
}

@test "backup cron: fixture bakes no secret (password is read from state at runtime)" {
    # The committable-fixture precondition: the generator's fixed test password
    # must never appear in the rendered bytes, and the script must fetch the
    # real password from .actools-state.json at cron runtime instead.
    ! grep -q "TEST_BACKUP_PASS_FIXED" "$GOLDEN" || {
        echo "Fixture contains the fixed test password — a secret was baked at render time."
        return 1
    }
    grep -qF ".backup_user_pass // empty" "$GOLDEN" || {
        echo "Fixture no longer reads backup_user_pass from state at runtime."
        return 1
    }
}
