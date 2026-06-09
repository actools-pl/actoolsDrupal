#!/usr/bin/env bash
# =============================================================================
# installer/dispatch.sh — Resolver dispatch surface for Actools Drupal.
#
# Sourced by: installer/init.sh, installer/preflight.sh,
#             installer/handoff.sh, cli/commands/doctor.sh, cli/actools
# Source order: AFTER profile.sh (or the env file) has set ACTOOLS_PROFILE.
#
# Contract: resolver functions return ONE value on stdout.
#   Empty stdout  = no profile-specific handler; caller uses default behaviour.
#   Non-empty     = the handler to use instead of the default.
#
# Return-shape asymmetry (made explicit at P0-E):
#   - resolve_feature_handler returns a FILE PATH to a handler script (3-tier
#     resolution: active-profile override -> profile module -> default gate),
#     or empty when nothing is found. See its header for the tiers.
#   - resolve_preflight_check / resolve_doctor_check / resolve_handoff_section
#     return a TOKEN (a function name like plus_*/test_*), or empty. These stay
#     token-based until their live surfaces are wired (P0-H).
#   - resolve_install_stage returns a concrete function NAME (never empty), as
#     run_install_stage invokes it directly (P0-D).
#   - resolve_profile_check is the locked-named umbrella that delegates to the
#     per-surface token resolvers above.
#
# Profile semantics:
#   community       — returns empty/base for all operations (no overrides; baseline)
#   community-plus  — returns plus_* tokens / resolved paths for handled operations
#   test            — returns test_* tokens (fixture profile, tests only)
#   <unknown>       — returns empty + emits WARN to stderr (fail-soft; default)
#
# D.0 defining property: community installs see ZERO behaviour change.
# resolve_feature_handler / resolve_profile_check are internal primitives with
# no live call sites yet; their callers land in P0-H. D.0 established the seam.
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
# Resolves a named feature to the PATH of the handler script that implements it
# for the active profile, using the LOCKED 3-tier order (alignment §4.1):
#
#   Tier 1  ${INSTALL_DIR}/profiles.d/${ACTOOLS_PROFILE}/commands/${FEATURE}.sh
#           (active-profile command override)
#   Tier 2  ${INSTALL_DIR}/modules/${module}/${FEATURE}.sh
#           for each module the active profile lists in PROFILE_FEATURE_MODULES
#   Tier 3  ${INSTALL_DIR}/cli/commands/${FEATURE}.sh
#           (the default handler / existing gate stub)
#
# The FIRST existing path wins; if none exist, output is empty (the caller then
# runs its inline default). This is a deliberate change from the pre-P0-E token
# contract — and it is safe because resolve_feature_handler has NO live call
# sites yet (its callers are wired in P0-H).
#
# community short-circuits to empty BEFORE the 3-tier search: no community
# override/module/default ships, so the search would yield empty anyway, but
# the explicit short-circuit keeps community byte-identical and intent-clear
# (alignment §4.1: "Returning empty for community is the correct baseline and
# must be preserved").
#
# PROFILE_FEATURE_MODULES is an INTERNAL resolver convention used only by Tier
# 2. It is intentionally NOT part of the public profile contract documented in
# profiles/README.md and is NOT set by community.profile; only profiles that
# ship feature modules define it. Read set -u-safely via a +x guard so its
# absence (the common case) is a no-op.
# ---------------------------------------------------------------------------
actools::dispatch::resolve_feature_handler() {
    local feature="${1:-}"
    local profile="${ACTOOLS_PROFILE:-community}"

    # community: preserved baseline — always empty (byte-identical).
    if [[ "$profile" == "community" ]]; then
        echo ""
        return 0
    fi

    # unknown profile: fail-soft — WARN to stderr, empty stdout (preserved).
    if ! actools::dispatch::profile_is_valid "$profile"; then
        echo "WARN: unknown ACTOOLS_PROFILE='${profile}' — using community defaults" >&2
        echo ""
        return 0
    fi

    local base="${INSTALL_DIR:-}"

    # Tier 1 — active-profile command override.
    local _override="${base}/profiles.d/${profile}/commands/${feature}.sh"
    if [[ -f "$_override" ]]; then
        echo "$_override"
        return 0
    fi

    # Tier 2 — a module the active profile lists provides the feature.
    if [[ -n "${PROFILE_FEATURE_MODULES+x}" ]]; then
        local _mod _candidate
        for _mod in "${PROFILE_FEATURE_MODULES[@]}"; do
            _candidate="${base}/modules/${_mod}/${feature}.sh"
            if [[ -f "$_candidate" ]]; then
                echo "$_candidate"
                return 0
            fi
        done
    fi

    # Tier 3 — default handler (or existing gate stub).
    local _default="${base}/cli/commands/${feature}.sh"
    if [[ -f "$_default" ]]; then
        echo "$_default"
        return 0
    fi

    # No handler anywhere — empty; caller uses its inline default.
    echo ""
    return 0
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
# actools::dispatch::resolve_profile_check SURFACE CHECK_ID
#
# Locked-named umbrella (LOCKED §6 item 1 / Decision 1; alignment §4.2). The
# spec names a single generic resolve_profile_check "<surface>" "<check_id>";
# the repo implemented per-surface resolvers. This delegates to those existing
# internals so the locked name resolves without re-opening the design. The
# per-surface resolvers remain the implementations (kept as internals) and are
# still token-based until their live surfaces are wired (P0-H).
#
#   surface = preflight -> resolve_preflight_check
#   surface = doctor    -> resolve_doctor_check
#   surface = handoff   -> resolve_handoff_section
#   <other>             -> WARN to stderr + empty (fail-soft)
# ---------------------------------------------------------------------------
actools::dispatch::resolve_profile_check() {
    local surface="${1:-}"
    local check_id="${2:-}"
    case "$surface" in
        preflight) actools::dispatch::resolve_preflight_check "$check_id" ;;
        doctor)    actools::dispatch::resolve_doctor_check "$check_id" ;;
        handoff)   actools::dispatch::resolve_handoff_section "$check_id" ;;
        *)
            echo "WARN: unknown profile-check surface='${surface}' — no handler" >&2
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
# Stage -> handler mapping. Host decomposition landed in P0-G (the host stage
# now drives modules/host/*); DB-user and worker-runtime decomposition remain
# folded for a later phase. The community stage list (host stack db drupal
# worker) is wired as follows:
#
#   host    -> install_packages -> setup_age_keypair -> tune_kernel ->
#              configure_swap -> configure_firewall -> install_docker ->
#              configure_logrotate  (modules/host/*, canonical monolith order; P0-G)
#   stack   -> setup_stack            (builds the container stack + worker image)
#   db      -> no-op  (DB creation is folded inside the per-env install_env loop,
#                      which runs at the `drupal` stage, until a later phase)
#   drupal  -> the full per-environment install_env loop, copied verbatim from
#              main() (ENVIRONMENTS split + total-RAM probe + low-RAM sequential
#              downgrade + parallel/sequential branch). This single handler
#              still covers BOTH the db and drupal stages.
#   worker  -> no-op  (the worker container runtime is built inside setup_stack
#                      until a later phase; P0-G moved only the worker IMAGE build)
#
# Iterating host->stack->db->drupal->worker therefore executes:
#   host modules -> setup_stack -> (no-op) -> install_env loop -> (no-op)
# The fresh-install generated output stays byte-for-byte identical; host
# provisioning now runs at the host stage (after the confirm prompt) instead of
# at top-level script load, so dry-run/update/env no longer re-provision the
# host. The db-vs-drupal grouping (DB work anchored under the drupal handler) is
# a documented judgment call; it is trivially flippable and both arrangements
# keep the golden net green.
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

# host: provisions the host via modules/host/* (P0-G). The modules are sourced
# at startup by actools.sh; this stage drives their functions in the canonical
# monolith order — the order the legacy top-level host block ran top-to-bottom.
# install_packages must precede setup_age_keypair so the `age` package exists.
actools::install::stage_host() {
    install_packages
    setup_age_keypair
    tune_kernel
    configure_swap
    configure_firewall
    install_docker
    configure_logrotate
}

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
