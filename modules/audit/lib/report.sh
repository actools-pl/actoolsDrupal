#!/usr/bin/env bash
# Report formatter — summary, next actions, JSON mode

generate_report() {
  local mode="${1:-default}"

  if [[ "$mode" == "json" ]]; then
    _generate_json_report
    return
  fi

  if [[ "$CI_MODE" == "true" ]]; then
    echo ""
    echo "PASS=${PASS} WARN=${WARN} FAIL=${FAIL} CRITICAL=${CRITICAL}"
    return
  fi

  # ── Human readable summary ──────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}─────────────────────────────────────────${NC}"
  echo -e "${BOLD}Summary:${NC}"
  echo -e "  ${GREEN}PASS:${NC}     ${PASS}"
  echo -e "  ${YELLOW}WARN:${NC}     ${WARN}"
  echo -e "  ${RED}FAIL:${NC}     ${FAIL}"
  if (( CRITICAL > 0 )); then
    echo -e "  ${RED}${BOLD}CRITICAL: ${CRITICAL}${NC}"
  fi

  # Score out of 10
  local total=$(( PASS + WARN + FAIL + CRITICAL ))
  local score=10
  if (( total > 0 )); then
    # CRITICAL = -4, FAIL(HIGH) = -2, FAIL(non-backup) = -1, WARN = -0 (informational only)
    # A clean fresh install with no backup (expected) should score 8/10
    local deduction=$(( CRITICAL * 4 + FAIL * 2 ))
    # Reduce WARN penalty — WARNs are informational, not failures
    local warn_deduction=$(( WARN / 4 ))
    deduction=$(( deduction + warn_deduction ))
    score=$(( 10 - deduction ))
    (( score < 0 )) && score=0
  fi

  echo ""
  echo -e "${BOLD}Audit score: ${score}/10${NC}"

  # ── Next actions by priority ────────────────────────────────────────────────
  if [[ -n "$FINDINGS" ]]; then
    echo ""
    echo -e "${BOLD}Next actions (CRITICAL first):${NC}"

    local i=1
    # CRITICAL first
    while IFS='|' read -r status priority message why fix id; do
      [[ -z "$status" ]] && continue
      if [[ "$priority" == "CRITICAL" ]]; then
        echo -e "  ${i}. ${RED}[CRITICAL]${NC} ${id} — ${message}"
        echo -e "     ${RED}→${NC} ${fix}"
        (( i++ ))
      fi
    done <<< "$(echo -e "$FINDINGS")"

    # HIGH
    while IFS='|' read -r status priority message why fix id; do
      [[ -z "$status" ]] && continue
      if [[ "$priority" == "HIGH" && "$status" == "FAIL" ]]; then
        echo -e "  ${i}. ${RED}[HIGH]${NC} ${id} — ${message}"
        echo -e "     ${RED}→${NC} ${fix}"
        (( i++ ))
      fi
    done <<< "$(echo -e "$FINDINGS")"

    # HIGH WARN
    while IFS='|' read -r status priority message why fix id; do
      [[ -z "$status" ]] && continue
      if [[ "$priority" == "HIGH" && "$status" == "WARN" ]]; then
        echo -e "  ${i}. ${YELLOW}[HIGH]${NC} ${id} — ${message}"
        echo -e "     ${YELLOW}→${NC} ${fix}"
        (( i++ ))
      fi
    done <<< "$(echo -e "$FINDINGS")"

    # MEDIUM
    while IFS='|' read -r status priority message why fix id; do
      [[ -z "$status" ]] && continue
      if [[ "$priority" == "MEDIUM" ]]; then
        echo -e "  ${i}. [MEDIUM] ${id} — ${message}"
        (( i++ ))
      fi
    done <<< "$(echo -e "$FINDINGS")"

    # LOW
    while IFS='|' read -r status priority message why fix id; do
      [[ -z "$status" ]] && continue
      if [[ "$priority" == "LOW" ]]; then
        echo -e "  ${i}. [LOW] ${id} — ${message}"
        (( i++ ))
      fi
    done <<< "$(echo -e "$FINDINGS")"
  fi

  echo -e "${BOLD}─────────────────────────────────────────${NC}"

  if (( CRITICAL == 0 && FAIL == 0 && WARN == 0 )); then
    echo -e "${GREEN}${BOLD}All checks passed. System healthy.${NC}"
  elif (( CRITICAL > 0 )); then
    echo -e "${RED}${BOLD}CRITICAL issues found. Fix immediately.${NC}"
  elif (( FAIL > 0 )); then
    echo -e "${RED}Fix FAIL items before next deploy.${NC}"
  else
    echo -e "${YELLOW}Warnings present. Review when convenient.${NC}"
  fi
  echo ""
}

_generate_json_report() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local total=$(( PASS + WARN + FAIL ))
  local score=10
  local total=$(( PASS + WARN + FAIL + CRITICAL ))
    local deduction=$(( CRITICAL * 4 + FAIL * 2 ))
    local warn_deduction=$(( WARN / 4 ))
    deduction=$(( deduction + warn_deduction ))
    score=$(( 10 - deduction ))
    (( score < 0 )) && score=0
  fi

  python3 << PYEOF
import json, sys

findings = []
raw = """${FINDINGS}"""
for line in raw.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|')
    if len(parts) >= 6:
        findings.append({
            "status": parts[0],
            "priority": parts[1],
            "message": parts[2],
            "why": parts[3],
            "fix": parts[4],
            "id": parts[5]
        })

report = {
    "actools_audit": {
        "timestamp": "${timestamp}",
        "score": ${score},
        "score_max": 10,
        "summary": {
            "pass": ${PASS},
            "warn": ${WARN},
            "fail": ${FAIL},
            "critical": ${CRITICAL}
        },
        "findings": findings
    }
}
print(json.dumps(report, indent=2))
PYEOF
}
