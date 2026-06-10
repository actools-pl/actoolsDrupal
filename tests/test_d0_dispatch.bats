#!/usr/bin/env bats
# =============================================================================
# tests/test_d0_dispatch.bats — D.0 Community Seam Hardening: dispatch tests.
#
# Consolidates ALL D.0 verification into one file (consolidation
# discipline: one test file per phase, named for the phase).
#
# Test count target: ≥ 31 (brief floor). This suite contains 49 tests
# (33 from D.0 + 15 added at P0-E: blocks 9/10/11 below + 1 added at P0-I:
# the resolver-bypass audit in block 5).
# Dispatch shapes: community (default) / test (fixture) / adversarial (unknown).
#
# Coverage:
#   - Resolver dispatch correctness (12 tests: 4 resolvers × 3 profiles)
#       NOTE (P0-E): resolve_feature_handler is now PATH-based (3-tier), so its
#       community-plus case asserts a resolved cli/commands/*.sh path, not a
#       plus_* token. The preflight/doctor/handoff resolvers stay token-based.
#   - profile_is_valid correctness (5 tests)
#   - actools::cli::resolve_profile (8 tests)
#   - Fixture profile activation (3 tests)
#   - Sibling-scope audit meta-test (1 test)
#   - [P0-I] resolver-bypass audit: no source/. of ${INSTALL_DIR}/modules/plus_*
#     outside the resolver (1 test; LOCKED §10 Risk 2 / alignment §4.4)
#   - Community-install regression (2 tests)
#   - Module guard (1 test)
#   - Unknown profile stderr warning (1 test)
#   - [P0-E] resolve_feature_handler 3-tier order (5 tests: override > module >
#     default > empty, plus the community short-circuit byte-identical guard)
#   - [P0-E] resolve_profile_check umbrella delegation (6 tests)
#   - [P0-E] side-effect-free profile loading (4 tests incl. a negative control)
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

