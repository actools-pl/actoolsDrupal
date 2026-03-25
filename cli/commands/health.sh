#!/usr/bin/env bash
# =============================================================================
# cli/commands/health.sh — Health Check Command
# =============================================================================

cmd_health() {
  cd "$INSTALL_DIR"
  for env in prod; do
    dom="${env}.${BASE_DOMAIN}"
    [[ "$env" == "prod" ]] && dom="${BASE_DOMAIN}"
    http=$(curl -sso /dev/null -w "%{http_code}" --max-time 5 "https://$dom" 2>/dev/null || echo "ERR")
    hlth=$(curl -sso /dev/null -w "%{http_code}" --max-time 5 "https://$dom/health" 2>/dev/null || echo "ERR")
    echo "$dom: HTTP=$http  /health=$hlth"
  done
}
