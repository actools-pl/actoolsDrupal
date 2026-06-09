#!/usr/bin/env bats
# =============================================================================
# tests/installer/dispatch_stages_test.bats — Install-stage dispatcher (P0-D)
#
# Verifies the install-stage dispatcher added in installer/dispatch.sh and the
# stage loop wired into actools.sh main(). Three concerns:
#
#   BLOCK 1 — Default stage order. With ACTOOLS_PROFILE=community the loop
#             drives stages in EXACTLY host stack db drupal worker order.
#             Asserted with stubbed stage handlers (a traced/dry harness), not
#             a live install.
#
#   BLOCK 2 — Behaviour preservation + append-only stage guard.
#             (a) The REAL community handlers reproduce the legacy call
#                 sequence: host -> the modules/host/* functions in the
#                 canonical monolith order (P0-G); stack -> setup_stack once;
#                 drupal -> the per-env install_env loop (incl. the low-RAM
#                 downgrade); db/worker are documented no-ops folded elsewhere
#                 until a later phase.
#             (b) community's PROFILE_INSTALL_STAGES is EXACTLY
#                 (host stack db drupal worker) and no profile REPLACES a
#                 community stage rather than appending to it (alignment §4.5
#                 part 1; LOCKED §10 Risk 1). Mirrors the sibling-scope guard
#                 in tests/test_d0_dispatch.bats.
#
#   BLOCK 3 — Resolver correctness. resolve_install_stage returns the expected
#             base handler per community stage, and the documented fail-soft
#             fallback (WARN + community base handler) for an unknown profile;
#             run_install_stage fails loudly on an undefined handler.
# =============================================================================

setup() {
    # Repo root is two levels up from tests/installer/.
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    DISPATCH_SH="${REPO_DIR}/installer/dispatch.sh"
    PROFILE_SH="${REPO_DIR}/profiles/community.profile"
    export REPO_DIR DISPATCH_SH PROFILE_SH

    # Clean profile/guard state so each test sources fresh.
    unset ACTOOLS_PROFILE 2>/dev/null || true
    unset _ACTOOLS_DISPATCH_SOURCED 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# BLOCK 1 — Default stage order (stubbed handlers; dry harness)
# ---------------------------------------------------------------------------

@test "dispatcher drives stages in exact order host stack db drupal worker (community)" {
    run bash -c '
        export ACTOOLS_PROFILE=community
        source "$DISPATCH_SH"
        # Override the five base handlers with recorders AFTER sourcing so the
        # loop records call order instead of performing a real install.
        actools::install::stage_host()   { echo host; }
        actools::install::stage_stack()  { echo stack; }
        actools::install::stage_db()     { echo db; }
        actools::install::stage_drupal() { echo drupal; }
        actools::install::stage_worker() { echo worker; }
        source "$PROFILE_SH"
        for s in "${PROFILE_INSTALL_STAGES[@]}"; do
            actools::dispatch::run_install_stage "$s"
        done
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "host" ]
    [ "${lines[1]}" = "stack" ]
    [ "${lines[2]}" = "db" ]
    [ "${lines[3]}" = "drupal" ]
    [ "${lines[4]}" = "worker" ]
    [ "${#lines[@]}" -eq 5 ]
}

@test "run_install_stage passes the stage name through to its handler" {
    run bash -c '
        export ACTOOLS_PROFILE=community
        source "$DISPATCH_SH"
        actools::install::stage_stack() { echo "handler-got:$1"; }
        actools::dispatch::run_install_stage stack
    '
    [ "$status" -eq 0 ]
    [ "$output" = "handler-got:stack" ]
}

# ---------------------------------------------------------------------------
# BLOCK 2a — Behaviour preservation: real handlers reproduce legacy sequence
# ---------------------------------------------------------------------------

