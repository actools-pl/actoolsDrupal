#!/usr/bin/env bash
# =============================================================================
# tests/fixtures/profiles/test/stage_handlers.sh — TEST-ONLY install-stage stubs.
#
# Under ACTOOLS_PROFILE=test, actools::dispatch::resolve_install_stage resolves
# EVERY stage to test_<stage> (the resolver keys on profile name). The fake-
# profile e2e sources this file so run_install_stage finds a defined handler for
# each stage in the test profile's PROFILE_INSTALL_STAGES list — the inherited
# community stages (host stack db drupal worker) AND the appended 'seam' stage.
#
# Each handler is a marker-writing stub: it touches a uniquely-named marker when
# ACTOOLS_MARKER_DIR is set so the e2e can assert the install-stage dispatch
# point fired for every stage, and the 'seam' marker specifically proves
# append-only routing (a profile-appended stage reached its handler). These are
# stubs, not real install steps — no host provisioning, no container build.
#
# Sourcing this file only DEFINES functions; the marker touch happens at call
# time and is a no-op when ACTOOLS_MARKER_DIR is unset.
# =============================================================================

test_host()   { [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/stage_host.marker";   echo "TEST_STAGE_DISPATCHED:host"; }
test_stack()  { [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/stage_stack.marker";  echo "TEST_STAGE_DISPATCHED:stack"; }
test_db()     { [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/stage_db.marker";     echo "TEST_STAGE_DISPATCHED:db"; }
test_drupal() { [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/stage_drupal.marker"; echo "TEST_STAGE_DISPATCHED:drupal"; }
test_worker() { [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/stage_worker.marker"; echo "TEST_STAGE_DISPATCHED:worker"; }
test_seam()   { [[ -n "${ACTOOLS_MARKER_DIR:-}" ]] && : > "${ACTOOLS_MARKER_DIR}/stage_seam.marker";   echo "TEST_STAGE_DISPATCHED:seam"; }
