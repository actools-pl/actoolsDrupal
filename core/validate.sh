#!/usr/bin/env bash
# =============================================================================
# core/validate.sh — Actools Engine: All Validation Logic
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

validate_env() {
  [[ "${PHP_MEMORY_LIMIT:-512m}" =~ ^[0-9]+[mg]$ ]] || \
    error "PHP_MEMORY_LIMIT format invalid ('${PHP_MEMORY_LIMIT}'). Use: 512m or 2g"
  [[ "${WORKER_MEMORY_LIMIT:-2g}" =~ ^[0-9]+[mg]$ ]] || \
    error "WORKER_MEMORY_LIMIT format invalid ('${WORKER_MEMORY_LIMIT}'). Use: 2g or 1024m"
  [[ "${DB_MEMORY_LIMIT:-2g}" =~ ^[0-9]+[mg]$ ]] || \
    error "DB_MEMORY_LIMIT format invalid ('${DB_MEMORY_LIMIT}'). Use: 2g or 1024m"
  [[ "${PHP_VERSION:-8.3}" =~ ^[0-9]+\.[0-9]+$ ]] || \
    error "PHP_VERSION format invalid: '${PHP_VERSION}'. Expected e.g. 8.3"
  log ".env validation passed."
}

detect_s3_provider() {
  STORAGE_PROVIDER="${STORAGE_PROVIDER:-${S3_PROVIDER:-}}"
  S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-${S3_ENDPOINT:-}}"
  ASSET_CDN_HOST="${ASSET_CDN_HOST:-${CLOUDFLARE_CDN_DOMAIN:-}}"

  if [[ -z "$STORAGE_PROVIDER" && -n "$S3_ENDPOINT_URL" ]]; then
    if [[ "$S3_ENDPOINT_URL" == *"backblazeb2.com"* ]]; then
      STORAGE_PROVIDER="backblaze"
      log "S3 provider auto-detected: backblaze"
    elif [[ "$S3_ENDPOINT_URL" == *"wasabisys.com"* ]]; then
      STORAGE_PROVIDER="wasabi"
      log "S3 provider auto-detected: wasabi"
    elif [[ "$S3_ENDPOINT_URL" == *"amazonaws.com"* ]]; then
      STORAGE_PROVIDER="aws"
      log "S3 provider auto-detected: aws"
    else
      STORAGE_PROVIDER="custom"
      log "S3 provider auto-detected: custom"
    fi
  elif [[ -z "$STORAGE_PROVIDER" ]]; then
    STORAGE_PROVIDER="aws"
  fi
}

validate_s3() {
  if [[ "${ENABLE_S3_STORAGE:-false}" == "true" ]]; then
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]     && error "ENABLE_S3_STORAGE=true but AWS_ACCESS_KEY_ID not set"
    [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]] && error "ENABLE_S3_STORAGE=true but AWS_SECRET_ACCESS_KEY not set"
    [[ -z "${S3_BUCKET:-}" ]]             && error "ENABLE_S3_STORAGE=true but S3_BUCKET not set"
    case "$STORAGE_PROVIDER" in
      aws)
        [[ -z "${AWS_REGION:-}" ]] && error "STORAGE_PROVIDER=aws but AWS_REGION not set"
        log "S3: provider=AWS bucket=${S3_BUCKET} region=${AWS_REGION}"
        ;;
      backblaze)
        [[ -z "$S3_ENDPOINT_URL" ]] && error "STORAGE_PROVIDER=backblaze but S3_ENDPOINT_URL not set"
        log "S3: provider=Backblaze B2 bucket=${S3_BUCKET} endpoint=${S3_ENDPOINT_URL}"
        ;;
      wasabi)
        [[ -z "$S3_ENDPOINT_URL" ]] && error "STORAGE_PROVIDER=wasabi but S3_ENDPOINT_URL not set"
        log "S3: provider=Wasabi bucket=${S3_BUCKET} endpoint=${S3_ENDPOINT_URL}"
        ;;
      custom)
        [[ -z "$S3_ENDPOINT_URL" ]] && error "STORAGE_PROVIDER=custom but S3_ENDPOINT_URL not set"
        log "S3: provider=custom bucket=${S3_BUCKET} endpoint=${S3_ENDPOINT_URL}"
        ;;
      *)
        error "STORAGE_PROVIDER must be: aws | backblaze | wasabi | custom (got: ${STORAGE_PROVIDER})"
        ;;
    esac
  fi
}

validate_xelatex() {
  XELATEX_MODE="${XELATEX_MODE:-local}"
  if [[ "$XELATEX_MODE" == "remote" ]]; then
    [[ -z "${XELATEX_ENDPOINT:-}" ]] && error "XELATEX_MODE=remote but XELATEX_ENDPOINT not set"
    log "XeLaTeX mode: remote (${XELATEX_ENDPOINT})"
  else
    log "XeLaTeX mode: local (self-contained in worker container)"
  fi
}

validate_environment_mode() {
  ENV_MODE="${ENVIRONMENT_MODE:-production-isolated}"
  if [[ "$ENV_MODE" == "production-isolated" ]]; then
    ENVIRONMENTS="prod"
    log "Mode: production-isolated (prod only)"
  elif [[ "$ENV_MODE" == "all-in-one" ]]; then
    ENVIRONMENTS="${ENVIRONMENTS:-dev,stg,prod}"
    log "Mode: all-in-one (${ENVIRONMENTS})"
  else
    ENVIRONMENTS="prod"
    warn "ENVIRONMENT_MODE '${ENV_MODE}' unrecognised -- defaulting to production-isolated"
  fi
}

validate_disk() {
  AVAILABLE_KB=$(df / | awk 'NR==2 {print $4}')
  (( AVAILABLE_KB < 20971520 )) && \
    error "Only $(( AVAILABLE_KB / 1048576 ))GB free. At least 20GB required."
  log "Disk OK -- $(( AVAILABLE_KB / 1048576 ))GB free."
  DISK_USE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  (( DISK_USE > 80 )) && warn "Disk ${DISK_USE}% full -- risk of failure during install."
}
