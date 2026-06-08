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

# =============================================================================
# Install-stage dispatcher (P0-D)
#
# Routes the default `fresh` install through PROFILE_INSTALL_STAGES instead of
# a hardcoded call sequence. This is the seam that makes the install order
# profile-driven and append-only (LOCKED Decision 3: community-plus *appends*
# plus_* stages; it never replaces a community stage).
#
# Stage -> handler mapping for P0-D (behavior-preserving; full per-stage module
# decomposition is P0-G, NOT this phase). The flat community stage list
# (host stack db drupal worker) does not yet map one-to-one onto the two coarse
# monoliths, so stages are wired as follows:
#
#   host    -> no-op  (host provisioning is folded inside setup_stack until P0-G)
#   stack   -> setup_stack            (builds host + container stack + worker)
#   db      -> no-op  (DB creation is folded inside the per-env install_env loop,
#                      which runs at the `drupal` stage, until P0-G)
#   drupal  -> the full per-environment install_env loop, copied verbatim from
#              main() (ENVIRONMENTS split + total-RAM probe + low-RAM sequential
#              downgrade + parallel/sequential branch). Until P0-G this single
#              handler covers BOTH the db and drupal stages.
#   worker  -> no-op  (the worker container is built inside setup_stack until P0-G)
#
# Iterating host->stack->db->drupal->worker therefore executes exactly:
#   (no-op) -> setup_stack -> (no-op) -> install_env loop -> (no-op)
# which is byte-for-byte the legacy sequence. The db-vs-drupal grouping (DB work
# anchored under the drupal handler) is a documented judgment call; it is
# trivially flippable and both arrangements keep the golden net green.
# =============================================================================

# ---------------------------------------------------------------------------
# actools::dispatch::resolve_install_stage STAGE
#
# Returns the handler function name for an install STAGE in the active profile.
# Mirrors the resolver convention above, with one deliberate asymmetry: the
# feature/preflight/doctor/handoff resolvers echo "" for community (callers
# there treat empty as "run the default inline"), but an install stage MUST
# resolve to a concrete, runnable function because run_install_stage calls it.
# So community (and the unknown-profile fallback) resolve to the base handler
# `actools::install::stage_<stage>` rather than to empty.
# ---------------------------------------------------------------------------
actools::dispatch::resolve_install_stage() {
    local stage="${1:-}"
    case "${ACTOOLS_PROFILE:-community}" in
        community)
            echo "actools::install::stage_${stage}"
            ;;
        community-plus)
            echo "plus_${stage}"
            ;;
        test)
            echo "test_${stage}"
            ;;
        *)
            echo "WARN: unknown ACTOOLS_PROFILE='${ACTOOLS_PROFILE}' — using community defaults" >&2
            echo "actools::install::stage_${stage}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# actools::dispatch::run_install_stage STAGE
#
# Resolves STAGE to its handler, verifies the handler is a defined function,
# and invokes it. Returns the handler's exit status.
#
# Emits NOTHING on the happy community path (every community stage resolves to
# a defined base handler), so install output stays byte-identical. The error
# branch only fires if a profile names a stage whose handler is not defined —
# a wiring bug that must fail loudly rather than silently skip an install step.
# ---------------------------------------------------------------------------
actools::dispatch::run_install_stage() {
    local stage="${1:-}"
    local handler
    handler="$(actools::dispatch::resolve_install_stage "$stage")"

    if ! declare -F "$handler" >/dev/null 2>&1; then
        echo "ERROR: install stage '${stage}' resolved to undefined handler '${handler}'" >&2
        return 1
    fi

    "$handler" "$stage"
}

# ---------------------------------------------------------------------------
# Community base stage handlers.
#
# These are the concrete functions resolve_install_stage returns for the
# community profile. Each either calls an existing monolith UNCHANGED or is a
# documented no-op for logic currently folded into another monolith (see the
# mapping table above). They take the stage name as $1 for signature
# uniformity, but the community handlers do not need it.
# ---------------------------------------------------------------------------

# host: folded into setup_stack until P0-G.
actools::install::stage_host() { :; }

# stack: build host + container stack + worker via the setup_stack monolith.
actools::install::stage_stack() {
    setup_stack
}

# db: folded into the per-env install_env loop (runs at the drupal stage) until P0-G.
actools::install::stage_db() { :; }

# drupal: the full per-environment install loop, verbatim from legacy main().
# NOTE: PARALLEL_INSTALL is intentionally NOT declared local so the low-RAM
# downgrade mutates the same global the legacy code did; ENVS/TOTAL_RAM/env are
# local because every other use site re-derives them and nothing reads them
# after this loop.
actools::install::stage_drupal() {
    local ENVS TOTAL_RAM env
    IFS=',' read -ra ENVS <<< "$ENVIRONMENTS"

    TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
    if [[ "${PARALLEL_INSTALL:-false}" == "true" ]] && (( TOTAL_RAM < 6000 )); then
        warn "Only ${TOTAL_RAM}MB RAM -- forcing sequential install."
        PARALLEL_INSTALL=false
    fi

    if [[ "${PARALLEL_INSTALL:-false}" == "true" ]]; then
        log "Parallel install (${TOTAL_RAM}MB RAM)..."
        for env in "${ENVS[@]}"; do install_env "${env// /}" & done
        wait
        log "All environments installed."
    else
        for env in "${ENVS[@]}"; do install_env "${env// /}"; done
    fi
}

# worker: folded into setup_stack until P0-G.
actools::install::stage_worker() { :; }
