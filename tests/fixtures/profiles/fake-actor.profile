# =============================================================================
# tests/fixtures/profiles/fake-actor.profile — TEST-ONLY fixture profile.
#
# Used ONLY by bats tests to prove the actor-id governance requirement fires.
# Never shipped. Tests stage this file into a sandbox INSTALL_DIR as
# profiles/test.profile ('test' is the test-friendly allowed profile name) and
# run `init --profile test`.
#
# Structural shape mirrors profiles/community.profile. The single meaningful
# difference is PROFILE_REQUIRES_ACTOR=true.
#
# This file is sourced — keep it valid shell with NO executable side effects
# (variable assignments only). A bats test asserts exactly that.
# =============================================================================

PROFILE_NAME="test"
PROFILE_DISPLAY="Actools Drupal Test Fixture (actor-required)"

# Governance: this fixture REQUIRES an actor identity at init, no change ticket.
PROFILE_REQUIRES_ACTOR=true
PROFILE_REQUIRES_CHANGE_TICKET=false

# init: same operator-facing fields as community (no extras).
PROFILE_INIT_FIELDS=(domain email site-name)

PROFILE_PREFLIGHT_EXTRA=()
PROFILE_INSTALL_STAGES=(host stack db drupal worker)
PROFILE_DOCTOR_EXTRA=()
PROFILE_HANDOFF_SECTIONS=(site admin commands log)
