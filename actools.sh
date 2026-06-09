#!/usr/bin/env bash
# =============================================================================
# Actools — Drupal 11 Enterprise Installer v14.0
# Ubuntu 24.04 | Docker CE · Caddy 2.8 · PHP-FPM · MariaDB 11.4 · Redis 7
# Dedicated Worker Image (XeLaTeX self-contained inside container)
# Multi-Provider S3 storage: AWS · Backblaze B2 · Wasabi · Custom
#
# v9.2 Changes (compatibility patch for MariaDB 11.4 + Docker Compose v2):
#   [fix1] MariaDB 11.4 dropped mysqladmin and mysql binaries.
#          Healthcheck now uses healthcheck.sh --connect --innodb_initialized.
#          All mysql client calls replaced with mariadb throughout.
#   [fix2] docker compose pull now skips locally-built images (caddy, worker)
#          by pulling only: db redis php_prod (avoids "pull access denied" error).
#   [fix3] pull_policy: never added to caddy and worker_prod services so Docker
#          Compose never attempts to pull locally-built images from registry.
#   [fix4] wait_db rewritten without timeout+subshell to avoid DB_ROOT_PASS
#          being unbound under set -u in the spawned bash process.
#   [fix5] Caddyfile log block expanded to multi-line (fixes "Unexpected token
#          after '{' on same line" parse error in Caddy 2.8).
#   [fix6] DB log dir pre-created with correct UID 999 ownership and slow.log
#          file pre-touched so MariaDB can open it on first start.
#   [fix7] Secret writeback regex now strips trailing comments from env file
#          lines before comparing, so DB_ROOT_PASS= with inline comments is
#          correctly matched and written back.
#   [fix8] version: '3.9' removed from generated docker-compose.yml (obsolete
#          in Compose v2, causes warning on every command).
#
# v9.1 Changes retained:
#   [fix1-5] S3FS config keys, backup cron cd, storage-info re-source,
#            CDN+endpoint in settings.php, lock file touch before exec.
#   [logs]   Per-run install logs in ~/logs/install/
#   [cli]    actools log-dir command
#
# v9.0 Changes retained:
#   XeLaTeX inside worker container, multi-provider S3, S3-aware backup cron,
#   storage-test/storage-info/migrate CLI commands.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

trap 'error "Script failed at line ${LINENO} -- command: ${BASH_COMMAND}"' ERR

# =============================================================================
# BOOTSTRAP
# =============================================================================
ACTOOLS_VERSION="14.0"
MODE="${1:-fresh}"

# 'install' is the new operator-facing name; 'fresh' is the legacy alias.
# Fresh still works — soft deprecation only, no exit on use.
if [[ "$MODE" == "fresh" ]]; then
  echo "Note: 'fresh' still works; 'install' is the new name. They run the same flow." >&2
fi
[[ "$MODE" == "install" ]] && MODE="fresh"

# 'help' / '--help' / '-h' / '--version' need no env file, lock, or sudo.
case "$MODE" in
  help|--help|-h)
    cat <<EOF
Actools Drupal Community v${ACTOOLS_VERSION}

Usage:
  sudo ./actools.sh init --domain <d> --email <e> [--site-name "<n>"]
  sudo ./actools.sh preflight
  sudo ./actools.sh install
  sudo ./actools.sh update
  sudo ./actools.sh handoff
  sudo ./actools.sh dry-run

After install:
  actools doctor   — daily health check
  actools help     — full CLI reference

Docs: docs/quick-start.md
EOF
    exit 0
    ;;
  --version|version)
    echo "actools v${ACTOOLS_VERSION}"
    exit 0
    ;;
esac

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"
# Re-exec with docker group if not already active — eliminates need for newgrp
# Skip re-exec if running as root (CI environment)
if [[ "$EUID" -ne 0 ]] && ! id -nG 2>/dev/null | grep -qw docker; then
  if id -nG "$REAL_USER" 2>/dev/null | grep -qw docker; then
    exec sg docker -c "bash $0 $*"
  fi
fi

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR
readonly DRUPAL_CONTAINER_DOCROOT="/var/www/html"   # served docroot inside php container (compose mount; image symlinks /opt/drupal/web here)
export DRUPAL_CONTAINER_DOCROOT
ENV_FILE="$INSTALL_DIR/actools.env"
STATE_FILE="$INSTALL_DIR/.actools-state.json"
LOCK_FILE="/tmp/actools.lock"
LOG_FILE="$INSTALL_DIR/actools-install.log"
LOG_DIR="$INSTALL_DIR/logs/install"
PKG_DONE_FLAG="/var/lib/actools/.packages_done"

# D.0: Source dispatch.sh early — provides resolver functions for all modes.
# Sourced here (after INSTALL_DIR is known) so init/preflight/handoff modes
# all have access. init.sh also sources it internally for independence.
# shellcheck source=/dev/null
source "${INSTALL_DIR}/installer/dispatch.sh" 2>/dev/null || true

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

mkdir -p "$LOG_DIR" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true
chown "$REAL_USER:$REAL_USER" "$LOG_FILE" 2>/dev/null || true
chown "$REAL_USER:$REAL_USER" "$LOG_DIR" 2>/dev/null || true
RUN_LOG="$LOG_DIR/actools-$(date +%F_%H%M%S).log"
touch "$RUN_LOG" 2>/dev/null || true
chown "$REAL_USER:$REAL_USER" "$RUN_LOG" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE" | tee -a "$RUN_LOG") 2>&1

log()     { echo -e "${G}[INFO ]${NC} $(date '+%F %T') $*"; }
warn()    { echo -e "${Y}[WARN ]${NC} $(date '+%F %T') $*"; }
error()   { echo -e "${R}[ERROR]${NC} $(date '+%F %T') $*"; exit 1; }
section() {
  echo -e "\n${C}══════════════════════════════════════════════════${NC}"
  echo -e "${C}  $*${NC}"
  echo -e "${C}══════════════════════════════════════════════════${NC}"
}

