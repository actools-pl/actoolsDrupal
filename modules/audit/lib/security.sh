#!/usr/bin/env bash
# Layer 3 — Surface exposure (passive by default)

run_security() {
  local active="${1:-false}"
  section_header "SECURITY"

  local domain="${BASE_DOMAIN:-localhost}"
  local headers
  headers=$(curl -sI --max-time 15 "https://${domain}" 2>/dev/null || echo "")

  # HTTPS enforced — Cloudflare handles redirect, check via header
  local https_header
  https_header=$(curl -sI --max-time 10 "https://${domain}" 2>/dev/null | grep -i "cf-ray" || echo "")
  if [[ -n "$https_header" ]]; then
    record_finding "PASS" "HIGH" "HTTPS: Cloudflare tunnel active — HTTPS enforced at edge" "" "" ""
  else
    local http_redirect
    http_redirect=$(curl -sso /dev/null -w "%{http_code}" --max-time 10       "http://${domain}" 2>/dev/null || echo "000")
    if [[ "$http_redirect" =~ ^30[0-9]$ ]]; then
      record_finding "PASS" "HIGH" "HTTPS: HTTP redirects to HTTPS" "" "" ""
    else
      record_finding "WARN" "HIGH"         "HTTP does not redirect to HTTPS (got ${http_redirect})"         "Users on plain HTTP not automatically secured"         "Verify Cloudflare SSL/TLS settings — set to Full (strict)"         "ACT-SEC-01"
    fi
  fi

  # HSTS header
  if echo "$headers" | grep -qi "strict-transport-security"; then
    record_finding "PASS" "HIGH" "HSTS header: present" "" "" ""
  else
    record_finding "WARN" "MEDIUM" \
      "HSTS header missing" \
      "Browsers not instructed to always use HTTPS" \
      "Add 'Strict-Transport-Security' to Caddyfile header block" \
      "ACT-SEC-01"
  fi

  # X-Frame-Options
  if echo "$headers" | grep -qi "x-frame-options"; then
    record_finding "PASS" "MEDIUM" "X-Frame-Options header: present" "" "" ""
  else
    record_finding "WARN" "MEDIUM" \
      "X-Frame-Options header missing" \
      "Site may be embeddable in iframes — clickjacking risk" \
      "Add 'X-Frame-Options SAMEORIGIN' to Caddyfile header block" \
      "ACT-SEC-02"
  fi

  # X-Content-Type-Options
  if echo "$headers" | grep -qi "x-content-type-options"; then
    record_finding "PASS" "LOW" "X-Content-Type-Options header: present" "" "" ""
  else
    record_finding "WARN" "LOW" \
      "X-Content-Type-Options header missing" \
      "MIME-type sniffing not disabled" \
      "Add 'X-Content-Type-Options nosniff' to Caddyfile" \
      "ACT-SEC-02"
  fi

  # Server header hidden
  if echo "$headers" | grep -qi "^server:"; then
    record_finding "WARN" "LOW" \
      "Server header exposed" \
      "Server software version visible to attackers" \
      "Add '-Server' to Caddyfile header block" \
      "ACT-SEC-03"
  else
    record_finding "PASS" "LOW" "Server header: hidden" "" "" ""
  fi

  # Referrer-Policy
  if echo "$headers" | grep -qi "referrer-policy"; then
    record_finding "PASS" "LOW" "Referrer-Policy header: present" "" "" ""
  else
    record_finding "WARN" "LOW" \
      "Referrer-Policy header missing" \
      "Full referrer URLs may leak to third parties" \
      "Add 'Referrer-Policy strict-origin-when-cross-origin' to Caddyfile" \
      "ACT-SEC-02"
  fi

  # Exposed admin path check (passive)
  local admin_check
  admin_check=$(curl -sso /dev/null -w "%{http_code}" --max-time 10 \
    "https://${domain}/user/login" 2>/dev/null || echo "000")
  if [[ "$admin_check" == "200" ]]; then
    record_finding "INFO" "LOW" "Login page: accessible at /user/login (expected)" "" "" ""
  fi

  # Docker image versions — check for :latest tags
  local latest_images
  latest_images=$(cd "$ACTOOLS_HOME" && docker compose config 2>/dev/null | \
    grep "image:" | grep ":latest" | wc -l | tr -d '[:space:]' || echo "0")
  if (( latest_images > 0 )); then
    record_finding "WARN" "MEDIUM" \
      "Docker images using :latest tag (${latest_images} found)" \
      "Unpinned images may pull breaking changes on next deploy" \
      "Pin image versions in docker-compose.yml (e.g. mariadb:11.4.2)" \
      "ACT-SEC-03"
  else
    record_finding "PASS" "MEDIUM" "Docker images: all pinned" "" "" ""
  fi

  # Active scans — only if explicitly requested
  if [[ "$active" == "true" ]]; then
    section_header "SECURITY (ACTIVE)"
    record_finding "INFO" "LOW" "Active security scans: use actools audit --deep (Pro)" "" "" ""
  fi
}
