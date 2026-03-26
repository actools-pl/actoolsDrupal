#!/usr/bin/env bash
# =============================================================================
# cli/commands/health.sh — Health Check CLI Command
# =============================================================================

cmd_health() {
  local mode="${1:-simple}"
  local INSTALL_DIR="/home/actools"

  # Load env for BASE_DOMAIN and DB_ROOT_PASS
  source "${INSTALL_DIR}/actools.env" 2>/dev/null || true

  case "$mode" in
    --verbose|-v)
      source "${INSTALL_DIR}/modules/health/checks.sh"
      health_check_all
      ;;
    --cost|-c)
      source "${INSTALL_DIR}/cli/commands/cost_optimize.sh"
      cmd_cost_optimize
      ;;
    *)
      # Simple mode — just HTTP check
      for env in prod; do
        local dom="${BASE_DOMAIN}"
        local http hlth
        http=$(curl -sso /dev/null -w "%{http_code}" --max-time 5 "https://$dom" 2>/dev/null || echo "ERR")
        hlth=$(curl -sso /dev/null -w "%{http_code}" --max-time 5 "https://$dom/health" 2>/dev/null || echo "ERR")
        echo "$dom: HTTP=$http  /health=$hlth"
      done
      echo ""
      echo "Run 'actools health --verbose' for full system health report."
      echo "Run 'actools health --cost' for memory optimization report."
      ;;
  esac
}