DRY_RUN=false
[[ "$MODE" == "dry-run" ]] && DRY_RUN=true
dryrun() { "$DRY_RUN" && { echo -e "${Y}[DRY-RUN]${NC} Would run: $*"; return 0; } || "$@"; }

log "Actools v${ACTOOLS_VERSION} started (mode=${MODE})"

# Lock file — remove stale lock from previous sudo/non-sudo run
if [[ -f "$LOCK_FILE" ]]; then
  if ! flock -n "$LOCK_FILE" true 2>/dev/null; then
    error "Another actools installation is already running."
  fi
  rm -f "$LOCK_FILE"
fi
touch "$LOCK_FILE" 2>/dev/null || true
chmod 666 "$LOCK_FILE" 2>/dev/null || true
exec 200>"$LOCK_FILE"
flock -n 200 || error "Another actools installation is already running."

# =============================================================================
# PRE-FLIGHT
# =============================================================================
section "Pre-flight Checks"

[[ "$(id -u)" -eq 0 ]]    || error "Run with sudo: sudo $0"
[[ -n "${SUDO_USER:-}" ]]  || error "Use 'sudo ./actools.sh', not running as root directly"

# 'init' mode runs before actools.env exists — it CREATES the env file.
# Shifts off MODE so positional args reach run_init unchanged.
if [[ "$MODE" == "init" ]]; then
  shift  # drop "init"
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh"
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/init.sh"
  # Disable strict-mode ERR trap — these handlers manage their own exit codes.
  trap - ERR
  set +e
  run_init "$@"
  exit $?
fi

[[ -f "$ENV_FILE" ]] || {
  error "Missing actools.env — run this first:
  sudo ./actools.sh init --domain <your-domain> --email <admin-email>
Then re-run: sudo ./actools.sh preflight"
}

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"

# Source modular install logic
source "${INSTALL_DIR}/modules/drupal/provision.sh" || error "Cannot load modules/drupal/provision.sh"
set +a

# Source modular host-provisioning logic (P0-G). These only DEFINE the host
# module functions; the `host` install stage executes them in the canonical
# monolith order (installer/dispatch.sh::actools::install::stage_host).
# install_packages runs first so the `age` package is present before
# setup_age_keypair. Host provisioning therefore now runs only on a fresh
# `install` (via the stage loop), not on dry-run/update/env — see
# docs/releases/P0-G-extract-host-stack.md.
for _hostmod in packages age kernel swap firewall docker logrotate; do
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/modules/host/${_hostmod}.sh" \
    || error "Cannot load modules/host/${_hostmod}.sh"
done
unset _hostmod

# Source modular stack-generation logic (P0-G). These define the stack
# generator functions; setup_stack delegates to them (and the golden-capture
# harness sources them too). Extracted incrementally — this list grows as each
# generated file moves out of setup_stack into modules/stack/*.
for _stackmod in mycnf images; do
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/modules/stack/${_stackmod}.sh" \
    || error "Cannot load modules/stack/${_stackmod}.sh"
done
unset _stackmod

[[ -z "${BASE_DOMAIN:-}" ]]        && error "BASE_DOMAIN is not set in $ENV_FILE"
[[ -z "${DRUPAL_ADMIN_EMAIL:-}" ]] && error "DRUPAL_ADMIN_EMAIL is not set in $ENV_FILE"
  [[ "${DRUPAL_ADMIN_EMAIL}" =~ ^[^@]+@[^@]+.[^@]+$ ]] || error "DRUPAL_ADMIN_EMAIL is not a valid email address: ${DRUPAL_ADMIN_EMAIL}"
[[ "${BASE_DOMAIN}" == *"example.com"* ]] &&   warn "BASE_DOMAIN looks like a placeholder. DNS must resolve before TLS works."

# DNS preflight — check domain resolves to this server
SERVER_IP="$(curl -s --max-time 5 ifconfig.me 2>/dev/null || true)"
DNS_IP="$(getent hosts "${BASE_DOMAIN}" 2>/dev/null | awk '{print $1}' | head -1 || true)"
if [[ -n "$SERVER_IP" && -n "$DNS_IP" && "$SERVER_IP" != "$DNS_IP" ]]; then
  warn "DNS mismatch: ${BASE_DOMAIN} resolves to ${DNS_IP} but this server is ${SERVER_IP}"
  warn "Caddy cannot obtain TLS certificates until DNS points to this server."
  warn "Continuing anyway — fix DNS before the site will be accessible via HTTPS."
elif [[ -n "$SERVER_IP" && -z "$DNS_IP" ]]; then
  warn "DNS not resolving: ${BASE_DOMAIN} has no A record yet."
  warn "Point your A record to ${SERVER_IP} before HTTPS will work."
  warn "Continuing install — DNS can be set after install completes."
else
  log "DNS check: ${BASE_DOMAIN} → ${DNS_IP} ✓"
fi

STORAGE_PROVIDER="${STORAGE_PROVIDER:-${S3_PROVIDER:-}}"
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-${S3_ENDPOINT:-}}"
ASSET_CDN_HOST="${ASSET_CDN_HOST:-${CLOUDFLARE_CDN_DOMAIN:-}}"

if [[ -z "$STORAGE_PROVIDER" && -n "$S3_ENDPOINT_URL" ]]; then
  if [[ "$S3_ENDPOINT_URL" == *"backblazeb2.com"* ]]; then
    STORAGE_PROVIDER="backblaze"
    log "S3 provider auto-detected: backblaze (from endpoint URL)"
  elif [[ "$S3_ENDPOINT_URL" == *"wasabisys.com"* ]]; then
    STORAGE_PROVIDER="wasabi"
    log "S3 provider auto-detected: wasabi (from endpoint URL)"
  elif [[ "$S3_ENDPOINT_URL" == *"amazonaws.com"* ]]; then
    STORAGE_PROVIDER="aws"
    log "S3 provider auto-detected: aws (from endpoint URL)"
  else
    STORAGE_PROVIDER="custom"
    log "S3 provider auto-detected: custom (unrecognised endpoint URL)"
  fi
