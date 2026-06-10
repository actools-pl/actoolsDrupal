# =============================================================================
# profiles/test.profile — TEST-ONLY seam-exercise profile (P0-I).
#
# WHAT THIS IS
#   A loadable profile (selectable via ACTOOLS_PROFILE=test) whose sole purpose
#   is to drive the Phase-0 dispatch seams end-to-end. It is NOT a production
#   profile and ships no real community-plus features: every handler it routes
#   to is a marker-writing stub (see tests/fixtures/profiles/test/* and
#   tests/fixtures/profiles/test/commands/*). 'test' is the test-friendly
#   allowed profile name (see _ACTOOLS_ALLOWED_PROFILES in installer/dispatch.sh).
#
#   The community live install never selects this profile — actools.sh::main()
#   sources community.profile directly (install-spine profile *selection* is a
#   deliberately-deferred concern), so shipping this file is inert for community
#   operators. It exists so the fake-profile e2e (tests/test_p0i_fake_profile_e2e.bats)
#   can load the REAL profile, not only a bats fixture.
#
# INHERITANCE / APPEND-ONLY (LOCKED Decision 3; alignment §4.5)
#   This profile inherits the community base by sourcing community.profile, then
#   EXTENDS the arrays with += (it never re-assigns PROFILE_INSTALL_STAGES). This
#   is the documented downstream-profile pattern (profiles/README.md §Inheritance)
#   and is exactly what keeps it append-only: the CI append-only stage guard
#   (tests/installer/dispatch_stages_test.bats) flags any non-community profile
#   that REPLACES (bare-assigns) PROFILE_INSTALL_STAGES, and this file passes it.
#
#   Because it inherits via source, INSTALL_DIR must be set at source time — the
#   profile-loader contract (installer/profile.sh) guarantees this. (The
#   self-contained governance fixtures under tests/fixtures/profiles/ do NOT
#   inherit, which is why they source cleanly with no INSTALL_DIR.)
#
# DISPATCH POINTS DECLARED HERE (each is exercised + marker-asserted by the e2e)
#   - install stage ......... PROFILE_INSTALL_STAGES += seam   (append-only)
#   - preflight extra ....... PROFILE_PREFLIGHT_EXTRA = (check missing)
#                             'check' resolves to an installed handler;
#                             'missing' has none -> hard FAIL (non-default profile)
#   - handoff section ....... PROFILE_HANDOFF_SECTIONS += section (non-built-in)
#   - init field ............ PROFILE_INIT_FIELDS += seam_field   (extra; no-op collect)
#   - governance ............ PROFILE_REQUIRES_ACTOR / _CHANGE_TICKET = true
#   - feature handler ....... resolved via resolve_feature_handler Tier-1
#                             (profiles.d/test/commands/seam_feature.sh) by the e2e
#   - doctor deep handler ... resolved via resolve_feature_handler Tier-1
#                             (profiles.d/test/commands/doctor_deep.sh) by `doctor --deep`
#   PROFILE_DOCTOR_EXTRA stays empty: doctor's per-check extra loop is deferred
#   (P0-H Entry 013); doctor's live dispatch point is the deep handler above.
#
# This file is sourced — keep it valid shell with NO executable side effects
# beyond inheriting the base (variable assignments only).
# =============================================================================

# Inherit the community base (sets the canonical PROFILE_* contract + the base
# PROFILE_INSTALL_STAGES=(host stack db drupal worker) we append to below).
# shellcheck source=/dev/null
source "${INSTALL_DIR}/profiles/community.profile"

PROFILE_NAME="test"
PROFILE_DISPLAY="Actools Drupal Test (seam exercise)"

# Governance: this profile REQUIRES both an actor identity AND a change ticket at
# init, so the e2e can prove the missing-actor/ticket failure path (exit 1).
PROFILE_REQUIRES_ACTOR=true
PROFILE_REQUIRES_CHANGE_TICKET=true

# init: base fields (domain email site-name, inherited) PLUS one extra to drive
# init's PROFILE_INIT_FIELDS-consumption "extra" branch. Phase 0 collects extras
# as a no-op (neither validated nor persisted), so init still succeeds and the
# extra is NOT written to actools.env.
PROFILE_INIT_FIELDS+=(seam_field)

# preflight: 'check' resolves to an installed handler (test_preflight_check);
# 'missing' has no installed handler, exercising the resolved path AND the
# declared-but-no-handler hard-FAIL path for a non-default profile. (Bare
# assignment is correct here — the append-only guard governs INSTALL_STAGES only,
# and a downstream profile defines its own preflight set, per profiles/README.md.)
PROFILE_PREFLIGHT_EXTRA=(check missing)

# install: APPEND one extra stage. Under ACTOOLS_PROFILE=test the dispatcher
# resolves every stage to test_<stage>; 'seam' specifically proves append-only
# routing fired. NEVER bare-assign this array (would replace the community stages
# and trip the append-only guard).
PROFILE_INSTALL_STAGES+=(seam)

# doctor: per-check extra loop deliberately deferred (see header). Live doctor
# dispatch point is the deep handler resolved via resolve_feature_handler.
PROFILE_DOCTOR_EXTRA=()

# handoff: built-ins (site admin commands log, inherited) PLUS one non-built-in
# section that resolves to a handler (test_handoff_section), exercising the *)
# arm's resolve_handoff_section routing.
PROFILE_HANDOFF_SECTIONS+=(section)
