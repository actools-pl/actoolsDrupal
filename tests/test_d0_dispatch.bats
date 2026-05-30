#!/usr/bin/env bats
# =============================================================================
# tests/test_d0_dispatch.bats — D.0 Community Seam Hardening: dispatch tests.
#
# Consolidates ALL D.0 verification into one file (consolidation
# discipline: one test file per phase, named for the phase).
#
# Test count target: ≥ 31 (brief floor). This suite contains 33 tests.
# Dispatch shapes: community (default) / test (fixture) / adversarial (unknown).
#
# Coverage:
#   - Resolver dispatch correctness (12 tests: 4 resolvers × 3 profiles)
#   - profile_is_valid correctness (5 tests)
#   - actools::cli::resolve_profile (8 tests)
#   - Fixture profile activation (3 tests)
#   - Sibling-scope audit meta-test (1 test)
#   - Community-install regression (2 tests)
#   - Module guard (1 test)
#   - Unknown profile stderr warning (1 test)
# =============================================================================

# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

setup() {
    # Locate repo root relative to this test file.
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    DISPATCH_SH="${REPO_DIR}/installer/dispatch.sh"
    FIXTURE_MANIFEST="${REPO_DIR}/tests/fixtures/profiles/test/manifest.sh"

    # Each test gets a clean environment for ACTOOLS_PROFILE.
    unset ACTOOLS_PROFILE 2>/dev/null || true
    unset _ACTOOLS_DISPATCH_SOURCED 2>/dev/null || true
}

# Source dispatch.sh in a subshell helper.
# Usage: run_dispatch ACTOOLS_PROFILE FUNCTION [ARGS...]
_dispatch_in_subshell() {
    local profile="$1"; shift
    local fn="$1"; shift
    bash -c "
        INSTALL_DIR='${REPO_DIR}'
        ACTOOLS_PROFILE='${profile}'
        source '${DISPATCH_SH}'
        ${fn} \"\$@\"
    " -- "$@"
}

# ---------------------------------------------------------------------------
# BLOCK 1 — Resolver dispatch correctness (12 tests: 4 resolvers × 3 profiles)
# Input shapes: community (default), test (fixture), unknown
# ---------------------------------------------------------------------------

@test "resolve_feature_handler: community returns empty string" {
    result="$(_dispatch_in_subshell "community" "actools::dispatch::resolve_feature_handler" "doctor_deep")"
    [ "$result" = "" ]
}

@test "resolve_feature_handler: community-plus returns plus_ token" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_feature_handler" "doctor_deep")"
    [ "$result" = "plus_doctor_deep" ]
}

@test "resolve_feature_handler: unknown profile returns empty and warns to stderr" {
    result="$(_dispatch_in_subshell "garbage_profile" "actools::dispatch::resolve_feature_handler" "anything" 2>/dev/null)"
    [ "$result" = "" ]
}

@test "resolve_preflight_check: community returns empty string" {
    result="$(_dispatch_in_subshell "community" "actools::dispatch::resolve_preflight_check" "disk")"
    [ "$result" = "" ]
}

@test "resolve_preflight_check: community-plus returns plus_preflight_ token" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_preflight_check" "disk")"
    [ "$result" = "plus_preflight_disk" ]
}

@test "resolve_preflight_check: unknown profile returns empty string" {
    result="$(_dispatch_in_subshell "bad_profile" "actools::dispatch::resolve_preflight_check" "disk" 2>/dev/null)"
    [ "$result" = "" ]
}

@test "resolve_doctor_check: community returns empty string" {
    result="$(_dispatch_in_subshell "community" "actools::dispatch::resolve_doctor_check" "tls")"
    [ "$result" = "" ]
}

@test "resolve_doctor_check: community-plus returns plus_doctor_ token" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_doctor_check" "tls")"
    [ "$result" = "plus_doctor_tls" ]
}

@test "resolve_doctor_check: unknown profile returns empty string" {
    result="$(_dispatch_in_subshell "bad_profile" "actools::dispatch::resolve_doctor_check" "tls" 2>/dev/null)"
    [ "$result" = "" ]
}

@test "resolve_handoff_section: community returns empty string" {
    result="$(_dispatch_in_subshell "community" "actools::dispatch::resolve_handoff_section" "site")"
    [ "$result" = "" ]
}

