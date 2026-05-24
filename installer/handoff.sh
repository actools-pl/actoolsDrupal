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
        ;;
      *)
        # Unknown section name — downstream profile asked for it but we
        # have no handler. Silent skip is correct here.
        ;;
    esac
  done
}