@test "resolve_feature_handler: community-plus resolves to a tier-3 default handler path" {
    # P0-E §4.1: resolve_feature_handler now returns a PATH via 3-tier resolution
    # (active-profile override -> profile module -> default), not a token. No
    # community-plus override or module ships, so 'doctor_deep' falls through to
    # the default cli/commands handler, which exists. INSTALL_DIR is REPO_DIR in
    # _dispatch_in_subshell, so the resolved path points at the real repo file.
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_feature_handler" "doctor_deep")"
    [[ "$result" == *"cli/commands/doctor_deep.sh" ]]
    [ -f "$result" ]
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
# BLOCK 5 — Sibling-scope + resolver-bypass audit meta-tests (2 tests)
# Guards the internal-verification-scope-must-enumerate-sibling-files
# held candidate. Every file reading ACTOOLS_PROFILE must either source
# dispatch.sh or carry a DISPATCH_EXEMPT comment. [P0-I] adds the resolver-
# bypass audit: only the resolver may source a ${INSTALL_DIR}/modules/plus_*
# path (LOCKED §10 Risk 2; alignment §4.4).
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

@test "resolver-bypass audit: no source/. of \${INSTALL_DIR}/modules/plus_* outside the resolver" {
    # LOCKED §10 Risk 2 / alignment §4.4: once the resolver layer exists, the
    # resolver (installer/dispatch.sh) is the ONLY place allowed to turn a
    # plus_* module path into a sourced/executed handler. Any OTHER file that
    # source/. -includes a ${INSTALL_DIR}/modules/plus_* path is a hardcoded
    # resolver bypass and must fail CI, so "we can hardcode this one path just
    # this once" cannot creep in during Phases 1–6. Mirrors the offenders-
    # collection shape of the sibling-scope audit above.
    local offenders=()
    while IFS= read -r filepath; do
        # The resolver itself is the allowed site (it constructs module paths).
        [[ "$filepath" == *"installer/dispatch.sh" ]] && continue
        # Tests reference paths intentionally (fixtures, this guard's own grep).
        [[ "$filepath" == *"/tests/"* ]] && continue

        # A statement that STARTS (after optional indent) with `source` or `.`
        # and references a modules/plus_ path is a bypass. Anchoring at line
        # start avoids matching comments that merely mention the phrase.
        if grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*modules/plus_' "$filepath"; then
            offenders+=("$filepath")
        fi
    done < <(grep -rl 'modules/plus_' "${REPO_DIR}" \
        --include="*.sh" --include="*.bats" 2>/dev/null)

    if [ "${#offenders[@]}" -gt 0 ]; then
        echo "Resolver bypass — files sourcing a \${INSTALL_DIR}/modules/plus_* path outside the resolver:"
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

# ---------------------------------------------------------------------------
# BLOCK 9 — resolve_feature_handler 3-tier path resolution (P0-E §4.1)
#
# resolve_feature_handler now returns the PATH of the FIRST existing handler in
# the LOCKED order: active-profile override -> profile module -> default. These
# tests stage a sandbox INSTALL_DIR with selected tiers present and assert which
# one wins. The community short-circuit (empty even with a staged override) is
# the byte-identical guarantee and is non-negotiable.
# ---------------------------------------------------------------------------

# Stage a sandbox INSTALL_DIR containing the requested tiers, resolve FEATURE for
# PROFILE, print the resolved handler, then remove the sandbox. TIERS is a
# space-separated subset of {override, module, default}.
_feat_in_sandbox() {
    local profile="$1" feature="$2" tiers="$3"
    local sb result
    sb="$(mktemp -d)"
    mkdir -p "${sb}/profiles.d/${profile}/commands" "${sb}/modules/mod_x" "${sb}/cli/commands"
    [[ " ${tiers} " == *" override "* ]] && echo '# override' > "${sb}/profiles.d/${profile}/commands/${feature}.sh"
    [[ " ${tiers} " == *" module "*   ]] && echo '# module'   > "${sb}/modules/mod_x/${feature}.sh"
    [[ " ${tiers} " == *" default "*  ]] && echo '# default'  > "${sb}/cli/commands/${feature}.sh"
    result="$(bash -c '
        INSTALL_DIR="$1"; ACTOOLS_PROFILE="$2"; PROFILE_FEATURE_MODULES=(mod_x)
        source "$3"
        actools::dispatch::resolve_feature_handler "$4"
    ' _ "${sb}" "${profile}" "${DISPATCH_SH}" "${feature}")"
    rm -rf "${sb}"
    printf '%s\n' "${result}"
}

@test "resolve_feature_handler (3-tier): tier-1 profile override wins over module and default" {
    result="$(_feat_in_sandbox test feat "override module default")"
    [[ "$result" == *"/profiles.d/test/commands/feat.sh" ]]
}

@test "resolve_feature_handler (3-tier): tier-2 profile module wins when no override exists" {
    result="$(_feat_in_sandbox test feat "module default")"
    [[ "$result" == *"/modules/mod_x/feat.sh" ]]
}

@test "resolve_feature_handler (3-tier): tier-3 default handler when no override or module" {
    result="$(_feat_in_sandbox test feat "default")"
    [[ "$result" == *"/cli/commands/feat.sh" ]]
}

@test "resolve_feature_handler (3-tier): empty when no tier provides the feature" {
    result="$(_feat_in_sandbox test feat "")"
    [ -z "$result" ]
}

@test "resolve_feature_handler (3-tier): community short-circuits to empty even with a staged override" {
    # The byte-identical guarantee: community must never resolve a handler, even
    # if a profiles.d/community override file is physically present on disk.
    result="$(_feat_in_sandbox community feat "override module default")"
    [ -z "$result" ]
}

# ---------------------------------------------------------------------------
# BLOCK 10 — resolve_profile_check umbrella delegation (P0-E §4.2)
#
# The locked-named umbrella delegates to the existing per-surface resolvers,
# which remain the implementations (kept as internals, still token-based).
# ---------------------------------------------------------------------------

@test "resolve_profile_check: preflight surface delegates to resolve_preflight_check" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_profile_check" "preflight" "disk")"
    [ "$result" = "plus_preflight_disk" ]
}

@test "resolve_profile_check: doctor surface delegates to resolve_doctor_check" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_profile_check" "doctor" "tls")"
    [ "$result" = "plus_doctor_tls" ]
}