elif [[ -z "$STORAGE_PROVIDER" ]]; then
  STORAGE_PROVIDER="aws"
fi

# ── New staged-journey modes (Doc 1 §5) ────────────────────────────────────
# 'preflight' and 'handoff' run after env is loaded but before any install
# work. They exit immediately after their own output. The strict-mode ERR
# trap is disabled inside these blocks because preflight legitimately
# returns 1 (failures) or 2 (warnings) — these are not "errors".
if [[ "$MODE" == "preflight" ]]; then
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh"
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/preflight.sh"
  trap - ERR
  set +e
  run_preflight
  exit $?
fi

if [[ "$MODE" == "handoff" ]]; then
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh"
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/handoff.sh"
  trap - ERR
  set +e
  run_handoff
  exit 0
fi

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
validate_env

if [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]]; then
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
      [[ -n "$ASSET_CDN_HOST" ]] && log "CDN: ${ASSET_CDN_HOST} (free egress via Cloudflare)"
      ;;
    wasabi)
      [[ -z "$S3_ENDPOINT_URL" ]] && error "STORAGE_PROVIDER=wasabi but S3_ENDPOINT_URL not set"
      log "S3: provider=Wasabi bucket=${S3_BUCKET} endpoint=${S3_ENDPOINT_URL}"
      ;;
    custom)
      [[ -z "$S3_ENDPOINT_URL" ]] && error "STORAGE_PROVIDER=custom but S3_ENDPOINT_URL not set"
      log "S3: provider=custom bucket=${S3_BUCKET} endpoint=${S3_ENDPOINT_URL}"
      [[ -n "$ASSET_CDN_HOST" ]] && log "CDN: ${ASSET_CDN_HOST}"
      ;;
    *)
      error "STORAGE_PROVIDER must be: aws | backblaze | wasabi | custom (got: ${STORAGE_PROVIDER})"
      ;;
  esac
fi

XELATEX_MODE="${XELATEX_MODE:-local}"
if [[ "$XELATEX_MODE" == "remote" ]]; then
  [[ -z "${XELATEX_ENDPOINT:-}" ]] && error "XELATEX_MODE=remote but XELATEX_ENDPOINT not set"
  log "XeLaTeX mode: remote (${XELATEX_ENDPOINT})"
else
  log "XeLaTeX mode: local (self-contained in worker container)"
fi

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

AVAILABLE_KB=$(df / | awk 'NR==2 {print $4}')
(( AVAILABLE_KB < 20971520 )) && \
  error "Only $(( AVAILABLE_KB / 1048576 ))GB free. At least 20GB required."
log "Disk OK -- $(( AVAILABLE_KB / 1048576 ))GB free."

DISK_USE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
(( DISK_USE > 80 )) && warn "Disk ${DISK_USE}% full -- risk of failure during install."

section "DNS Check"
for subdomain in "${BASE_DOMAIN}" "stg.${BASE_DOMAIN}" "dev.${BASE_DOMAIN}"; do
  getent hosts "$subdomain" >/dev/null 2>&1 \
    && log "DNS OK -- ${subdomain}" \
    || warn "DNS MISSING -- ${subdomain}. Let's Encrypt will fail until DNS propagates."
done

log "Pre-flight complete."

# =============================================================================
# SECRET GUARD + WRITEBACK
# [v9.2 fix7] Writeback strips trailing comments before matching, so lines like
#             DB_ROOT_PASS=                # comment  are correctly updated.
# =============================================================================
section "Secret Guard"

