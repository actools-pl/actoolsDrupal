#!/usr/bin/env bats
# =============================================================================
# tests/test_p0i_fake_profile_e2e.bats — P0-I: fake-profile end-to-end.
#
# One test file per phase (consolidation discipline; mirrors
# tests/test_d0_dispatch.bats / tests/test_p0h_dispatch.bats). This is the
# SINGLE e2e artifact — both .github/workflows/lint.yml (suite-in-CI, the fast
# PR merge gate) and .github/workflows/e2e.yml (the hermetic fake-profile job)
# invoke this same file, so the assertions live in exactly one place.
#
# WHAT THIS PROVES (the seam, end-to-end — not a live Drupal install)
#   Phase 0 hardened the dispatch SEAMS, not the Drupal install. So the e2e for
#   the seams is: load the REAL profiles/test.profile, set ACTOOLS_PROFILE=test,
#   drive every dispatch point through the REAL installer/dispatch.sh +
#   installer/profile.sh + the real surfaces, and assert a uniquely-named marker
#   for each. The full-install e2e already exists for `community` (e2e.yml). A
#   "VM-live" version would force exactly the two things Phase 0 scoped out:
#   routing the install spine through the selected profile (deferred) and a full
#   Drupal install driven by stub handlers (which cannot produce a working site).
#   Hermetic is therefore the correct shape of "e2e" here — and is why this phase
#   does not touch actools.sh.
#
# DISPATCH POINT -> MARKER -> ASSERTION (exhaustive; the Opus review bar)
#   install stage (inherited) host  -> resolve_install_stage -> test_host   -> stage_host.marker
#   install stage (inherited) stack -> ...                    -> test_stack  -> stage_stack.marker
#   install stage (inherited) db    -> ...                    -> test_db     -> stage_db.marker
#   install stage (inherited) drupal-> ...                    -> test_drupal -> stage_drupal.marker
#   install stage (inherited) worker-> ...                    -> test_worker -> stage_worker.marker
#   install stage (APPENDED)  seam  -> ...                    -> test_seam   -> stage_seam.marker   [append-only proof]
#   feature handler (generic)       -> resolve_feature_handler (Tier-1)      -> run_seam_feature -> feature_seam.marker
#   doctor deep handler             -> doctor --deep -> resolve_feature_handler(Tier-1) -> run_doctor_deep -> doctor_deep.marker (+ exit 7 + sentinel)
#   preflight extra (resolved)      -> run_preflight -> resolve_profile_check "preflight" -> test_preflight_check -> preflight_check.marker
#   preflight extra (unknown)       -> run_preflight -> declared 'missing', no handler -> hard FAIL (exit 1), no marker
#   handoff section                 -> run_handoff -> resolve_handoff_section -> test_handoff_section -> handoff_section.marker
#   init field + governance         -> run_init --profile test -> BEHAVIORAL (init dispatches no handler):
#                                        success -> exit 0 + ACTOOLS_PROFILE=test persisted + extra field NOT persisted
#                                        missing actor/ticket -> exit 1
#   (PROFILE_DOCTOR_EXTRA per-check loop is deferred — P0-H Entry 013 — so there
#    is no doctor-extra dispatch point; doctor's live point is the deep handler.)
#
# FAILURE PATHS
#   unknown profile -> exit 3 ; test profile missing actor/ticket -> exit 1.
#
# Community-unchanged is proved per-surface in test_p0h_dispatch.bats /
# *_test.bats (untouched); this file adds a marker-level invariant: community
# drives NONE of the P0-I markers.
# =============================================================================

setup() {
  REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="${REPO_DIR}/tests/fixtures/profiles"
  export ACTOOLS_PLAIN=1
  unset ACTOOLS_PROFILE 2>/dev/null || true
  unset BASE_DOMAIN 2>/dev/null || true
}

teardown() {
  [[ -n "${INSTALL_DIR:-}"        && -d "${INSTALL_DIR}" ]]        && rm -rf "${INSTALL_DIR}"
  [[ -n "${ACTOOLS_MARKER_DIR:-}" && -d "${ACTOOLS_MARKER_DIR}" ]] && rm -rf "${ACTOOLS_MARKER_DIR}"
  return 0
}

