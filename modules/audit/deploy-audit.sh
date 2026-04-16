#!/usr/bin/env bash
# Deploy actools audit to any Actools server
# Run from: $ACTOOLS_HOME (default: /home/actools)
# Usage: bash deploy-audit.sh

set -euo pipefail

ACTOOLS_HOME="${ACTOOLS_HOME:-/home/actools}"
AUDIT_DIR="${ACTOOLS_HOME}/modules/audit"

echo "Deploying actools audit..."

# 1. Create directory structure
mkdir -p "${AUDIT_DIR}/lib"
mkdir -p "${AUDIT_DIR}/docs"

echo "Directories created."

# 2. Write audit.sh
cat > "${AUDIT_DIR}/audit.sh" << 'ENDOFFILE'
#!/usr/bin/env bash
# The Drupal community has enough Report modules.
# What it lacks is a CLI tool that says:
# I found a problem, I won't let you deploy until you run this specific command to fix it.
#
# actools audit — deterministic, operator-readable, fix-oriented
# Version: 1.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTOOLS_HOME="${ACTOOLS_HOME:-/home/actools}"

MODE="default"
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

export PASS=0 WARN=0 FAIL=0 CRITICAL=0
export FINDINGS=""
export CI_MODE=false
export JSON_MODE=false
[[ "$MODE" == "ci"   ]] && CI_MODE=true
[[ "$MODE" == "json" ]] && JSON_MODE=true

if [[ "$CI_MODE" == "true" ]]; then
  RED="" GREEN="" YELLOW="" CYAN="" BOLD="" NC=""
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

source "${SCRIPT_DIR}/lib/output.sh"
source "${SCRIPT_DIR}/lib/drupal.sh"
source "${SCRIPT_DIR}/lib/integration.sh"
source "${SCRIPT_DIR}/lib/stack.sh"
source "${SCRIPT_DIR}/lib/security.sh"
source "${SCRIPT_DIR}/lib/report.sh"

if [[ "$MODE" == "deep" ]]; then
  echo -e "${RED}actools audit --deep requires Actools Pro (€49/month)${NC}"
  echo -e "  → https://actools.feesix.com/pro"
  exit 2
fi

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

generate_report "$MODE"

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
ENDOFFILE

echo "audit.sh written."

# 3. Write lib files (sourced inline to avoid heredoc nesting issues)
# They will be written by the individual cat commands below

echo "Writing lib/output.sh..."
cat > "${AUDIT_DIR}/lib/output.sh" << 'ENDOFFILE'
#!/usr/bin/env bash
record_finding() {
  local status="$1" priority="$2" message="$3" why="$4" fix="$5" id="$6"
  case "$status" in
    PASS) (( PASS++ )) ;;
    WARN) (( WARN++ )); FINDINGS+="${status}|${priority}|${message}|${why}|${fix}|${id}\n" ;;
    FAIL)
      if [[ "$priority" == "CRITICAL" ]]; then (( CRITICAL++ )); else (( FAIL++ )); fi
      FINDINGS+="${status}|${priority}|${message}|${why}|${fix}|${id}\n"
      ;;
    INFO) ;;
  esac
  if [[ "$CI_MODE" == "true" ]]; then
    [[ "$status" != "PASS" ]] && echo "${status} [${priority}] ${message} [${id}]"; return
  fi
  [[ "$JSON_MODE" == "true" ]] && return
  case "$status" in
    PASS) echo -e "  ${GREEN}PASS${NC}  ${message}" ;;
    WARN) echo -e "  ${YELLOW}WARN${NC}  ${message}"
          echo -e "        ${YELLOW}→ Why:${NC} ${why}"
          echo -e "        ${YELLOW}→ Fix:${NC} ${fix}"
          echo -e "        ${YELLOW}→ ID:${NC}  ${id}" ;;
    FAIL)
      [[ "$priority" == "CRITICAL" ]] && \
        echo -e "  ${RED}${BOLD}FAIL [CRITICAL]${NC}  ${message}" || \
        echo -e "  ${RED}FAIL${NC}  [${priority}] ${message}"
      echo -e "        ${RED}→ Why:${NC} ${why}"
      echo -e "        ${RED}→ Fix:${NC} ${fix}"
      echo -e "        ${RED}→ ID:${NC}  ${id}" ;;
    INFO) echo -e "  ${CYAN}INFO${NC}  ${message}" ;;
  esac
}
section_header() {
  [[ "$CI_MODE" != "true" && "$JSON_MODE" != "true" ]] && echo "" && echo -e "${BOLD}[${1}]${NC}"
}
drush_exec() {
  cd "$ACTOOLS_HOME" 2>/dev/null || true
  docker compose exec -T php_prod bash -c \
    "cd /var/www/html/prod && ./vendor/bin/drush $* 2>/dev/null" 2>/dev/null
}
ENDOFFILE

echo "Writing lib/drupal.sh..."
# Copy from the deployed files
cp "${ACTOOLS_HOME}/modules/audit/lib/drupal.sh" "${AUDIT_DIR}/lib/drupal.sh" 2>/dev/null || true

echo "All lib files need to be uploaded via SFTP."
echo "See deploy instructions below."

# 4. Set permissions
chmod +x "${AUDIT_DIR}/audit.sh"
chmod +x "${AUDIT_DIR}/lib/"*.sh 2>/dev/null || true

echo "Permissions set."

# 5. Add to actools CLI
if ! grep -q "audit)" /usr/local/bin/actools; then
  python3 << 'PYEOF'
content = open('/usr/local/bin/actools').read()
audit_block = """  audit)
    shift
    source "${ACTOOLS_HOME}/modules/audit/lib/output.sh" 2>/dev/null || true
    cd "${ACTOOLS_HOME}"
    set -a; source "${ACTOOLS_HOME}/actools.env" 2>/dev/null || true; set +a
    bash "${ACTOOLS_HOME}/modules/audit/audit.sh" "$@"
    ;;
"""
content = content.replace('  tunnel)', audit_block + '  tunnel)')
open('/tmp/actools_audit_new', 'w').write(content)
print("CLI patch written to /tmp/actools_audit_new")
PYEOF
  sudo cp /tmp/actools_audit_new /usr/local/bin/actools
  echo "CLI updated — actools audit command added."
else
  echo "CLI already has audit command."
fi

echo ""
echo "=== DEPLOY COMPLETE ==="
echo ""
echo "Test with:"
echo "  actools audit"
echo "  actools audit --ci && echo ok || echo fail"
echo "  actools audit --json | python3 -m json.tool"
echo ""
