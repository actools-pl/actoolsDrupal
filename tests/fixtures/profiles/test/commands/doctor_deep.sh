#!/usr/bin/env bash
# =============================================================================
# tests/fixtures/profiles/test/commands/doctor_deep.sh — TEST-ONLY fixture.
#
# A profile-supplied deep-doctor handler. Tests stage this into a sandbox as
#   ${INSTALL_DIR}/profiles.d/test/commands/doctor_deep.sh
# which is exactly resolve_feature_handler's Tier-1 ("active-profile command
# override") location. It proves the doctor surface routes `--deep` through
# resolve_feature_handler and runs the profile's handler INSTEAD of the
# built-in cli/commands/doctor_deep.sh gate.
#
# The sentinel string and the distinctive exit code (7) let the test assert
# both that this handler ran and that its return propagated through run_doctor.
# =============================================================================

run_doctor_deep() {
  echo "TEST_DOCTOR_DEEP_OVERRIDE_DISPATCHED"
  return 7
}