# Build a sandbox INSTALL_DIR staging the REAL loaders, surfaces, the REAL
# profiles/test.profile (+ community.profile it inherits), and the Tier-1
# override fixtures at resolve_feature_handler's override location. Also create
# a fresh marker dir and export ACTOOLS_MARKER_DIR + the globals the surfaces need.
_new_e2e_sandbox() {
  INSTALL_DIR="$(mktemp -d)";        export INSTALL_DIR
  ACTOOLS_MARKER_DIR="$(mktemp -d)"; export ACTOOLS_MARKER_DIR

  mkdir -p "${INSTALL_DIR}/installer" "${INSTALL_DIR}/cli/commands" \
           "${INSTALL_DIR}/profiles"  "${INSTALL_DIR}/profiles.d/test/commands" \
           "${INSTALL_DIR}/logs"

  # Real loaders + surfaces.
  cp "${REPO_DIR}/installer/dispatch.sh"  "${INSTALL_DIR}/installer/dispatch.sh"
  cp "${REPO_DIR}/installer/profile.sh"   "${INSTALL_DIR}/installer/profile.sh"
  cp "${REPO_DIR}/installer/output.sh"    "${INSTALL_DIR}/installer/output.sh"
  cp "${REPO_DIR}/installer/init.sh"      "${INSTALL_DIR}/installer/init.sh"
  cp "${REPO_DIR}/installer/preflight.sh" "${INSTALL_DIR}/installer/preflight.sh"
  cp "${REPO_DIR}/installer/handoff.sh"   "${INSTALL_DIR}/installer/handoff.sh"
  cp "${REPO_DIR}/cli/commands/doctor.sh"      "${INSTALL_DIR}/cli/commands/doctor.sh"
  cp "${REPO_DIR}/cli/commands/doctor_deep.sh" "${INSTALL_DIR}/cli/commands/doctor_deep.sh"  # baseline gate

  # The REAL loadable profile (and the community base it sources).
  cp "${REPO_DIR}/profiles/community.profile" "${INSTALL_DIR}/profiles/community.profile"
  cp "${REPO_DIR}/profiles/test.profile"      "${INSTALL_DIR}/profiles/test.profile"

  # Tier-1 ("active-profile command override") handlers for the feature resolver.
  cp "${FIXTURES}/test/commands/doctor_deep.sh"  "${INSTALL_DIR}/profiles.d/test/commands/doctor_deep.sh"
  cp "${FIXTURES}/test/commands/seam_feature.sh" "${INSTALL_DIR}/profiles.d/test/commands/seam_feature.sh"

  cp "${REPO_DIR}/actools.env.example" "${INSTALL_DIR}/actools.env.example"

  # Globals the surfaces read.
  export ENV_FILE="${INSTALL_DIR}/actools.env"
  export STATE_FILE="${INSTALL_DIR}/.actools-state.json"
  export REAL_HOME="${INSTALL_DIR}"
  export REAL_USER="${USER:-root}"
  export LOG_DIR="${INSTALL_DIR}/logs"
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=p0i-test.invalid
DRUPAL_ADMIN_EMAIL=admin@example.com
ACTOOLS_PROFILE=test
EOF
}

# Assert a marker file exists; on failure dump the marker dir for the CI log.
_assert_marker() {
  local name="$1"
  if [[ ! -f "${ACTOOLS_MARKER_DIR}/${name}.marker" ]]; then
    echo "MISSING marker: ${name}.marker"
    echo "Markers present in ${ACTOOLS_MARKER_DIR}:"
    ls -1 "${ACTOOLS_MARKER_DIR}" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    return 1
  fi
}

# ===========================================================================
# THE END-TO-END TEST — every dispatch point fires, every marker asserted.
# ===========================================================================

