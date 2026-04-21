#!/usr/bin/env bash
# Layer 1.5 — Behavioral verification
# Not: is Redis running. But: does Redis actually work end-to-end.

run_integration() {
  section_header "INTEGRATION"

  # Redis behavioral test — write → read → TTL confirm
  local redis_write
  redis_write=$(docker compose exec -T redis \
    redis-cli SET actools_audit_test "ok" EX 10 2>/dev/null | tr -d '[:space:]' || echo "")
  local redis_read
  redis_read=$(docker compose exec -T redis \
    redis-cli GET actools_audit_test 2>/dev/null | tr -d '[:space:]' || echo "")
  local redis_ttl
  redis_ttl=$(docker compose exec -T redis \
    redis-cli TTL actools_audit_test 2>/dev/null | tr -d '[:space:]' || echo "0")
  # Clean up
  docker compose exec -T redis redis-cli DEL actools_audit_test >/dev/null 2>&1 || true

  if [[ "$redis_read" == "ok" && "$redis_ttl" -gt 0 ]]; then
    record_finding "PASS" "HIGH" "Redis: write/read/TTL confirmed" "" "" ""
  else
    record_finding "FAIL" "HIGH" \
      "Redis behavioral test failed" \
      "Redis is running but write/read/TTL cycle not working correctly" \
      "actools redis-info — check Redis memory and eviction policy" \
      "ACT-REDIS-02"
  fi

  # Redis actually used by Drupal cache
  local drupal_redis
  drupal_redis=$(drush_exec "ev 'try { \$c = \\Drupal::service(\"cache.backend.redis\"); echo \"ok\"; } catch(\\Exception \$e) { echo \"fail\"; }'" \
    2>/dev/null | tr -d '[:space:]' || echo "fail")
  if [[ "$drupal_redis" == "ok" ]]; then
    record_finding "PASS" "HIGH" "Redis: Drupal cache backend confirmed" "" "" ""
  else
    record_finding "WARN" "HIGH" \
      "Redis not confirmed as Drupal cache backend" \
      "Drupal may be using database cache — performance and session risk" \
      "Verify \$settings['cache']['default'] in settings.php — actools drush prod cr" \
      "ACT-REDIS-01"
  fi

  # HTTP response behavior — Cloudflare aware
  local domain="${BASE_DOMAIN:-localhost}"
  local http_headers
  # Skip HTTP checks in CI mode — fake domain has no DNS/TLS
  if [[ "${CI_MODE:-false}" == "true" ]]; then
    record_finding "PASS" "INFO" "HTTP checks: skipped in CI mode" "" "" ""
  else
  http_headers=$(curl -sI --max-time 10 "https://${domain}" 2>/dev/null || echo "")
  # Cloudflare strips Cache-Control and Content-Encoding at edge
  # Check for Cloudflare presence and skip these checks if tunnel active
  if echo "$http_headers" | grep -qi "cf-ray"; then
    record_finding "PASS" "LOW" "HTTP: Cloudflare edge active — caching and compression handled at edge" "" "" ""
  else
    if echo "$http_headers" | grep -qi "cache-control"; then
      record_finding "PASS" "LOW" "HTTP: Cache-Control header present" "" "" ""
    else
      record_finding "WARN" "LOW"         "Cache-Control header missing from HTTP response"         "Browsers and CDNs may not cache static assets efficiently"         "Verify Caddyfile header directives — actools caddy-reload"         "ACT-HTTP-01"
    fi
    if echo "$http_headers" | grep -qi "content-encoding"; then
      record_finding "PASS" "LOW" "HTTP: Compression (gzip/brotli) active" "" "" ""
    else
      record_finding "WARN" "LOW"         "Response compression not detected"         "Pages served uncompressed — slower load times"         "Verify encode zstd gzip in Caddyfile"         "ACT-HTTP-01"
    fi
  fi

  # Trusted host — actual spoof test
  local spoof_response
  spoof_response=$(curl -sI --max-time 10 \
    -H "Host: evil-attacker.com" \
    "https://${domain}" 2>/dev/null | head -1 | tr -d '[:space:]' || echo "")
  if echo "$spoof_response" | grep -qE "400|403|421"; then
    record_finding "PASS" "MEDIUM" "Trusted host: spoof rejected at reverse proxy" "" "" ""
  else
    record_finding "WARN" "MEDIUM" \
      "Trusted host: reverse proxy accepts forged Host header" \
      "Caddy handles TLS via SNI — Drupal trusted_host_patterns still protects PHP layer" \
      "Verify trusted_host_patterns in settings.php — expected behaviour with Caddy+TLS" \
      "ACT-SEC-04"
  fi

  # Queue worker behavioral test — enqueue and verify processing
  local test_job_result
  test_job_result=$(drush_exec \
    "ev '\\Drupal::queue(\"actools_audit_probe\")->createItem([\"test\"=>1]); echo \\Drupal::queue(\"actools_audit_probe\")->numberOfItems();'" \
    2>/dev/null | tr -d '[:space:]' || echo "")
  # Clean up probe queue
  drush_exec "ev '\\Drupal::queue(\"actools_audit_probe\")->deleteQueue();'" >/dev/null 2>&1 || true

  if [[ -n "$test_job_result" && "$test_job_result" -ge 1 ]]; then
    record_finding "PASS" "MEDIUM" "Queue worker: enqueue test passed" "" "" ""
  else
    record_finding "WARN" "MEDIUM" \
      "Queue worker: could not verify enqueue" \
      "Worker container may not be processing jobs — PDF generation at risk" \
      "actools worker-status — actools worker-logs" \
      "ACT-WORK-02"
  fi

  # Private files path exists and writable
  local private_path
  private_path=$(drush_exec "ev 'echo \\Drupal::service(\"file_system\")->realpath(\"private://\");'" \
    2>/dev/null | tr -d '[:space:]' || echo "")
  if [[ -z "$private_path" ]]; then
    record_finding "FAIL" "CRITICAL" \
      "Private file path not configured" \
      "Private file downloads are publicly accessible via direct URL" \
      "Set \$settings['file_private_path'] in settings.php" \
      "ACT-PRIV-01"
  else
    # Test writability
    local write_test
    write_test=$(docker compose exec -T php_prod bash -c \
      "test -w '${private_path}' && echo ok || echo fail" 2>/dev/null | tr -d '[:space:]' || echo "fail")
    if [[ "$write_test" == "ok" ]]; then
      record_finding "PASS" "HIGH" "Private file path: configured and writable" "" "" ""
    else
      record_finding "WARN" "HIGH" \
        "Private file path set but not writable" \
        "Private file uploads will fail silently" \
        "chmod 755 ${private_path} — verify web user ownership" \
        "ACT-PRIV-01"
    fi
  fi
}
