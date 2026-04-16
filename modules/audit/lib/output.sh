#!/usr/bin/env bash
# Shared output helpers for actools audit

# record_finding STATUS PRIORITY MESSAGE WHY FIX_CMD FIX_ID
record_finding() {
  local status="$1" priority="$2" message="$3" why="$4" fix="$5" id="$6"

  case "$status" in
    PASS) (( PASS++ )) ;;
    WARN)
      (( WARN++ ))
      FINDINGS+="${status}|${priority}|${message}|${why}|${fix}|${id}\n"
      ;;
    FAIL)
      if [[ "$priority" == "CRITICAL" ]]; then
        (( CRITICAL++ ))
      else
        (( FAIL++ ))
      fi
      FINDINGS+="${status}|${priority}|${message}|${why}|${fix}|${id}\n"
      ;;
    INFO) ;;
  esac

  if [[ "$CI_MODE" == "true" ]]; then
    [[ "$status" != "PASS" ]] && echo "${status} [${priority}] ${message} [${id}]"
    return
  fi

  if [[ "$JSON_MODE" == "true" ]]; then
    return  # collected in report.sh
  fi

  case "$status" in
    PASS) echo -e "  ${GREEN}PASS${NC}  ${message}" ;;
    WARN) echo -e "  ${YELLOW}WARN${NC}  ${message}"
          echo -e "        ${YELLOW}→ Why:${NC} ${why}"
          echo -e "        ${YELLOW}→ Fix:${NC} ${fix}"
          echo -e "        ${YELLOW}→ ID:${NC}  ${id}"
          ;;
    FAIL)
      if [[ "$priority" == "CRITICAL" ]]; then
        echo -e "  ${RED}${BOLD}FAIL [CRITICAL]${NC}  ${message}"
      else
        echo -e "  ${RED}FAIL${NC}  [${priority}] ${message}"
      fi
      echo -e "        ${RED}→ Why:${NC} ${why}"
      echo -e "        ${RED}→ Fix:${NC} ${fix}"
      echo -e "        ${RED}→ ID:${NC}  ${id}"
      ;;
    INFO) echo -e "  ${CYAN}INFO${NC}  ${message}" ;;
  esac
}

section_header() {
  if [[ "$CI_MODE" != "true" && "$JSON_MODE" != "true" ]]; then
    echo ""
    echo -e "${BOLD}[${1}]${NC}"
  fi
}

drush_exec() {
  cd "${ACTOOLS_HOME:-$(pwd)}" 2>/dev/null || true
  docker compose exec -T php_prod bash -c \
    "cd /opt/drupal/web/prod && ./vendor/bin/drush $* 2>/dev/null" 2>/dev/null || true
}