@test "e2e: every dispatch point fires under ACTOOLS_PROFILE=test (all markers present)" {
  _new_e2e_sandbox

  # --- (A) install-stage dispatcher: iterate the REAL profile's stage list ----
  # Drives run_install_stage over PROFILE_INSTALL_STAGES (host stack db drupal
  # worker seam). Under ACTOOLS_PROFILE=test every stage resolves to test_<stage>;
  # 'seam' proves append-only routing. Plus the generic feature resolver.
  run bash -c '
    set -u
    export INSTALL_DIR ACTOOLS_MARKER_DIR
    export ACTOOLS_PROFILE=test
    source "${INSTALL_DIR}/installer/dispatch.sh"
    source "${INSTALL_DIR}/installer/profile.sh"
    source "'"${FIXTURES}"'/test/stage_handlers.sh"
    for s in "${PROFILE_INSTALL_STAGES[@]}"; do
      actools::dispatch::run_install_stage "$s"
    done
    # generic feature handler (distinct from the doctor surface that consumes it)
    handler="$(actools::dispatch::resolve_feature_handler seam_feature)"
    [ -n "$handler" ] || { echo "feature resolver returned empty"; exit 1; }
    # shellcheck source=/dev/null
    source "$handler"
    run_seam_feature
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_STAGE_DISPATCHED:seam"* ]]
  [[ "$output" == *"TEST_FEATURE_HANDLER_DISPATCHED:seam_feature"* ]]

  # --- (B) preflight extra: resolved handler runs (marker), unknown hard-fails -
  source "${FIXTURES}/test/plus_preflight_check.sh"
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/preflight.sh"
  run run_preflight
  [[ "$output" == *"TEST_PREFLIGHT_DISPATCHED:check"* ]]
  [[ "$output" == *"missing"*"no handler installed"* ]]

  # --- (C) handoff section: *) arm resolves + renders the profile section ------
  source "${FIXTURES}/test/plus_handoff_section.sh"
  source "${INSTALL_DIR}/installer/handoff.sh"
  run run_handoff
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_HANDOFF_DISPATCHED:section"* ]]

  # --- (D) doctor --deep: resolve_feature_handler Tier-1 override runs ---------
  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  [ "$status" -eq 7 ]
  [[ "$output" == *"TEST_DOCTOR_DEEP_OVERRIDE_DISPATCHED"* ]]

  # --- ASSERT EVERY MARKER (the completeness bar) -----------------------------
  _assert_marker stage_host
  _assert_marker stage_stack
  _assert_marker stage_db
  _assert_marker stage_drupal
  _assert_marker stage_worker
  _assert_marker stage_seam          # appended stage reached its handler
  _assert_marker feature_seam        # generic feature resolver -> handler
  _assert_marker preflight_check     # preflight extra resolved -> handler
  _assert_marker handoff_section     # handoff section resolved -> handler
  _assert_marker doctor_deep         # doctor --deep resolved -> handler
}

# ===========================================================================
# Granular per-dispatch-point tests (a failure here pinpoints the broken seam).
# ===========================================================================

@test "install-stage: every stage in the test profile resolves to its test_<stage> handler and fires" {
  _new_e2e_sandbox
  run bash -c '
    set -u
    export INSTALL_DIR ACTOOLS_MARKER_DIR ACTOOLS_PROFILE=test
    source "${INSTALL_DIR}/installer/dispatch.sh"
    source "${INSTALL_DIR}/installer/profile.sh"
    source "'"${FIXTURES}"'/test/stage_handlers.sh"
    for s in "${PROFILE_INSTALL_STAGES[@]}"; do
      printf "%s->" "$s"
      actools::dispatch::resolve_install_stage "$s"
    done
  '
  [ "$status" -eq 0 ]
  # The resolver maps each stage to test_<stage> under the test profile.
  [[ "$output" == *"host->test_host"* ]]
  [[ "$output" == *"seam->test_seam"* ]]
}

@test "install-stage append-only: the appended 'seam' stage is present and reaches test_seam" {
  _new_e2e_sandbox
  run bash -c '
    set -u
    export INSTALL_DIR ACTOOLS_MARKER_DIR ACTOOLS_PROFILE=test
    source "${INSTALL_DIR}/installer/dispatch.sh"
    source "${INSTALL_DIR}/installer/profile.sh"
    source "'"${FIXTURES}"'/test/stage_handlers.sh"
    # The base community stages must still be present (append, not replace).
    echo "${PROFILE_INSTALL_STAGES[*]}"
    actools::dispatch::run_install_stage seam
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "host stack db drupal worker seam"* ]]
  [[ "$output" == *"TEST_STAGE_DISPATCHED:seam"* ]]
  _assert_marker stage_seam
}

