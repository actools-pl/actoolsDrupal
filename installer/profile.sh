#!/usr/bin/env bash
# =============================================================================
# installer/profile.sh — Profile loader.
#
# Sources the active profile and exposes accessor functions so callers
# never touch the underlying global variables directly.
#
# The community installer ships only the 'community' profile. Other
# profiles (standard, institutional) belong to separate products that
# follow the contract in profiles/README.md.
#
# Required globals at source time:
#   INSTALL_DIR  — repository root, set by actools.sh and cli/actools
# =============================================================================

: "${ACTOOLS_PROFILE:=community}"

_PROFILE_FILE="${INSTALL_DIR}/profiles/${ACTOOLS_PROFILE}.profile"

if [[ ! -f "$_PROFILE_FILE" ]]; then
  echo "Profile not found: ${ACTOOLS_PROFILE}" >&2
  echo "  expected: ${_PROFILE_FILE}" >&2
  echo "  this build only ships the 'community' profile." >&2
  echo "  other profiles (standard, institutional) are separate products." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$_PROFILE_FILE"

# Accessor functions. Bash arrays don't travel cleanly across files
# without these wrappers.
profile_name()                   { echo "${PROFILE_NAME:-community}"; }
profile_display()                { echo "${PROFILE_DISPLAY:-Actools Drupal Community}"; }
profile_requires_actor()         { [[ "${PROFILE_REQUIRES_ACTOR:-false}" == "true" ]]; }
profile_requires_change_ticket() { [[ "${PROFILE_REQUIRES_CHANGE_TICKET:-false}" == "true" ]]; }
profile_init_fields()            { printf '%s\n' "${PROFILE_INIT_FIELDS[@]}"; }
profile_preflight_extra()        { printf '%s\n' "${PROFILE_PREFLIGHT_EXTRA[@]:-}" | grep -v '^$' || true; }
profile_install_stages()         { printf '%s\n' "${PROFILE_INSTALL_STAGES[@]}"; }
profile_doctor_extra()           { printf '%s\n' "${PROFILE_DOCTOR_EXTRA[@]:-}" | grep -v '^$' || true; }
profile_handoff_sections()       { printf '%s\n' "${PROFILE_HANDOFF_SECTIONS[@]}"; }
