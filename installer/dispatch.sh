#!/usr/bin/env bash
# =============================================================================
# installer/dispatch.sh — Resolver dispatch surface for Actools Drupal.
#
# Sourced by: installer/init.sh, installer/preflight.sh,
#             installer/handoff.sh, cli/commands/doctor.sh, cli/actools
# Source order: AFTER profile.sh (or the env file) has set ACTOOLS_PROFILE.
#
# Contract: every resolver function returns ONE token on stdout.
#   Empty stdout  = no profile-specific handler; caller uses default behaviour.
#   Non-empty     = call the named function instead of the default.
#
# Profile semantics:
#   community       — returns empty for all operations (no overrides; baseline)
#   community-plus  — returns "plus_<operation>" for operations with handlers
#   test            — returns "test_*" tokens (fixture profile, tests only)
#   <unknown>       — returns empty + emits WARN to stderr (fail-soft; default)
#
# D.0 defining property: community installs see ZERO behaviour change.
# Resolver calls land in D.1+; D.0 establishes the seam only.
#
# Required globals at source time:
#   INSTALL_DIR — repository / installation root
# =============================================================================

# Module guard — prevents redefinition warnings if sourced by multiple callers.
[[ "${_ACTOOLS_DISPATCH_SOURCED:-0}" -eq 1 ]] && return 0
readonly _ACTOOLS_DISPATCH_SOURCED=1

# set -u only — let callers' errexit handle exit semantics.
# Resolver functions never fail; they return empty on unknown profile.
set -u

# ---------------------------------------------------------------------------
# Allowed profile values — single source of truth for valid profile names.
# Adding a new profile: one entry here + one case branch in each resolver.
# ---------------------------------------------------------------------------
_ACTOOLS_ALLOWED_PROFILES=(community community-plus test)

# ---------------------------------------------------------------------------
# actools::dispatch::profile_is_valid PROFILE
#
# Returns 0 if PROFILE is in _ACTOOLS_ALLOWED_PROFILES, 1 otherwise.
# ---------------------------------------------------------------------------
actools::dispatch::profile_is_valid() {
    local candidate="${1:-}"
    local p
    for p in "${_ACTOOLS_ALLOWED_PROFILES[@]}"; do
        [[ "$p" == "$candidate" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# actools::dispatch::resolve_feature_handler FEATURE
#
# Returns the handler name for a named feature in the active profile.
# Callers use the result to decide which implementation to source/call.
# ---------------------------------------------------------------------------
actools::dispatch::resolve_feature_handler() {
    local feature="${1:-}"
    case "${ACTOOLS_PROFILE:-community}" in
        community)
            echo ""
            ;;
        community-plus)
            echo "plus_${feature}"
            ;;
        test)
            echo "test_${feature}"
            ;;
        *)
            echo "WARN: unknown ACTOOLS_PROFILE='${ACTOOLS_PROFILE}' — using community defaults" >&2
            echo ""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# actools::dispatch::resolve_preflight_check CHECK_ID
#
# Returns the handler name for a named preflight check in the active profile.
# ---------------------------------------------------------------------------
actools::dispatch::resolve_preflight_check() {
    local check="${1:-}"
    case "${ACTOOLS_PROFILE:-community}" in
        community)
            echo ""
            ;;
        community-plus)
            echo "plus_preflight_${check}"
            ;;
        test)
            echo "test_preflight_${check}"
            ;;
        *)
            echo "WARN: unknown ACTOOLS_PROFILE='${ACTOOLS_PROFILE}' — using community defaults" >&2
            echo ""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# actools::dispatch::resolve_doctor_check CHECK_ID
#
# Returns the handler name for a named doctor check in the active profile.
# ---------------------------------------------------------------------------
actools::dispatch::resolve_doctor_check() {
    local check="${1:-}"
    case "${ACTOOLS_PROFILE:-community}" in
        community)
            echo ""
            ;;
        community-plus)
            echo "plus_doctor_${check}"
            ;;
        test)
            echo "test_doctor_${check}"
            ;;
        *)
            echo "WARN: unknown ACTOOLS_PROFILE='${ACTOOLS_PROFILE}' — using community defaults" >&2
            echo ""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# actools::dispatch::resolve_handoff_section SECTION_ID
#
# Returns the handler name for a named handoff section in the active profile.
# ---------------------------------------------------------------------------
actools::dispatch::resolve_handoff_section() {
    local section="${1:-}"
    case "${ACTOOLS_PROFILE:-community}" in
        community)
            echo ""
            ;;
        community-plus)
            echo "plus_handoff_${section}"
            ;;
        test)
            echo "test_handoff_${section}"
            ;;
        *)
            echo "WARN: unknown ACTOOLS_PROFILE='${ACTOOLS_PROFILE}' — using community defaults" >&2
            echo ""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# actools::cli::resolve_profile CLI_PROFILE ENV_PROFILE
#
# Resolves the active profile from two potential sources:
#   $1 = --profile flag value from CLI (may be empty)
#   $2 = ACTOOLS_PROFILE from actools.env if present (may be empty)
#
# Outputs the resolved profile name on stdout.
# Exit codes:
#   0 — resolved cleanly
#   2 — conflict: CLI and env disagree on profile (operator must fix actools.env)
#   3 — invalid: the CLI value is not in _ACTOOLS_ALLOWED_PROFILES
#
# Per Decision 2: profile selection is deployment-defining. A conflict fails
# closed (exit 2) to prevent silent profile changes via CLI typo.
# ---------------------------------------------------------------------------
actools::cli::resolve_profile() {
    local cli_profile="${1:-}"
    local env_profile="${2:-}"

    # Validate the CLI value if provided.
    if [[ -n "$cli_profile" ]] && ! actools::dispatch::profile_is_valid "$cli_profile"; then
        echo "ERROR: --profile='${cli_profile}' is not a valid profile" >&2
        echo "       Allowed: ${_ACTOOLS_ALLOWED_PROFILES[*]}" >&2
        return 3
    fi

    # Conflict: both are set to DIFFERENT values — fail closed.
    if [[ -n "$cli_profile" && -n "$env_profile" && "$cli_profile" != "$env_profile" ]]; then
        echo "ERROR: --profile='${cli_profile}' conflicts with actools.env (ACTOOLS_PROFILE='${env_profile}')" >&2
        echo "       Profile selection is deployment-defining. To change profile:" >&2
        echo "         1. Edit actools.env directly: ACTOOLS_PROFILE=${cli_profile}" >&2
        echo "         2. OR remove ACTOOLS_PROFILE from actools.env and re-run with --profile=${cli_profile}" >&2
        return 2
    fi

    # Resolve: CLI value if provided, else env value, else default community.
    echo "${cli_profile:-${env_profile:-community}}"
    return 0
}