@test "feature-handler: resolve_feature_handler resolves a generic feature to the Tier-1 override path and runs it" {
  _new_e2e_sandbox
  run bash -c '
    set -u
    export INSTALL_DIR ACTOOLS_MARKER_DIR ACTOOLS_PROFILE=test
    source "${INSTALL_DIR}/installer/dispatch.sh"
    source "${INSTALL_DIR}/installer/profile.sh"
    actools::dispatch::resolve_feature_handler seam_feature
  '
  [ "$status" -eq 0 ]
  # Tier-1 location: profiles.d/<profile>/commands/<feature>.sh
  [[ "$output" == *"/profiles.d/test/commands/seam_feature.sh" ]]
  # And running it writes the marker.
  source "${INSTALL_DIR}/profiles.d/test/commands/seam_feature.sh"
  run run_seam_feature
  [ "$status" -eq 0 ]
  _assert_marker feature_seam
}

@test "preflight: resolved extra runs (marker) and a declared-but-unhandled extra HARD-FAILS (exit 1)" {
  _new_e2e_sandbox
  source "${FIXTURES}/test/plus_preflight_check.sh"
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/preflight.sh"
  run run_preflight
  [[ "$output" == *"TEST_PREFLIGHT_DISPATCHED:check"* ]]
  [[ "$output" == *"missing"*"no handler installed"* ]]
  [[ "$output" != *"missing"*"SKIP"* ]]
  [ "$status" -eq 1 ]
  _assert_marker preflight_check
}

@test "doctor --deep: Tier-1 override is resolved + run (marker, sentinel, exit 7); built-in gate suppressed" {
  _new_e2e_sandbox
  source "${INSTALL_DIR}/cli/commands/doctor.sh"
  run run_doctor --deep
  [ "$status" -eq 7 ]
  [[ "$output" == *"TEST_DOCTOR_DEEP_OVERRIDE_DISPATCHED"* ]]
  [[ "$output" != *"not available in this edition"* ]]
  _assert_marker doctor_deep
}

@test "handoff: profile section resolves through the *) arm to its handler (marker)" {
  _new_e2e_sandbox
  source "${FIXTURES}/test/plus_handoff_section.sh"
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/handoff.sh"
  run run_handoff
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_HANDOFF_DISPATCHED:section"* ]]
  _assert_marker handoff_section
}

@test "init: test profile succeeds with governance flags; persists ACTOOLS_PROFILE=test; extra field not persisted" {
  _new_e2e_sandbox
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/init.sh"
  # test.profile requires actor + ticket; supply both. --force because the
  # sandbox env file (staged for the other surfaces) already exists.
  run run_init --profile test --domain example.com --email admin@example.com \
        --actor-id alice --change-ticket TICKET-123 --force
  [ "$status" -eq 0 ]
  [ -f "$ENV_FILE" ]
  grep -q '^ACTOOLS_PROFILE=test$' "$ENV_FILE"
  # Governance identity is validated but NOT persisted (P0-E/P0-H scope).
  ! grep -q 'alice' "$ENV_FILE"
  ! grep -q 'TICKET-123' "$ENV_FILE"
  # The extra PROFILE_INIT_FIELDS entry is collected as a no-op, not written.
  ! grep -q 'seam_field' "$ENV_FILE"
}

# ===========================================================================
# FAILURE PATHS
# ===========================================================================

@test "failure path: unknown profile fails cleanly (exit 3), nothing persisted" {
  _new_e2e_sandbox
  rm -f "$ENV_FILE"   # start clean so we can prove non-persistence
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/init.sh"
  run run_init --profile definitely-not-a-profile --domain example.com --email admin@example.com
  [ "$status" -eq 3 ]
  [[ "$output" == *"--profile"* ]]
  [ ! -f "$ENV_FILE" ]
}

