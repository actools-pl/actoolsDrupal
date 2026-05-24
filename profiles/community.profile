# =============================================================================
# profiles/community.profile — Actools Drupal Community (default profile).
#
# This is the ONLY profile that ships with the open-source community
# installer. Other profiles (DrupalFortress Standard, DrupalFortress
# Institutional) live in separate products and source this file's contract.
#
# See profiles/README.md for the full profile contract.
#
# This file is sourced — keep it valid shell with no executable side effects.
# =============================================================================

PROFILE_NAME="community"
PROFILE_DISPLAY="Actools Drupal Community"

# Governance flags — community has no actor identity or change ticket.
PROFILE_REQUIRES_ACTOR=false
PROFILE_REQUIRES_CHANGE_TICKET=false

# init: required fields the operator must supply via CLI flags.
PROFILE_INIT_FIELDS=(domain email site-name)

# preflight: profile-specific extra checks beyond the base set
# (OS, env, RAM, disk, ports, DNS, existing-state). Empty for community.
PROFILE_PREFLIGHT_EXTRA=()

# install: which module stage groups run during install.
PROFILE_INSTALL_STAGES=(host stack db drupal worker)

# doctor: extra check IDs this profile adds. Empty for community.
PROFILE_DOCTOR_EXTRA=()

# handoff: which sections appear in the post-install summary.
PROFILE_HANDOFF_SECTIONS=(site admin commands log)