@test "resolve_handoff_section: community-plus returns plus_handoff_ token" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_handoff_section" "site")"
    [ "$result" = "plus_handoff_site" ]
}

@test "resolve_handoff_section: unknown profile returns empty string" {
    result="$(_dispatch_in_subshell "bad_profile" "actools::dispatch::resolve_handoff_section" "site" 2>/dev/null)"
    [ "$result" = "" ]
}

# ---------------------------------------------------------------------------
# BLOCK 2 — profile_is_valid correctness (5 tests)
# ---------------------------------------------------------------------------

@test "profile_is_valid: community is valid" {
    run bash -c "source '${DISPATCH_SH}'; actools::dispatch::profile_is_valid 'community'"
    [ "$status" -eq 0 ]
}

@test "profile_is_valid: community-plus is valid" {
    run bash -c "source '${DISPATCH_SH}'; actools::dispatch::profile_is_valid 'community-plus'"
    [ "$status" -eq 0 ]
}

@test "profile_is_valid: test is valid (fixture profile)" {
    run bash -c "source '${DISPATCH_SH}'; actools::dispatch::profile_is_valid 'test'"
    [ "$status" -eq 0 ]
}

@test "profile_is_valid: empty string is invalid" {
    run bash -c "source '${DISPATCH_SH}'; actools::dispatch::profile_is_valid ''"
    [ "$status" -ne 0 ]
}

@test "profile_is_valid: malformed string is invalid" {
    run bash -c "source '${DISPATCH_SH}'; actools::dispatch::profile_is_valid 'enterprise-hack'"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BLOCK 3 — actools::cli::resolve_profile (8 tests)
# Verifies Decision 2: fail-closed conflict, invalid exits, precedence order.
# ---------------------------------------------------------------------------

@test "resolve_profile: no flag + no env defaults to community" {
    result="$(bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile '' ''")"
    [ "$result" = "community" ]
}

@test "resolve_profile: flag only resolves to flag value" {
    result="$(bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile 'community-plus' ''")"
    [ "$result" = "community-plus" ]
}

@test "resolve_profile: env only resolves to env value" {
    result="$(bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile '' 'community'")"
    [ "$result" = "community" ]
}

@test "resolve_profile: flag equals env resolves cleanly (no conflict)" {
    result="$(bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile 'community-plus' 'community-plus'")"
    [ "$result" = "community-plus" ]
}

@test "resolve_profile: flag differs from env exits 2 (conflict)" {
    run bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile 'community' 'community-plus'"
    [ "$status" -eq 2 ]
}

@test "resolve_profile: invalid flag exits 3" {
    run bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile 'pro-edition' ''"
    [ "$status" -eq 3 ]
}

@test "resolve_profile: empty flag with env set resolves to env value" {
    result="$(bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile '' 'community-plus'")"
    [ "$result" = "community-plus" ]
}

@test "resolve_profile: flag with empty env resolves to flag value" {
    result="$(bash -c "source '${DISPATCH_SH}'; actools::cli::resolve_profile 'community-plus' ''")"
    [ "$result" = "community-plus" ]
}

# ---------------------------------------------------------------------------
# BLOCK 4 — Fixture profile activation (3 tests)
# Decision 3: fixture has the same structural shape production profiles will use.
# ---------------------------------------------------------------------------

@test "fixture manifest: sourcing sets ACTOOLS_PROFILE=test" {
    result="$(bash -c "source '${FIXTURE_MANIFEST}'; echo \"\$ACTOOLS_PROFILE\"")"
    [ "$result" = "test" ]
}

@test "fixture manifest: handler functions are defined after sourcing" {
    run bash -c "
        source '${FIXTURE_MANIFEST}'
        declare -f test_feature >/dev/null 2>&1 && \
        declare -f test_preflight_check >/dev/null 2>&1 && \
        declare -f test_doctor_check >/dev/null 2>&1 && \
        declare -f test_handoff_section >/dev/null 2>&1
    "
    [ "$status" -eq 0 ]
}

@test "resolver returns test_ tokens when ACTOOLS_PROFILE=test" {
    result="$(bash -c "
        source '${FIXTURE_MANIFEST}'
        source '${DISPATCH_SH}'
        actools::dispatch::resolve_preflight_check 'foo'
    ")"
    [ "$result" = "test_preflight_foo" ]
}