@test "failure path: test profile without --actor-id/--change-ticket fails (exit 1), nothing persisted" {
  _new_e2e_sandbox
  rm -f "$ENV_FILE"   # start clean so we can prove non-persistence
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/init.sh"
  run run_init --profile test --domain example.com --email admin@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"--actor-id"* ]]
  [[ "$output" == *"--change-ticket"* ]]
  [ ! -f "$ENV_FILE" ]
}

# ===========================================================================
# INVARIANTS / HYGIENE
# ===========================================================================

@test "community routes through NONE of the P0-I markers" {
  _new_e2e_sandbox
  # Point the surfaces at community (the resolvers short-circuit to empty).
  cat > "$ENV_FILE" <<'EOF'
BASE_DOMAIN=p0i-test.invalid
DRUPAL_ADMIN_EMAIL=admin@example.com
ACTOOLS_PROFILE=community
EOF
  # Define the test_* handlers in-shell so that IF community wrongly resolved to
  # one, a marker WOULD be written — making this a biting check.
  source "${FIXTURES}/test/stage_handlers.sh"
  source "${FIXTURES}/test/plus_preflight_check.sh"
  source "${FIXTURES}/test/plus_handoff_section.sh"
  source "${INSTALL_DIR}/installer/output.sh"
  source "${INSTALL_DIR}/installer/preflight.sh"
  source "${INSTALL_DIR}/installer/handoff.sh"
  source "${INSTALL_DIR}/cli/commands/doctor.sh"

  run run_preflight       # community: extra loop body never runs
  run run_handoff         # community: every section hits an explicit arm
  run run_doctor --deep   # community: built-in gate, not the override

  # Resolver-level: community install stages resolve to the base handlers.
  run bash -c '
    set -u; export INSTALL_DIR ACTOOLS_PROFILE=community
    source "${INSTALL_DIR}/installer/dispatch.sh"
    actools::dispatch::resolve_install_stage host
  '
  [ "$output" = "actools::install::stage_host" ]

  # No P0-I marker may exist.
  local present
  present="$(ls -1 "${ACTOOLS_MARKER_DIR}" 2>/dev/null)"
  if [[ -n "$present" ]]; then
    echo "community wrongly produced markers:"; echo "$present" | sed 's/^/  /'
    return 1
  fi
}

@test "profiles/test.profile is pure data (no executable side effects) when sourced via the loader" {
  # It inherits via 'source community.profile', so INSTALL_DIR must be set — the
  # profile-loader contract (installer/profile.sh) guarantees this. Sourced that
  # way it must still produce no output and create no files (pure data). The
  # negative control in test_d0_dispatch.bats proves this harness shape bites.
  local wd out rc produced created
  wd="$(mktemp -d)"; out="$(mktemp)"
  bash -c 'cd "$1" && set -u && INSTALL_DIR="$3" && . "$2"' _ \
       "${wd}" "${REPO_DIR}/profiles/test.profile" "${REPO_DIR}" >"${out}" 2>&1
  rc=$?
  produced="$(cat "${out}")"
  created="$(find "${wd}" -mindepth 1 2>/dev/null)"
  rm -rf "${wd}" "${out}"
  [ "$rc" -eq 0 ]
  [ -z "$produced" ]
  [ -z "$created" ]
}

@test "guard: actools.sh is executable (exec-bit standing guard — the P0-G regression)" {
  # Working-tree bit — covers a checkout/extraction that preserves file modes.
  [ -x "${REPO_DIR}/actools.sh" ]
  # Committed index mode — the meaningful guard against committing a
  # non-executable entry point (the exact regression that broke the P0-G
  # install). Run only inside a git work tree (CI checkout + local dev have one;
  # a bare zip export may not), so the suite stays runnable everywhere.
  if git -C "${REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    run git -C "${REPO_DIR}" ls-files -s -- actools.sh
    [ "$status" -eq 0 ]
    [ -n "$output" ]                 # actools.sh is tracked
    [[ "$output" == 100755\ * ]]     # mode is 100755 (executable)
  fi
}