rand_pass() { while true; do p=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9'); [ ${#p} -ge 22 ] && echo "${p:0:22}" && break; done; }

gen_if_empty() {
  local var="$1"
  local val="${!var:-}"
  [[ "$val" == *"CHANGEME"* ]] && error "$var contains 'CHANGEME' -- set a real value."
  if [[ -z "$val" ]]; then
    log "$var empty -- auto-generating..."
    printf -v "$var" '%s' "$(rand_pass)"
    log "$var generated."
  fi
}

gen_if_empty DB_ROOT_PASS
gen_if_empty DRUPAL_ADMIN_PASS

# [v9.2 fix7] Writeback: match VAR= with optional trailing whitespace/comment.
# Uses a two-step approach: strip the line, rewrite with clean value.
for var in DB_ROOT_PASS DRUPAL_ADMIN_PASS; do
  val="${!var}"
  # Match lines that are VAR= (empty value, with or without trailing comment/spaces)
  if grep -qP "^${var}=\s*(#.*)?$" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${var}=.*|${var}=${val}|" "$ENV_FILE"
    log "${var} written back to env file."
  fi
done
log "Secrets ready."

# =============================================================================
# STATE MANAGEMENT
# =============================================================================
init_state() {
  [[ -f "$STATE_FILE" ]] || echo '{"envs":{},"db_passes":{}}' > "$STATE_FILE"
  chown "$REAL_USER:$REAL_USER" "$STATE_FILE" 2>/dev/null || true
}

set_state()      { local tmp; tmp=$(mktemp); jq "$1" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"; }
get_state()      { jq -r "$1" "$STATE_FILE" 2>/dev/null || echo "null"; }
is_installed()   { jq -e ".envs.$1 == true" "$STATE_FILE" >/dev/null 2>&1; }
mark_installed() { set_state ".envs.$1=true"; }

get_db_pass() {
  local env="$1" pass
  pass=$(get_state ".db_passes.${env}")
  if [[ "$pass" == "null" || -z "$pass" ]]; then
    pass=$(rand_pass)
    set_state ".db_passes.${env}=\"${pass}\""
  fi
  echo "$pass"
}

get_backup_pass() {
  local pass
  pass=$(get_state ".backup_user_pass")
  if [[ "$pass" == "null" || -z "$pass" ]]; then
    pass=$(rand_pass)
    set_state ".backup_user_pass=\"${pass}\""
  fi
  echo "$pass"
}

# =============================================================================
# SETUP STACK
# =============================================================================
setup_stack() {
  section "Stack Setup (v14.0)"

  mkdir -p "$INSTALL_DIR/docroot"/{dev,stg,prod}
  mkdir -p "$INSTALL_DIR"/{caddy/{data,config},logs/{caddy,db,worker,install},backups}
  for env in dev stg prod; do
    mkdir -p "$INSTALL_DIR/logs/php_${env}"
  done

  # [v9.2 fix6] Pre-create DB log dir with correct ownership (UID 999 = mysql in container)
  # and pre-touch slow.log so MariaDB can open it without permission errors.
  chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR" 2>/dev/null || true
  chown -R 999:999 "$INSTALL_DIR/logs/db" 2>/dev/null || true
  touch "$INSTALL_DIR/logs/db/slow.log" 2>/dev/null || true
  chown 999:999 "$INSTALL_DIR/logs/db/slow.log" 2>/dev/null || true
  chmod 664 "$INSTALL_DIR/logs/db/slow.log" 2>/dev/null || true

  # The recursive chown above owns all install files (incl. the age keypair) to REAL_USER.

  BACKUP_PASS=$(get_backup_pass)

  # ── MariaDB my.cnf ──────────────────────────────────────────────────────────
  generate_mycnf

  # ── Container images: Caddy / PHP / worker (modules/stack/images.sh) ─────────
  build_caddy_image
  build_php_image
  build_worker_image

  # ── Caddyfile ───────────────────────────────────────────────────────────────
  # [v9.2 fix5] log block expanded to multi-line to avoid Caddy 2.8 parse error.
  cat > "$INSTALL_DIR/Caddyfile" <<CADDY
{
    email ${DRUPAL_ADMIN_EMAIL}
    log {
        level INFO
    }
}

(drupal_base) {
    encode zstd gzip

    @static {
        file
        path *.css *.js *.png *.jpg *.jpeg *.gif *.svg *.woff2 *.woff *.ico *.pdf
    }
    header @static Cache-Control "public, max-age=31536000, immutable"

    header {
        Strict-Transport-Security        "max-age=31536000; includeSubDomains"
        X-Content-Type-Options           "nosniff"
        X-Frame-Options                  "SAMEORIGIN"
        Referrer-Policy                  "strict-origin-when-cross-origin"
        Permissions-Policy               "camera=(), microphone=(), geolocation=()"
        Content-Security-Policy-Report-Only "default-src \'self\' \'unsafe-inline\' \'unsafe-eval\' https:; report-uri /csp-violations"
        -Server
        -X-Powered-By
        -X-Generator
    }

    handle /health {
        respond "OK" 200
    }

    handle /csp-violations {
        respond "logged" 204
    }

    @login {
        path /user/login /user/password
    }
    rate_limit @login {
        zone login_protect {
            key {remote_host}
            events 5
            window 60s
        }
    }

    file_server
}

$(if [[ "$ENVIRONMENT_MODE" == "all-in-one" ]]; then
cat <<ALLINONE
dev.${BASE_DOMAIN} {
    root * /var/www/html/dev/web
    php_fastcgi php_dev:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}

stg.${BASE_DOMAIN} {
    root * /var/www/html/stg/web
    php_fastcgi php_stg:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}
ALLINONE
fi)

${BASE_DOMAIN} {
    root * /var/www/html/prod/web
    php_fastcgi php_prod:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}
CADDY

  # ── Docker Compose ──────────────────────────────────────────────────────────
  local WEB_MEM="${PHP_MEMORY_LIMIT:-512m}"
  local WORKER_MEM="${WORKER_MEMORY_LIMIT:-2g}"
  local DB_MEM="${DB_MEMORY_LIMIT:-2g}"
  local REDIS_MEM="${REDIS_MEMORY_LIMIT:-256m}"
  local CADVISOR="${ENABLE_CADVISOR:-false}"
  local REDIS_ON="${ENABLE_REDIS:-true}"

  PHP_ENV_BLOCK="
      PHP_MEMORY_LIMIT: \"${WEB_MEM}\"
      PHP_UPLOAD_MAX_FILESIZE: \"${PHP_UPLOAD_MAX:-256m}\"
      PHP_MAX_EXECUTION_TIME: \"${PHP_MAX_EXEC:-300}\"
      COMPOSER_PROCESS_TIMEOUT: \"${COMPOSER_PROCESS_TIMEOUT:-600}\"
      PHP_OPCACHE_ENABLE: \"${PHP_OPCACHE_ENABLE:-1}\"
      PHP_OPCACHE_MEMORY_CONSUMPTION: \"${PHP_OPCACHE_MEMORY:-256}\"
      PHP_OPCACHE_MAX_ACCELERATED_FILES: \"${PHP_OPCACHE_MAX_FILES:-20000}\"
      PHP_OPCACHE_VALIDATE_TIMESTAMPS: \"${PHP_OPCACHE_VALIDATE_TIMESTAMPS:-1}\""

  WORKER_ENV_BLOCK="
      PHP_MEMORY_LIMIT: \"${WORKER_MEM}\"
      PHP_UPLOAD_MAX_FILESIZE: \"${PHP_UPLOAD_MAX:-256m}\"
      PHP_MAX_EXECUTION_TIME: \"600\"
      COMPOSER_PROCESS_TIMEOUT: \"${COMPOSER_PROCESS_TIMEOUT:-600}\"
      XELATEX_MODE: \"${XELATEX_MODE:-local}\"
      XELATEX_ENDPOINT: \"${XELATEX_ENDPOINT:-}\"
      AWS_ACCESS_KEY_ID: \"${AWS_ACCESS_KEY_ID:-}\"
      AWS_SECRET_ACCESS_KEY: \"${AWS_SECRET_ACCESS_KEY:-}\"
      S3_BUCKET: \"${S3_BUCKET:-}\"
      STORAGE_PROVIDER: \"${STORAGE_PROVIDER:-}\"
      AWS_REGION: \"${AWS_REGION:-us-east-1}\"
      S3_ENDPOINT_URL: \"${S3_ENDPOINT_URL:-}\"
      ASSET_CDN_HOST: \"${ASSET_CDN_HOST:-}\""

  S3_ENV_BLOCK="
      AWS_ACCESS_KEY_ID: \"${AWS_ACCESS_KEY_ID:-}\"
      AWS_SECRET_ACCESS_KEY: \"${AWS_SECRET_ACCESS_KEY:-}\"
      S3_BUCKET: \"${S3_BUCKET:-}\"
      STORAGE_PROVIDER: \"${STORAGE_PROVIDER:-}\"
      AWS_REGION: \"${AWS_REGION:-us-east-1}\"
      S3_ENDPOINT_URL: \"${S3_ENDPOINT_URL:-}\"
      ASSET_CDN_HOST: \"${ASSET_CDN_HOST:-}\""

  PHP_SEC_BLOCK="
    tmpfs:
      - /tmp:size=256m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - SETUID
      - SETGID
      - DAC_OVERRIDE"

  # [v9.2 fix8] version: removed (obsolete in Compose v2)
  cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
networks:
  actools_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
  db_data:

services:

  caddy:
    image: actools_caddy:custom
    pull_policy: never
    container_name: actools_caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./docroot:/var/www/html:ro
      - ./caddy/data:/data
      - ./caddy/config:/config
      - ./logs/caddy:/var/log/caddy
    depends_on:
      - php_prod
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  php_prod:
    image: actools_php:custom
    container_name: actools_php_prod
    restart: unless-stopped
    volumes:
      - ./docroot/prod:/var/www/html/prod
      - ./logs/php_prod:/var/log/php
    environment:${PHP_ENV_BLOCK}${S3_ENV_BLOCK}
    mem_limit: "${WEB_MEM}"${PHP_SEC_BLOCK}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  worker_prod:
    image: actools_worker:latest
    pull_policy: never
    container_name: actools_worker_prod
    restart: unless-stopped
    command: ["bash", "-c", "while true; do sleep 60; done"]
    volumes:
      - ./docroot/prod:/var/www/html/prod
      - ./logs/worker:/var/log/worker
    environment:${WORKER_ENV_BLOCK}
    mem_limit: "${WORKER_MEM}"${PHP_SEC_BLOCK}
    healthcheck:
      test: ["CMD-SHELL", "php -v && xelatex --version > /dev/null 2>&1"]
      interval: 60s
      timeout: 15s
      retries: 3
      start_period: 60s
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

$(if [[ "$ENVIRONMENT_MODE" == "all-in-one" ]]; then
cat <<ALLINONE_SVC
  php_dev:
    image: actools_php:custom
    container_name: actools_php_dev
    restart: unless-stopped
    volumes:
      - ./docroot/dev:/var/www/html/dev
      - ./logs/php_dev:/var/log/php
    environment:${PHP_ENV_BLOCK}
    mem_limit: "${WEB_MEM}"${PHP_SEC_BLOCK}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    depends_on:
      db:
        condition: service_healthy
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  php_stg:
    image: actools_php:custom
    container_name: actools_php_stg
    restart: unless-stopped
    volumes:
      - ./docroot/stg:/var/www/html/stg
      - ./logs/php_stg:/var/log/php
    environment:${PHP_ENV_BLOCK}
    mem_limit: "${WEB_MEM}"${PHP_SEC_BLOCK}
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    depends_on:
      db:
        condition: service_healthy
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
ALLINONE_SVC
fi)

  db:
    image: mariadb:${MARIADB_VERSION}
    container_name: actools_db
    restart: unless-stopped
    stop_grace_period: 2m
    environment:
      MARIADB_ROOT_PASSWORD: "${DB_ROOT_PASS}"
      MARIADB_AUTO_UPGRADE: "1"
    volumes:
      - db_data:/var/lib/mysql
      - ./logs/db:/var/log/mysql
      - ./my.cnf:/etc/mysql/conf.d/actools.cnf:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 8
      start_period: 30s
    networks:
      - actools_net
    mem_limit: "${DB_MEM}"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

$(if [[ "${REDIS_ON}" == "true" ]]; then
cat <<REDIS_SVC
  redis:
    image: redis:7-alpine
    container_name: actools_redis
    restart: unless-stopped
    command: redis-server --maxmemory ${REDIS_MEM} --maxmemory-policy allkeys-lru
    mem_limit: "${REDIS_MEM}"
    networks:
      - actools_net
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"
REDIS_SVC
fi)

$(if [[ "${CADVISOR}" == "true" ]]; then
cat <<CADVISOR_SVC
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: actools_cadvisor
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    networks:
      - actools_net
CADVISOR_SVC
fi)
COMPOSE

  log "Pulling Docker images..."
  PULL_OK=0
  # [v9.2 fix2] Pull only registry images -- skip locally-built caddy and worker.
  for attempt in 1 2 3; do
    if docker compose -f "$INSTALL_DIR/docker-compose.yml" pull db redis; then
      PULL_OK=1; break
    fi
    warn "Pull failed (attempt ${attempt}/3). Retrying in 5s..."
    sleep 5
  done
  [[ $PULL_OK -eq 1 ]] || error "Docker image pull failed after 3 attempts."

  cd "$INSTALL_DIR"
  docker compose down --remove-orphans 2>/dev/null || true
  docker compose up -d
  log "Stack started."

  setup_backup_db_user "$BACKUP_PASS"
}


# =============================================================================
# DB ACCESS HELPERS — remove password from host argv (3a)
# =============================================================================
# Run a root mariadb command inside the db container with no password on the host argv.
# The container already holds MARIADB_ROOT_PASSWORD; we expose it to the client as MYSQL_PWD
# *inside* the container. Caller passes mariadb args ($@), e.g. -e "..." or a heredoc on stdin.
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}

# Pipe-fed root mariadb (e.g. restore): stdin is the piped SQL; $1 is the target database.
# Password from container env (MYSQL_PWD); db name passed positionally. No password on host argv.
db_exec_root_stdin() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$1"' _ "$1"
}