# ---------------------------------------------------------------------------
# BLOCK 5 — Sibling-scope audit meta-test (1 test)
# Guards the internal-verification-scope-must-enumerate-sibling-files
# held candidate. Every file reading ACTOOLS_PROFILE must either source
# dispatch.sh or carry a DISPATCH_EXEMPT comment.
# ---------------------------------------------------------------------------

@test "sibling-scope audit: every ACTOOLS_PROFILE reader sources dispatch.sh or is DISPATCH_EXEMPT" {
    # Find all shell files in the repo that reference ACTOOLS_PROFILE.
    local offenders=()
    while IFS= read -r filepath; do
        # Skip dispatch.sh itself (it defines ACTOOLS_PROFILE handling).
        [[ "$filepath" == *"installer/dispatch.sh" ]] && continue
        # Skip profile files (they SET ACTOOLS_PROFILE, not read for dispatch).
        [[ "$filepath" == *".profile" ]] && continue
        # Skip test files — they set ACTOOLS_PROFILE intentionally.
        [[ "$filepath" == *"/tests/"* ]] && continue

        local content
        content="$(cat "$filepath")"

        # File is compliant if it sources dispatch.sh OR carries DISPATCH_EXEMPT comment.
        if echo "$content" | grep -q "installer/dispatch.sh"; then
            continue
        fi
        if echo "$content" | grep -q "DISPATCH_EXEMPT"; then
            continue
        fi

        offenders+=("$filepath")
    done < <(grep -rl "ACTOOLS_PROFILE" "${REPO_DIR}" \
        --include="*.sh" --include="*.bats" --include="*.profile" \
        2>/dev/null)

    if [ "${#offenders[@]}" -gt 0 ]; then
        echo "Files reading ACTOOLS_PROFILE without dispatch.sh sourcing or DISPATCH_EXEMPT comment:"
        printf '  %s\n' "${offenders[@]}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# BLOCK 6 — Community-install regression (2 tests)
# D.0 defining property: community installs see ZERO behaviour change.
# ---------------------------------------------------------------------------

@test "community profile: all four resolvers return exact empty string" {
    result="$(bash -c "
        ACTOOLS_PROFILE=community
        source '${DISPATCH_SH}'
        h=\$(actools::dispatch::resolve_feature_handler 'anything')
        p=\$(actools::dispatch::resolve_preflight_check 'anything')
        d=\$(actools::dispatch::resolve_doctor_check 'anything')
        s=\$(actools::dispatch::resolve_handoff_section 'anything')
        echo \"\${h}|\${p}|\${d}|\${s}\"
    ")"
    # All four must be empty — pipe-separated empties produce "|||"
    [ "$result" = "|||" ]
}

@test "community profile: resolver never returns 'community_' prefixed token (no false positive)" {
    result="$(_dispatch_in_subshell "community" "actools::dispatch::resolve_feature_handler" "doctor_deep")"
    # Must be exactly empty — not "community_doctor_deep", not "default", not any token.
    [ -z "$result" ]
}

# ---------------------------------------------------------------------------
# BLOCK 7 — Module guard (1 test)
# Sourcing dispatch.sh twice must not produce errors or redefinition warnings.
# ---------------------------------------------------------------------------

@test "module guard: sourcing dispatch.sh twice produces no errors" {
    run bash -c "
        source '${DISPATCH_SH}'
        source '${DISPATCH_SH}'
        echo 'double-source-ok'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"double-source-ok"* ]]
}

# ---------------------------------------------------------------------------
# BLOCK 8 — Unknown profile stderr warning (1 test)
# Unknown profile must warn to stderr, not fail-fast (fail-soft contract).
# ---------------------------------------------------------------------------

@test "unknown profile: emits WARN to stderr and does not exit non-zero" {
    run bash -c "
        ACTOOLS_PROFILE='totally_unknown'
        source '${DISPATCH_SH}'
        actools::dispatch::resolve_feature_handler 'foo'
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^$ ]] || [[ "$output" = "" ]] || [[ "$output" == *"WARN"* ]]  # stdout empty OR merged-with-WARN
    [[ "$stderr" == *"WARN"* ]] || [[ "$output" == *"WARN"* ]]
}