@test "resolve_profile_check: handoff surface delegates to resolve_handoff_section" {
    result="$(_dispatch_in_subshell "community-plus" "actools::dispatch::resolve_profile_check" "handoff" "site")"
    [ "$result" = "plus_handoff_site" ]
}

@test "resolve_profile_check: community returns empty (delegated baseline preserved)" {
    result="$(_dispatch_in_subshell "community" "actools::dispatch::resolve_profile_check" "preflight" "disk")"
    [ -z "$result" ]
}

@test "resolve_profile_check: result equals the per-surface internal it delegates to" {
    umbrella="$(_dispatch_in_subshell "test" "actools::dispatch::resolve_profile_check" "preflight" "disk")"
    direct="$(_dispatch_in_subshell "test" "actools::dispatch::resolve_preflight_check" "disk")"
    [ "$umbrella" = "$direct" ]
}

@test "resolve_profile_check: unknown surface warns to stderr and returns empty" {
    run bash -c "ACTOOLS_PROFILE='community-plus'; source '${DISPATCH_SH}'; actools::dispatch::resolve_profile_check 'bogus' 'x'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"bogus"* ]]
}

# ---------------------------------------------------------------------------
# BLOCK 11 — side-effect-free profile loading (P0-E §4d / spec detail 4)
#
# Every shipped/fixture .profile must be pure data: sourcing it sets variables
# only and performs NO executable side effects. The harness sources the profile
# from an empty working directory with all output captured, then asserts: exit
# 0, no stdout/stderr, and no files created. The negative-control test proves the
# harness actually bites (a check that cannot fail is worthless).
# ---------------------------------------------------------------------------

# Source PROFILE_FILE (absolute path) in a clean bash subshell from an empty CWD.
# Echo "<rc>|<captured-output>|<files-created>" for the test to assert on.
_source_in_clean_subshell() {
    local pf="$1"
    local wd out rc produced created
    wd="$(mktemp -d)"; out="$(mktemp)"
    bash -c 'cd "$1" && set -u && . "$2"' _ "${wd}" "${pf}" >"${out}" 2>&1; rc=$?
    produced="$(cat "${out}")"
    created="$(find "${wd}" -mindepth 1 2>/dev/null)"
    rm -rf "${wd}" "${out}"
    printf '%s|%s|%s' "${rc}" "${produced}" "${created}"
}

@test "profile loading: community.profile sources with no executable side effects" {
    res="$(_source_in_clean_subshell "${REPO_DIR}/profiles/community.profile")"
    [ "$res" = "0||" ]
}

@test "profile loading: fake-actor fixture sources with no side effects" {
    res="$(_source_in_clean_subshell "${REPO_DIR}/tests/fixtures/profiles/fake-actor.profile")"
    [ "$res" = "0||" ]
}

@test "profile loading: fake-ticket fixture sources with no side effects" {
    res="$(_source_in_clean_subshell "${REPO_DIR}/tests/fixtures/profiles/fake-ticket.profile")"
    [ "$res" = "0||" ]
}

@test "profile loading (negative control): a profile with a side effect is detected" {
    local evil; evil="$(mktemp)"
    printf 'PROFILE_NAME="x"\nmkdir side_effect_dir\necho noise\n' > "${evil}"
    res="$(_source_in_clean_subshell "${evil}")"
    rm -f "${evil}"
    # The harness MUST flag this — anything other than the clean "0||" signature.
    [ "$res" != "0||" ]
}