# Backup-user dump inside the db container, least-privilege preserved.
# Password fed via a transient 0600 defaults-file written from a heredoc on stdin (never on any argv).
# $1 = backup password; remaining args = dump args (db name, --single-transaction, etc.).
# Caller pipes stdout to gzip as before.
db_dump_container() {
  local _bp="$1"; shift
  docker exec -i actools_db sh -c '
    umask 077
    tmp="$(mktemp /tmp/actools-dump.XXXXXX.cnf)"
    trap "rm -f \"$tmp\"" EXIT
    cat > "$tmp"
    mariadb-dump --defaults-extra-file="$tmp" "$@"
  ' _ "$@" <<EOF
[mariadb-dump]
user=backup
password=${_bp}
EOF
}

# =============================================================================
# BACKUP DB USER
# =============================================================================
setup_backup_db_user() {
  local backup_pass="$1"
  wait_db
  # [v9.2 fix1] Use mariadb client (mysql removed in MariaDB 11.4)
  db_exec_root <<SQL
CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY '${backup_pass}';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* TO 'backup'@'%';
FLUSH PRIVILEGES;
SQL
  log "DB backup user created."
}

# =============================================================================
# WAIT FOR DB
# [v9.2 fix4] Rewritten without timeout+subshell -- DB_ROOT_PASS was unbound
#             under set -u when passed into a spawned bash -c process.
# =============================================================================
wait_db() {
  cd "$INSTALL_DIR"
  log "Waiting for MariaDB (write-check)..."
  local _wp="${DB_ROOT_PASS}"
  local _tries=0
  until docker compose exec -T db mariadb -uroot -p"${_wp}" \
    -e "CREATE TABLE IF NOT EXISTS mysql.actools_write_check (id INT); DROP TABLE IF EXISTS mysql.actools_write_check;" \
    &>/dev/null 2>&1; do
    _tries=$(( _tries + 1 ))
    [[ $_tries -ge 50 ]] && error "MariaDB did not become ready within 150s."
    sleep 3
  done
  log "MariaDB ready."
}

