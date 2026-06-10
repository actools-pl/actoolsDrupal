#!/usr/bin/env bash
# =============================================================================
# tests/fixtures/profiles/test/commands/seam_feature.sh — TEST-ONLY fixture.
#
# A profile-supplied GENERIC feature handler. Tests stage this into a sandbox as
#   ${INSTALL_DIR}/profiles.d/test/commands/seam_feature.sh
# which is resolve_feature_handler's Tier-1 ("active-profile command override")
# location. It proves the resolve_feature_handler primitive resolves an arbitrary
# feature (not just doctor_deep) to a profile-supplied PATH, and that sourcing +
# running that path works — the generic feature-handler dispatch point, distinct
# from the doctor `--deep` surface that *consumes* the same resolver.
#
# The fake-profile e2e resolves `resolve_feature_handler seam_feature`, sources
# the returned path, and calls run_seam_feature, asserting the marker. Touches a
# marker when ACTOOLS_MARKER_DIR is set; sourcing only defines the function.
# =============================================================================

run_seam_feature() {
  [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/feature_seam.marker"
  echo "TEST_FEATURE_HANDLER_DISPATCHED:seam_feature"
  return 0
}
