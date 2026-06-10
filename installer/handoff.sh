#!/usr/bin/env bash
# =============================================================================
# installer/handoff.sh — Post-install summary panel (Doc 1 §5.5).
#
# Replaces the verbose bottom banner of actools.sh main(). Shows the
# operator the four things that matter: site URL, login URL, where the
# admin password lives, and which commands to learn next.
#
# Required globals (set by actools.sh, or loaded from actools.env):
#   INSTALL_DIR, ENV_FILE, REAL_HOME, LOG_DIR
# =============================================================================

run_handoff() {
  # If invoked standalone (not from install flow), source the env file.
  if [[ -z "${BASE_DOMAIN:-}" && -f "${ENV_FILE:-/dev/null}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
  fi

  local domain="${BASE_DOMAIN:-<unset>}"
  local admin_pass_file="${REAL_HOME:-$HOME}/.actools-admin-pass"
  local install_log=""
  if [[ -d "${LOG_DIR:-}" ]]; then
    install_log=$(ls -t "${LOG_DIR}"/actools-*.log 2>/dev/null | head -1)
  fi

  # Load profile to know which sections to render
  local sections=(site admin commands log)
  if [[ -f "${INSTALL_DIR}/installer/profile.sh" ]]; then
    # shellcheck source=/dev/null
    source "${INSTALL_DIR}/installer/profile.sh"
    # Source dispatch.sh after profile.sh has set ACTOOLS_PROFILE. P0-H: the
    # handoff-section resolver is now consumed by the *) arm below (was
    # "available, not called").
    # shellcheck source=/dev/null
    source "${INSTALL_DIR}/installer/dispatch.sh" 2>/dev/null || true
    mapfile -t sections < <(profile_handoff_sections)
  fi

  print_title "ACTOOLS HANDOFF"

  for section in "${sections[@]}"; do
    case "$section" in
      site)
        echo "Site:"
        echo "  https://${domain}"
        echo
        ;;
      admin)
        echo "Drupal admin:"
        echo "  https://${domain}/user/login"
        echo
        echo "Admin credential file:"
        echo "  ${admin_pass_file}"
        echo
        ;;
      commands)
        echo "Useful commands:"
        echo "  actools doctor"
        echo "  actools status"
        echo "  actools logs"
        echo "  actools backup"
        echo "  actools update"
        echo
        ;;
      log)
        if [[ -n "$install_log" ]]; then
          echo "Install log:"
          echo "  ${install_log}"
          echo
        fi
        echo "Note: a per-deployment encrypted-backup key was generated. Keep a secure"
        echo "      off-server backup of it; it will be required if encrypted backups are enabled."
        echo
        ;;
      *)
        # Non-built-in section. community's PROFILE_HANDOFF_SECTIONS are all
        # handled by the explicit arms above, so this never fires for community.
        # A non-default profile routes the section through the resolver (P0-H):
        # a section that resolves to an installed handler is rendered by it; an
        # unresolved section gets a visible notice (handoff is a post-install
        # DISPLAY surface — unlike preflight's readiness checks, an unresolved
        # summary section is non-fatal, so it is reported rather than failed).
        local _handoff_handler=""
        if declare -F actools::dispatch::resolve_handoff_section >/dev/null 2>&1; then
          _handoff_handler="$(actools::dispatch::resolve_handoff_section "$section" 2>/dev/null)"
        fi
        if [[ -n "$_handoff_handler" ]] && declare -F "$_handoff_handler" >/dev/null 2>&1; then
          "$_handoff_handler" "$section" || true
        else
          echo "Note: profile requested handoff section '${section}' but no handler is installed."
          echo
        fi
        ;;
    esac
  done
}