# =============================================================================
# DB CREDENTIAL PROBE
# =============================================================================
check_db_creds() {
  cd "$INSTALL_DIR"
  db_exec_root -e "SELECT 1;" &>/dev/null 2>&1 \
    || error "Cannot authenticate to MariaDB with current DB_ROOT_PASS.
  Revert DB_ROOT_PASS in actools.env to the previously generated value, or:
  docker compose exec db mariadb -uroot -p<old_pass> -e \"ALTER USER 'root'@'%' IDENTIFIED BY '<new_pass>';\""
  log "DB credentials verified."
}

# =============================================================================
# INSTALL DRUPAL ENVIRONMENT
# =============================================================================
install_env() {
  local env="$1"
  local php_svc="php_${env}"
  local db_name="actools_${env}"
  local db_pass
  db_pass=$(get_db_pass "$env")

  section "Installing Drupal: ${env}"

  if is_installed "$env"; then
    log "${env} already installed -- running database updates only."
    cd "$INSTALL_DIR"
    docker compose exec -T "$php_svc" bash -c "
      cd /var/www/html/${env}
      ./vendor/bin/drush updb --yes 2>&1 || true
      ./vendor/bin/drush cr 2>&1 || true
    " 2>&1 || warn "drush updates failed for ${env}"
    # Re-apply www-data ownership — second run resets via chown -R REAL_USER
    if id www-data &>/dev/null; then
      chown -R www-data:www-data "$INSTALL_DIR/docroot/${env}/web/sites/default/files" 2>/dev/null || true
      chown -R www-data:www-data "$INSTALL_DIR/docroot/${env}/private" 2>/dev/null || true
    fi
    return
  fi

  wait_db

  # [v9.2 fix1] Use mariadb client
  db_exec_root <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_name}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_name}'@'%';
FLUSH PRIVILEGES;
SQL

  # Stage 2: Drupal install, settings injection, permissions
  drupal_provision "$env"

  mark_installed "$env"
  set_state ".db_passes.${env}=\"${db_pass}\""
  echo "[${env}] DB: ${db_name}  User: ${db_name}  Pass: ${db_pass}" \
    >> "$REAL_HOME/.actools-db-creds"
  chmod 600 "$REAL_HOME/.actools-db-creds" 2>/dev/null || true
  log "${env} ready."
}