@test "real handlers: stack->setup_stack once, drupal->install_env per env, in legacy order (sequential)" {
    run bash -c '
        export ACTOOLS_PROFILE=community
        export ENVIRONMENTS="prod,stage"
        export PARALLEL_INSTALL=false
        # Stub the monoliths + output helpers the real handlers call.
        setup_stack() { echo "setup_stack"; }
        install_env() { echo "install_env:$1"; }
        warn() { echo "WARN:$*"; }
        log()  { :; }
        free() { echo "Mem: 16000"; }   # deterministic RAM probe (no downgrade)
        # stage_host (P0-G) drives the host modules; stub them to silent no-ops
        # here so this test stays focused on the stack + drupal sequence. Their
        # ordering is asserted in the dedicated host-stage test below.
        install_packages()    { :; }
        setup_age_keypair()   { :; }
        tune_kernel()         { :; }
        configure_swap()      { :; }
        configure_firewall()  { :; }
        install_docker()      { :; }
        configure_logrotate() { :; }
        source "$DISPATCH_SH"
        source "$PROFILE_SH"
        for s in "${PROFILE_INSTALL_STAGES[@]}"; do
            actools::dispatch::run_install_stage "$s"
        done
    '
    [ "$status" -eq 0 ]
    # host modules stubbed silent here; db/worker are no-ops; only setup_stack
    # then the per-env loop emit.
    [ "${lines[0]}" = "setup_stack" ]
    [ "${lines[1]}" = "install_env:prod" ]
    [ "${lines[2]}" = "install_env:stage" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "real handlers: drupal handler preserves low-RAM downgrade (parallel + <6000MB -> sequential + warn)" {
    run bash -c '
        export ACTOOLS_PROFILE=community
        export ENVIRONMENTS="prod,stage"
        export PARALLEL_INSTALL=true
        setup_stack() { echo "setup_stack"; }
        install_env() { echo "install_env:$1"; }
        warn() { echo "WARN:$*"; }
        log()  { echo "LOG:$*"; }
        free() { echo "Mem: 4000"; }    # < 6000 -> force sequential
        source "$DISPATCH_SH"
        source "$PROFILE_SH"
        for s in "${PROFILE_INSTALL_STAGES[@]}"; do
            actools::dispatch::run_install_stage "$s"
        done
    '
    [ "$status" -eq 0 ]
    # Downgrade message fires, and the install runs sequentially (deterministic
    # order). No "Parallel install" log line is emitted.
    [[ "$output" == *"forcing sequential install"* ]]
    [[ "$output" == *"install_env:prod"* ]]
    [[ "$output" == *"install_env:stage"* ]]
    [[ "$output" != *"Parallel install"* ]]
}

@test "real handler: stage_host drives the host modules in canonical monolith order (P0-G)" {
    run bash -c '
        export ACTOOLS_PROFILE=community
        source "$DISPATCH_SH"
        # Recorder stubs for the host module functions. stage_host does NOT
        # source the modules (actools.sh sources them at startup), so these
        # stubs are exactly what the real handler invokes.
        install_packages()    { echo "install_packages"; }
        setup_age_keypair()   { echo "setup_age_keypair"; }
        tune_kernel()         { echo "tune_kernel"; }
        configure_swap()      { echo "configure_swap"; }
        configure_firewall()  { echo "configure_firewall"; }
        install_docker()      { echo "install_docker"; }
        configure_logrotate() { echo "configure_logrotate"; }
        actools::dispatch::run_install_stage host
    '
    [ "$status" -eq 0 ]
    # Exact legacy top-level order: packages (so the `age` package exists) ->
    # age keypair -> kernel -> swap -> firewall -> docker -> logrotate.
    [ "${lines[0]}" = "install_packages" ]
    [ "${lines[1]}" = "setup_age_keypair" ]
    [ "${lines[2]}" = "tune_kernel" ]
    [ "${lines[3]}" = "configure_swap" ]
    [ "${lines[4]}" = "configure_firewall" ]
    [ "${lines[5]}" = "install_docker" ]
    [ "${lines[6]}" = "configure_logrotate" ]
    [ "${#lines[@]}" -eq 7 ]
}

# ---------------------------------------------------------------------------
# BLOCK 2b — Append-only stage guard (alignment §4.5 part 1)
# ---------------------------------------------------------------------------

@test "community PROFILE_INSTALL_STAGES is exactly (host stack db drupal worker)" {
    run bash -c '
        source "$PROFILE_SH"
        echo "${PROFILE_INSTALL_STAGES[*]}"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "host stack db drupal worker" ]
}

@test "append-only guard: no profile REPLACES a community stage (bare = reassignment)" {
    # Community is the base definer (one bare assignment is correct). Every
    # OTHER profile must extend via += , never reassign PROFILE_INSTALL_STAGES.
    # Mirrors the offenders-collection shape of the sibling-scope audit.
    local offenders=()
    local f
    for f in "${REPO_DIR}"/profiles/*.profile; do
        [ -e "$f" ] || continue
        # The canonical base list lives in community.profile — skip it.
        [[ "$f" == *"/community.profile" ]] && continue
        # A bare `PROFILE_INSTALL_STAGES=(` (not `+=`) REPLACES the inherited
        # community list — forbidden. `PROFILE_INSTALL_STAGES+=(` is allowed.
        if grep -Eq '^[[:space:]]*PROFILE_INSTALL_STAGES=\(' "$f"; then
            offenders+=("$f")
        fi
    done

    if [ "${#offenders[@]}" -gt 0 ]; then
        echo "Profiles that REPLACE (not append) PROFILE_INSTALL_STAGES:"
        printf '  %s\n' "${offenders[@]}"
        return 1
    fi
}

@test "append-only guard: community.profile defines the base list via a single bare assignment" {
    # Sanity anchor for the guard above: the base definer uses exactly one bare
    # assignment, and does not also append to itself.
    run bash -c "grep -Ec '^[[:space:]]*PROFILE_INSTALL_STAGES=\\(' \"\$PROFILE_SH\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run bash -c "grep -Ec '^[[:space:]]*PROFILE_INSTALL_STAGES\\+=\\(' \"\$PROFILE_SH\""
    [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# BLOCK 3 — Resolver correctness
# ---------------------------------------------------------------------------

@test "resolve_install_stage returns the community base handler for each stage" {
    run bash -c '
        export ACTOOLS_PROFILE=community
        source "$DISPATCH_SH"
        for s in host stack db drupal worker; do
            actools::dispatch::resolve_install_stage "$s"
        done
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "actools::install::stage_host" ]
    [ "${lines[1]}" = "actools::install::stage_stack" ]
    [ "${lines[2]}" = "actools::install::stage_db" ]
    [ "${lines[3]}" = "actools::install::stage_drupal" ]
    [ "${lines[4]}" = "actools::install::stage_worker" ]
}

@test "resolve_install_stage defaults to community base handler when ACTOOLS_PROFILE is unset" {
    run bash -c '
        unset ACTOOLS_PROFILE
        source "$DISPATCH_SH"
        actools::dispatch::resolve_install_stage drupal
    '
    [ "$status" -eq 0 ]
    [ "$output" = "actools::install::stage_drupal" ]
}

@test "resolve_install_stage on unknown profile WARNs to stderr and falls back to community base handler" {
    run bash -c '
        export ACTOOLS_PROFILE=bogus-profile
        source "$DISPATCH_SH"
        actools::dispatch::resolve_install_stage stack
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: unknown ACTOOLS_PROFILE"* ]]
    [[ "$output" == *"actools::install::stage_stack"* ]]
}

@test "run_install_stage fails loudly when a stage resolves to an undefined handler" {
    # The 'test' profile resolves stages to test_<stage> handlers, which are not
    # defined for install stages yet (placeholders for later phases). This must
    # error, never silently skip an install step.
    run bash -c '
        export ACTOOLS_PROFILE=test
        source "$DISPATCH_SH"
        actools::dispatch::run_install_stage stack
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"undefined handler"* ]]
    [[ "$output" == *"test_stack"* ]]
}

@test "resolve_install_stage returns plus_<stage> under community-plus (append scaffolding)" {
    run bash -c '
        export ACTOOLS_PROFILE=community-plus
        source "$DISPATCH_SH"
        actools::dispatch::resolve_install_stage stack
    '
    [ "$status" -eq 0 ]
    [ "$output" = "plus_stack" ]
}
