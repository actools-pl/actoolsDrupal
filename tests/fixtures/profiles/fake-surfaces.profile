# =============================================================================
# tests/fixtures/profiles/fake-surfaces.profile — TEST-ONLY fixture profile.
#
# Used ONLY by P0-H bats tests to prove the operator surfaces route profile
# extras through the resolver. Never shipped. Tests stage this file into a
# sandbox INSTALL_DIR as profiles/test.profile ('test' is the test-friendly
# allowed profile name) and drive init / preflight / handoff against it.
#
# It deliberately declares a NON-default value at each surface so a single
# fixture exercises every dispatch point:
#   - PROFILE_INIT_FIELDS adds one extra field beyond the base three, so init's
#     PROFILE_INIT_FIELDS-consumption loop takes its "extra" branch. (Phase 0
#     collects extras as a no-op — neither validated nor persisted — so the
#     test asserts init still succeeds and the extra is NOT written.)
#   - PROFILE_PREFLIGHT_EXTRA lists one check whose handler the test installs
#     ('check' -> test_preflight_check) AND one whose handler is absent
#     ('missing'), exercising the resolved path AND the unknown-fails path.
#   - PROFILE_HANDOFF_SECTIONS appends one non-built-in section whose handler
#     the test installs ('section' -> test_handoff_section), exercising the *)
#     arm's resolve_handoff_section routing.
#   - PROFILE_DOCTOR_EXTRA stays empty: doctor's per-check extra loop is
#     deliberately deferred in P0-H (the deep handler is wired via
#     resolve_feature_handler instead; see the doctor-deep override fixture
#     at tests/fixtures/profiles/test/commands/doctor_deep.sh).
#
# Governance flags are false so init succeeds without --actor-id/--change-ticket
# (those paths are covered by fake-actor.profile / fake-ticket.profile).
#
# This file is sourced — keep it valid shell with NO executable side effects
# (variable assignments only). A bats test asserts exactly that.
# =============================================================================

PROFILE_NAME="test"
PROFILE_DISPLAY="Actools Drupal Test Fixture (surface dispatch)"

# Governance: neither required (kept simple for surface-dispatch tests).
PROFILE_REQUIRES_ACTOR=false
PROFILE_REQUIRES_CHANGE_TICKET=false

# init: base fields + one extra to exercise the init-field consumption loop.
PROFILE_INIT_FIELDS=(domain email site-name extra_field)

# preflight: 'check' resolves to an installed handler; 'missing' does not.
PROFILE_PREFLIGHT_EXTRA=(check missing)

# install: unchanged from community (install staging is out of P0-H scope).
PROFILE_INSTALL_STAGES=(host stack db drupal worker)

# doctor: extra-check loop deliberately deferred in P0-H (see fixture header).
PROFILE_DOCTOR_EXTRA=()

# handoff: built-ins plus one non-built-in section that resolves to a handler.
PROFILE_HANDOFF_SECTIONS=(site admin commands log section)