# =============================================================================
# DAILY BACKUP CRON
# =============================================================================
setup_backup_cron() {
  section "Backup Cron"
  local backup_dir="$INSTALL_DIR/backups"
  local backup_pass
  backup_pass=$(get_backup_pass)
  local s3_on="${ENABLE_S3_STORAGE:-true}"
  local s3_bucket="${S3_BUCKET:-}"
  local s3_endpoint="${S3_ENDPOINT_URL:-}"
  local s3_provider="${STORAGE_PROVIDER:-aws}"

  cat > /etc/cron.daily/actools-backup <<BACKUP
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="${backup_dir}"
INSTALL_DIR="${INSTALL_DIR}"
TIMESTAMP=\$(date +%F)
ENABLE_S3_STORAGE="${s3_on}"
S3_BUCKET="${s3_bucket}"
S3_ENDPOINT_URL="${s3_endpoint}"
STORAGE_PROVIDER="${s3_provider}"

command -v docker &>/dev/null || exit 1
cd "\${INSTALL_DIR}" || { echo "ERROR: INSTALL_DIR not found: \${INSTALL_DIR}" >&2; exit 1; }

for env in $(echo "${ENVIRONMENTS}" | tr ',' ' '); do
  DB="actools_\${env}"
  DUMPFILE="\${BACKUP_DIR}/\${env}_db_\${TIMESTAMP}.sql.gz"
  BK=\$(jq -r '.backup_user_pass // empty' "${INSTALL_DIR}/.actools-state.json")
  printf '%s\n' '[mariadb-dump]' 'user=backup' "password=\$BK" \
    | docker exec -i actools_db sh -c '
        umask 077; t=\$(mktemp /tmp/actools-dump.XXXXXX.cnf); trap "rm -f \"\$t\"" EXIT
        cat > "\$t"
        mariadb-dump --defaults-extra-file="\$t" "\$@"
      ' _ --single-transaction --quick "\$DB" \
    | gzip > "\$DUMPFILE"
  sha256sum "\$DUMPFILE" > "\$DUMPFILE.sha256"
  sha256sum -c "\$DUMPFILE.sha256" &>/dev/null || {
    echo "DB backup FAILED integrity check: \$DUMPFILE" >&2
    rm -f "\$DUMPFILE" "\$DUMPFILE.sha256"
  }

  if [[ "\${ENABLE_S3_STORAGE}" == "true" ]]; then
    if docker compose exec -T php_prod bash -c \
      "cd /var/www/html/prod && ./vendor/bin/drush s3fs:refresh-cache 2>/dev/null" \
      &>/dev/null 2>&1; then
      echo "S3 reachability OK for \${env} (bucket: \${S3_BUCKET})"
    else
      echo "WARNING: S3 bucket unreachable for \${env} -- files not backed up" >&2
    fi
  else
    FILES_SRC="${INSTALL_DIR}/docroot/\${env}/web/sites/default/files"
    FILES_DST="\${BACKUP_DIR}/\${env}_files_\${TIMESTAMP}.tar.gz"
    if [[ -d "\$FILES_SRC" ]]; then
      tar -czf "\$FILES_DST" -C "\$FILES_SRC" . && \
        sha256sum "\$FILES_DST" > "\$FILES_DST.sha256" && \
        sha256sum -c "\$FILES_DST.sha256" &>/dev/null || {
          echo "Files backup FAILED integrity check: \$FILES_DST" >&2
          rm -f "\$FILES_DST" "\$FILES_DST.sha256"
        }
    fi
  fi
done

find "\${BACKUP_DIR}" -name "*.sql.gz"        -mtime +${BACKUP_RETENTION_DAYS:-7} -delete
find "\${BACKUP_DIR}" -name "*.sql.gz.sha256"  -mtime +${BACKUP_RETENTION_DAYS:-7} -delete
find "\${BACKUP_DIR}" -name "*.tar.gz"         -mtime +${BACKUP_RETENTION_DAYS:-7} -delete
find "\${BACKUP_DIR}" -name "*.tar.gz.sha256"  -mtime +${BACKUP_RETENTION_DAYS:-7} -delete

RCLONE_REMOTE="${RCLONE_REMOTE:-}"
if [[ -n "\${RCLONE_REMOTE}" ]] && command -v rclone &>/dev/null; then
  rclone copy "\${BACKUP_DIR}" "\${RCLONE_REMOTE}/" \
    --include "*.sql.gz" --include "*.tar.gz" \
    && echo "Remote backup pushed to \${RCLONE_REMOTE}"
fi
BACKUP
  chmod +x /etc/cron.daily/actools-backup
  log "Daily backup cron installed (S3-aware)."
}

# =============================================================================
# CLI HELPER
# =============================================================================
setup_cli() {
  # P0-F: the CLI is installed by copying the single canonical source
  # (cli/actools) verbatim. The previous heredoc that re-emitted a second
  # CLI implementation has been removed — see
  # docs/architecture/cli-authority-contract.md (Option A). cli/actools
  # reads its config at runtime (ACTOOLS_HOME / actools.env / state.json),
  # so nothing needs baking in at install time.
  install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools
  chmod +x /usr/local/bin/actools
  log "CLI installed: /usr/local/bin/actools"
  # Write ACTOOLS_HOME so CLI always finds the install directory
  grep -q "ACTOOLS_HOME" /etc/environment 2>/dev/null && \
    sed -i "s|ACTOOLS_HOME=.*|ACTOOLS_HOME=${INSTALL_DIR}|" /etc/environment \
    || echo "ACTOOLS_HOME=${INSTALL_DIR}" >> /etc/environment
  log "ACTOOLS_HOME set to ${INSTALL_DIR}"
}

# =============================================================================
# TLS CHECK
# =============================================================================
tls_check() {
  section "TLS Readiness Check"
  sleep 5
  IFS=',' read -ra ENVS <<< "$ENVIRONMENTS"
  for env in "${ENVS[@]}"; do
    env="${env// /}"
    domain="${env}.${BASE_DOMAIN}"
    [[ "$env" == "prod" ]] && domain="${BASE_DOMAIN}"
    curl -sSf --max-time 15 "https://${domain}" &>/dev/null \
      && log "TLS OK -- https://${domain}" \
      || warn "TLS pending for https://${domain} -- Caddy may still be obtaining cert."
  done
  warn "If certs are pending, wait 60s then run: actools tls-status"
}

