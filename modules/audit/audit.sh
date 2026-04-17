#!/usr/bin/env bash
# The Drupal community has enough Report modules.
# What it lacks is a CLI tool that says:
# I found a problem, I won't let you deploy until you run this specific command to fix it.
#
# actools audit — deterministic, operator-readable, fix-oriented
# Version: 1.0 (v1.1 + v1.2 + v1.3 spec)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTOOLS_HOME="${ACTOOLS_HOME:-/home/sysadmin/actoolsDrupal}"
# Re-exec with docker group if docker not accessible
if ! docker info >/dev/null 2>&1; then
  if id -nG "$USER" 2>/dev/null | grep -qw docker; then
    exec sg docker -c "bash $0 $*"
  else
    echo "[WARN] Docker not accessible — some checks will fail. Add user to docker group."
  fi
fi

# ── Flags ─────────────────────────────────────────────────────────────────────
MODE="default"     # default | complete | security | json | ci | deep
LAYER_PERF=false
LAYER_SECURITY_ACTIVE=false

for arg in "$@"; do
  case "$arg" in
    --complete)         MODE="complete"; LAYER_PERF=true ;;
    --security)         MODE="security" ;;
    --json)             MODE="json" ;;
    --ci)               MODE="ci" ;;
    --deep)             MODE="deep" ;;
    --security-active)  LAYER_SECURITY_ACTIVE=true ;;
  esac
done

# ── Counters ──────────────────────────────────────────────────────────────────
export PASS=0 WARN=0 FAIL=0 CRITICAL=0
export FINDINGS=""
export CI_MODE=false
export JSON_MODE=false
[[ "$MODE" == "ci"   ]] && CI_MODE=true
[[ "$MODE" == "json" ]] && JSON_MODE=true

# ── Color ─────────────────────────────────────────────────────────────────────
if [[ "$CI_MODE" == "true" ]]; then
  RED="" GREEN="" YELLOW="" CYAN="" BOLD="" NC=""
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

# ── Source modules ─────────────────────────────────────────────────────────────
source "${SCRIPT_DIR}/lib/output.sh"
source "${SCRIPT_DIR}/lib/drupal.sh"
source "${SCRIPT_DIR}/lib/integration.sh"
source "${SCRIPT_DIR}/lib/stack.sh"
source "${SCRIPT_DIR}/lib/security.sh"
source "${SCRIPT_DIR}/lib/report.sh"

# ── Deep (Pro) gate ────────────────────────────────────────────────────────────
if [[ "$MODE" == "deep" ]]; then
  echo -e "${RED}actools audit --deep requires Actools Pro (€49/month)${NC}"
  echo -e "  → https://actools.feesix.com/pro"
  exit 2
fi

# ── Run layers ─────────────────────────────────────────────────────────────────
if [[ "$CI_MODE" != "true" && "$JSON_MODE" != "true" ]]; then
  echo -e "${BOLD}${CYAN}=== ACTOOLS DRUPAL AUDIT ===${NC}"
  echo ""
fi

if [[ "$MODE" == "security" ]]; then
  run_security "$LAYER_SECURITY_ACTIVE"
else
  run_drupal
  run_integration
  run_stack
  run_security "$LAYER_SECURITY_ACTIVE"
  [[ "$LAYER_PERF" == "true" ]] && run_performance
fi

# ── Report ─────────────────────────────────────────────────────────────────────
generate_report "$MODE"

# ── Exit codes ─────────────────────────────────────────────────────────────────
if [[ "$CI_MODE" == "true" ]]; then
  if   (( CRITICAL > 0 )); then exit 3
  elif (( FAIL     > 0 )); then exit 2
  elif (( WARN     > 0 )); then exit 1
  else exit 0
  fi
else
  if   (( CRITICAL > 0 )); then exit 3
  elif (( FAIL     > 0 )); then exit 2
  else exit 0
  fi
fi