send_webhook() {
  [[ -n "${NOTIFY_WEBHOOK:-}" ]] || return 0
  curl -fsS -X POST "${NOTIFY_WEBHOOK}" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"Actools v${ACTOOLS_VERSION} complete. https://${BASE_DOMAIN}\"}" \
    --max-time 10 &>/dev/null \
    && log "Webhook sent." \
    || warn "Webhook ping failed -- install succeeded anyway."
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  init_state

  if [[ "$DRY_RUN" == "true" ]]; then
    section "DRY-RUN MODE (v9.2)"
    echo -e "  Base domain      : ${C}${BASE_DOMAIN}${NC}"
    echo -e "  Environments     : ${C}${ENVIRONMENTS}${NC}"
    echo -e "  Web memory       : ${C}${PHP_MEMORY_LIMIT:-512m}${NC}"
    echo -e "  Worker memory    : ${C}${WORKER_MEMORY_LIMIT:-2g}${NC}"
    echo -e "  DB memory        : ${C}${DB_MEMORY_LIMIT:-2g}${NC}"
    echo -e "  Redis            : ${C}${ENABLE_REDIS:-true}${NC}"
    echo -e "  Storage provider : ${C}${STORAGE_PROVIDER}${NC}"
    [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]] && \
      echo -e "  S3 bucket        : ${C}${S3_BUCKET:-not set}${NC}"
    [[ -n "${ASSET_CDN_HOST:-}" ]] && \
      echo -e "  CDN host         : ${C}${ASSET_CDN_HOST}${NC}"
    echo -e "  XeLaTeX mode     : ${C}${XELATEX_MODE:-local}${NC}"
    echo -e "  Swap             : ${C}${ENABLE_SWAP:-true} (${SWAP_SIZE:-4G})${NC}"
    echo -e "  MariaDB InnoDB   : ${C}${INNODB_BUFFER_POOL:-1G}${NC} buffer pool"
    echo ""
    echo "  No changes were made. Run without 'dry-run' to proceed."
    exit 0
  fi

  case "$MODE" in
    fresh)
      section "Confirmation"
      echo -e "  Base domain      : ${C}${BASE_DOMAIN}${NC}"
      echo -e "  Environments     : ${C}${ENVIRONMENTS}${NC}"
      echo -e "  Web memory       : ${C}${PHP_MEMORY_LIMIT:-512m}${NC}"
      echo -e "  Worker memory    : ${C}${WORKER_MEMORY_LIMIT:-2g}${NC}"
      echo -e "  DB memory        : ${C}${DB_MEMORY_LIMIT:-2g}${NC}"
      echo -e "  Storage provider : ${C}${STORAGE_PROVIDER}${NC}"
      echo -e "  XeLaTeX mode     : ${C}${XELATEX_MODE:-local}${NC}"
      echo -e "  Redis            : ${C}${ENABLE_REDIS:-true}${NC}"
      echo ""
      # Auto-confirm in CI or when running as root
      if [[ "${CI:-false}" == "true" || "$EUID" -eq 0 ]]; then
        reply="y"
        echo "  Auto-confirmed (CI/root mode)"
      else
        read -rp "  Proceed? [y/N] " reply; echo
      fi
      [[ "$reply" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }

      # P0-D: route the install through the stage dispatcher instead of a
      # hardcoded setup_stack + install_env sequence. Community is the only
      # shipped profile and P0-D is community-only; profile SELECTION by
      # ACTOOLS_PROFILE arrives in P0-E. Sourcing the profile here yields the
      # canonical PROFILE_INSTALL_STAGES=(host stack db drupal worker); the
      # stage handlers in installer/dispatch.sh call setup_stack and the
      # per-env install_env loop UNCHANGED, so behavior and generated output
      # stay byte-identical.
      # shellcheck source=/dev/null
      source "${INSTALL_DIR}/profiles/community.profile"
      for stage in "${PROFILE_INSTALL_STAGES[@]}"; do
        actools::dispatch::run_install_stage "$stage"
      done

      setup_backup_cron
      setup_cli
      tls_check
      ;;

    update)
      section "Update"
      check_db_creds
      cd "$INSTALL_DIR"
      BACKUP_PASS=$(get_backup_pass)
      log "Pre-update prod snapshot..."
      SNAP="$INSTALL_DIR/backups/pre_update_prod_$(date +%F_%H%M%S).sql.gz"
      db_dump_container "${BACKUP_PASS}" --single-transaction --quick actools_prod \
        | gzip > "$SNAP" && log "Snapshot: $SNAP" || warn "Snapshot failed (non-fatal)"
      docker compose pull db redis
      docker compose up -d
      IFS=',' read -ra ENVS <<< "$ENVIRONMENTS"
      for env in "${ENVS[@]}"; do
        env="${env// /}"
        is_installed "$env" || continue
        log "drush updb for ${env}..."
        docker compose exec -T "php_${env}" bash -c "
          cd /var/www/html/${env} && ./vendor/bin/drush updb --yes && ./vendor/bin/drush cr
        " 2>&1 || warn "drush updb failed for ${env}"
      done
      docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
      log "Update complete."
      ;;

    env)
      TARGET="${2:-}"
      [[ -z "$TARGET" ]] && error "Specify env: sudo ./actools.sh env dev|stg|prod"
      [[ "$TARGET" =~ ^(dev|stg|prod)$ ]] || error "Invalid environment: $TARGET"
      check_db_creds
      cd "$INSTALL_DIR"
      docker compose up -d
      install_env "$TARGET"
      ;;

    *)
      error "Unknown mode: $MODE. Use: init | preflight | install | update | env <dev|stg|prod> | handoff | dry-run | help"
      ;;
  esac

  echo "${DRUPAL_ADMIN_PASS}" > "$REAL_HOME/.actools-admin-pass"
  chmod 600 "$REAL_HOME/.actools-admin-pass"
  chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.actools-admin-pass" 2>/dev/null || true

  send_webhook

  # Write the install-complete marker (used by doctor and external tooling)
  touch "${INSTALL_DIR}/.actools-install-complete" 2>/dev/null || true
  chown "$REAL_USER:$REAL_USER" "${INSTALL_DIR}/.actools-install-complete" 2>/dev/null || true

  # Hand off to the operator with a clean summary (Doc 1 §5.5)
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh"
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/handoff.sh"
  run_handoff
}

main "$@"
