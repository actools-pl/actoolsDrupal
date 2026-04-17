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

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$INSTALL_DIR/actools.env"
STATE_FILE="$INSTALL_DIR/.actools-state.json"
LOCK_FILE="/tmp/actools.lock"
LOG_FILE="$INSTALL_DIR/actools-install.log"
LOG_DIR="$INSTALL_DIR/logs/install"
PKG_DONE_FLAG="/var/lib/actools/.packages_done"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

mkdir -p "$LOG_DIR" 2>/dev/null || true
RUN_LOG="$LOG_DIR/actools-$(date +%F_%H%M%S).log"
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

touch "$LOCK_FILE" 2>/dev/null || true
exec 200>"$LOCK_FILE"
flock -n 200 || error "Another actools installation is already running."

# =============================================================================
# PRE-FLIGHT
# =============================================================================
section "Pre-flight Checks"

[[ "$(id -u)" -eq 0 ]]    || error "Run with sudo: sudo $0"
[[ -n "${SUDO_USER:-}" ]]  || error "Use 'sudo ./actools.sh', not running as root directly"
[[ -f "$ENV_FILE" ]] || {
  error "Missing actools.env — run this first:
  cp actools.env.example actools.env
  nano actools.env   # set BASE_DOMAIN and DRUPAL_ADMIN_EMAIL
Then re-run: sudo ./actools.sh"
}

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

[[ -z "${BASE_DOMAIN:-}" ]]        && error "BASE_DOMAIN is not set in $ENV_FILE"
[[ -z "${DRUPAL_ADMIN_EMAIL:-}" ]] && error "DRUPAL_ADMIN_EMAIL is not set in $ENV_FILE"
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

rand_pass() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 22; }

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
# PACKAGES -- idempotent
# =============================================================================
section "System Packages"
mkdir -p /var/lib/actools
if [[ ! -f "$PKG_DONE_FLAG" ]]; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  apt-get install -y -qq \
    curl git unzip zip jq ca-certificates gnupg lsb-release \
    ufw fail2ban rclone dnsutils logrotate
  touch "$PKG_DONE_FLAG"
  log "Packages installed."
else
  log "Packages already installed -- skipping upgrade."
fi

# =============================================================================
# KERNEL TUNING
# =============================================================================
section "Kernel Tuning"
cat > /etc/sysctl.d/99-actools.conf <<SYSCTL
vm.overcommit_memory=1
vm.swappiness=10
fs.file-max=2097152
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=10240 65535
SYSCTL
sysctl --system >/dev/null 2>&1
log "Kernel tuning applied."

# =============================================================================
# SWAP
# =============================================================================
section "Swap Configuration"
if [[ "${ENABLE_SWAP:-true}" == "true" ]]; then
  if ! swapon --show | grep -q '/'; then
    SWAP="${SWAP_SIZE:-4G}"
    log "Creating ${SWAP} swap file..."
    fallocate -l "$SWAP" /swapfile && chmod 600 /swapfile
    mkswap /swapfile && swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap active: ${SWAP}."
  else
    log "Swap already configured -- skipping."
  fi
else
  warn "Swap disabled. XeLaTeX in worker container may OOM on large papers."
fi

# =============================================================================
# FIREWALL
# =============================================================================
section "Firewall"
ufw limit 22/tcp  comment 'SSH rate-limited'  2>/dev/null || true
ufw allow 80/tcp  comment 'HTTP Caddy ACME'   2>/dev/null || true
ufw allow 443/tcp comment 'HTTPS'             2>/dev/null || true
ufw allow 443/udp comment 'HTTP/3 QUIC'       2>/dev/null || true
ufw --force enable
systemctl enable --now fail2ban
log "UFW + fail2ban active."

# =============================================================================
# DOCKER CE
# =============================================================================
section "Docker Engine"
if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  usermod -aG docker "$REAL_USER"
  log "Docker CE installed."
else
  log "Docker present: $(docker --version)"
fi

if [[ ! -f /etc/docker/daemon.json ]]; then
  cat > /etc/docker/daemon.json <<DAEMON
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON
  systemctl reload docker 2>/dev/null || true
  log "Docker daemon log rotation configured."
fi

! docker compose version &>/dev/null && apt-get install -y -qq docker-compose-plugin
systemctl enable --now docker
log "Docker Compose: $(docker compose version)"

# =============================================================================
# HOST LOG ROTATION
# =============================================================================
cat > /etc/logrotate.d/actools <<LOGROTATE
${INSTALL_DIR}/logs/*/*.log
${INSTALL_DIR}/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTATE
log "Host log rotation configured."

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
  chown -R 999:999 "$INSTALL_DIR/logs/db" 2>/dev/null || true
  touch "$INSTALL_DIR/logs/db/slow.log" 2>/dev/null || true
  chown 999:999 "$INSTALL_DIR/logs/db/slow.log" 2>/dev/null || true
  chmod 664 "$INSTALL_DIR/logs/db/slow.log" 2>/dev/null || true

  BACKUP_PASS=$(get_backup_pass)

  # ── MariaDB my.cnf ──────────────────────────────────────────────────────────
  local innodb_buf="${INNODB_BUFFER_POOL:-1G}"
  local innodb_log="${INNODB_LOG_FILE_SIZE:-256M}"
  local max_conn="${MARIADB_MAX_CONNECTIONS:-100}"

  cat > "$INSTALL_DIR/my.cnf" <<MYCNF
[mysqld]
innodb_buffer_pool_size = ${innodb_buf}
innodb_log_file_size    = ${innodb_log}
max_connections         = ${max_conn}
innodb_flush_log_at_trx_commit = 1
slow_query_log          = 1
slow_query_log_file     = /var/log/mysql/slow.log
long_query_time         = 2
MYCNF

  # ── Dockerfile.caddy ────────────────────────────────────────────────────────
  cat > "$INSTALL_DIR/Dockerfile.caddy" <<'CADDY_DOCKERFILE'
FROM caddy:2.8-builder AS builder
RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit

FROM caddy:2.8-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
CADDY_DOCKERFILE

  log "Building custom Caddy image with caddy-ratelimit plugin..."
  docker build -t actools_caddy:custom -f "$INSTALL_DIR/Dockerfile.caddy" "$INSTALL_DIR" \
    || error "Caddy image build failed. Check Docker build output above."
  log "Custom Caddy image built."

  # ── Dockerfile.worker ───────────────────────────────────────────────────────
  cat > "$INSTALL_DIR/Dockerfile.worker" <<WORKER_DOCKERFILE
FROM drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      texlive-xetex \
      texlive-fonts-recommended \
      texlive-latex-extra \
      poppler-utils \
      ghostscript \
      default-mysql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN xelatex --version
WORKER_DOCKERFILE

  log "Building custom worker image with XeLaTeX toolchain..."
  docker build \
    -t actools_worker:latest \
    -f "$INSTALL_DIR/Dockerfile.worker" \
    --build-arg DRUPAL_VERSION="${DRUPAL_VERSION:-11}" \
    --build-arg PHP_VERSION="${PHP_VERSION:-8.3}" \
    "$INSTALL_DIR" \
    || error "Worker image build failed. Check Docker build output above."
  log "Worker image built -- XeLaTeX self-contained inside container."

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
    image: drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm
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
    image: drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm
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
    image: drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm
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
    if docker compose -f "$INSTALL_DIR/docker-compose.yml" pull db redis php_prod; then
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
# BACKUP DB USER
# =============================================================================
setup_backup_db_user() {
  local backup_pass="$1"
  wait_db
  # [v9.2 fix1] Use mariadb client (mysql removed in MariaDB 11.4)
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" <<SQL
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
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" -e "SELECT 1;" &>/dev/null 2>&1 \
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
    return
  fi

  wait_db

  # [v9.2 fix1] Use mariadb client
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_name}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_name}'@'%';
FLUSH PRIVILEGES;
SQL

  # Resolve Drupal version constraint
  # Supports: 11 (latest 11.x) | 11.3 (latest 11.3.x) | 11.3.5 (exact)
  local DV="${DRUPAL_VERSION:-11}"
  local DRUPAL_CONSTRAINT
  if [[ "$DV" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    DRUPAL_CONSTRAINT="$DV"
    log "Drupal version: exact ${DV}"
  elif [[ "$DV" =~ ^[0-9]+\.[0-9]+$ ]]; then
    DRUPAL_CONSTRAINT="~${DV}"
    log "Drupal version: latest ${DV}.x"
  else
    DRUPAL_CONSTRAINT="^${DV}"
    log "Drupal version: latest ${DV}.x.x"
  fi

  log "Composing Drupal ${DV} for ${env}..."
  docker compose exec -T "$php_svc" bash -c "
    export COMPOSER_PROCESS_TIMEOUT=${COMPOSER_PROCESS_TIMEOUT:-600}
    set -euo pipefail
    mkdir -p /var/www/html/${env}
    cd /var/www/html/${env}

    if ! command -v composer &>/dev/null; then
      curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi

    if [[ ! -f composer.json ]]; then
      composer create-project drupal/recommended-project:${DRUPAL_CONSTRAINT} . --no-interaction
      composer require drush/drush --no-interaction
    fi

    EXTRA='${EXTRA_PACKAGES:-}'
    [[ -n \"\$EXTRA\" ]] && composer require \$EXTRA --no-interaction || true
  "

  if [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]]; then
    log "Installing S3FS module for ${env}..."
    docker compose exec -T "$php_svc" bash -c "
      cd /var/www/html/${env}
      composer require drupal/s3fs --no-interaction
      ./vendor/bin/drush en s3fs --yes 2>/dev/null || true
    " 2>/dev/null || warn "S3FS installation failed -- configure manually after install"
  fi

  docker compose exec -T "$php_svc" bash -c \
    "apt-get update -qq && apt-get install -y -qq default-mysql-client 2>/dev/null || true" \
    2>/dev/null || true

  log "drush site:install for ${env}..."
  docker compose exec -T "$php_svc" bash -c "
    set -euo pipefail
    cd /var/www/html/${env}
    ./vendor/bin/drush site:install standard \
      --db-url=mysql://${db_name}:${db_pass}@db/${db_name} \
      --account-name=${DRUPAL_ADMIN_USER:-admin} \
      --account-pass=${DRUPAL_ADMIN_PASS} \
      --account-mail=${DRUPAL_ADMIN_EMAIL} \
      --site-name='${SITE_NAME:-AcTools}' \
      --yes
    ./vendor/bin/drush cr
  "

  local domain_escaped="${BASE_DOMAIN//./\\.}"
  docker compose exec -T "$php_svc" bash -c "
    CONFIG_FILE=/opt/drupal/web/${env}/web/sites/default/settings.php
    grep -q \"^\$settings\['trusted_host_patterns'\]\" \"\$CONFIG_FILE\" 2>/dev/null || \
    printf "\$settings['trusted_host_patterns'] = array('^${domain_escaped}$', '^.*\\.${domain_escaped}$');\n" >> "$CONFIG_FILE"
  " 2>/dev/null && log "trusted_host_patterns set for ${env}" \
    || warn "trusted_host_patterns injection failed for ${env} -- set manually in settings.php"
  docker compose exec -T "$php_svc" bash -c "
    CONFIG_FILE=/opt/drupal/web/${env}/web/sites/default/settings.php
    grep -q \"^\$settings\['file_private_path'\]\" \"\$CONFIG_FILE\" 2>/dev/null || \
    printf \"\\\$settings['file_private_path'] = '/opt/drupal/web/${env}/private';\\n\" >> \"\$CONFIG_FILE\"
  " 2>/dev/null && log "file_private_path set for ${env}"     || warn "file_private_path injection failed for ${env} -- set manually in settings.php"
  docker compose exec -T "$php_svc" mkdir -p /opt/drupal/web/${env}/private 2>/dev/null || true

  if [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]]; then
    log "Injecting S3 credentials into settings.php for ${env}..."
    docker compose exec -T "$php_svc" bash -c "
      CONFIG_FILE=/opt/drupal/web/${env}/web/sites/default/settings.php
      cat >> \"\$CONFIG_FILE\" <<'SETTINGS'

// S3FS configuration -- injected by actools installer (v9.2).
\$config['s3fs.settings']['access_key']        = getenv('AWS_ACCESS_KEY_ID') ?: '';
\$config['s3fs.settings']['secret_key']        = getenv('AWS_SECRET_ACCESS_KEY') ?: '';
\$config['s3fs.settings']['bucket']            = getenv('S3_BUCKET') ?: '';
\$config['s3fs.settings']['region']            = getenv('AWS_REGION') ?: 'us-east-1';
\$config['s3fs.settings']['use_s3_for_public'] = TRUE;
\$config['s3fs.settings']['use_s3_for_private'] = TRUE;

\$_s3_endpoint = getenv('S3_ENDPOINT_URL');
if (!empty(\$_s3_endpoint)) {
  \$config['s3fs.settings']['use_customhost'] = TRUE;
  \$config['s3fs.settings']['hostname']       = \$_s3_endpoint;
}

\$_cdn_host = getenv('ASSET_CDN_HOST');
if (!empty(\$_cdn_host)) {
  \$config['s3fs.settings']['use_cname'] = TRUE;
  \$config['s3fs.settings']['domain']    = \$_cdn_host;
}
SETTINGS
    " 2>/dev/null || warn "S3 settings.php injection failed for ${env}"
    log "S3 settings.php injection complete for ${env} (provider: ${STORAGE_PROVIDER})"
    [[ -n "${ASSET_CDN_HOST:-}" ]] && log "CDN: ${ASSET_CDN_HOST}"
    [[ -n "${S3_ENDPOINT_URL:-}" ]] && log "Endpoint: ${S3_ENDPOINT_URL}"
  fi

  docker compose exec -T "$php_svc" bash -c "
    if [[ -f /usr/local/etc/php-fpm.d/www.conf ]]; then
      echo 'slowlog = /var/log/php/www-slow.log' >> /usr/local/etc/php-fpm.d/www.conf
      echo 'request_slowlog_timeout = 5s' >> /usr/local/etc/php-fpm.d/www.conf
      kill -USR2 1 2>/dev/null || true
    fi
  " 2>/dev/null || true

  docker compose exec -T "$php_svc" bash -c "
    chown -R www-data:www-data /var/www/html/${env}/web/sites/default/files 2>/dev/null || true
  " 2>/dev/null || true
  chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR/docroot/${env}" 2>/dev/null || true
  if id www-data &>/dev/null; then
    chown -R www-data:www-data "$INSTALL_DIR/docroot/${env}/web/sites/default/files" 2>/dev/null || true
  fi

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
  docker exec actools_db mariadb-dump \
    --single-transaction --quick \
    -ubackup -p"${backup_pass}" "\$DB" \
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
  local backup_pass
  backup_pass=$(get_backup_pass)

  cat > /usr/local/bin/actools <<HELPER
#!/usr/bin/env bash
# Actools CLI v9.2
INSTALL_DIR="${INSTALL_DIR}"
cd "\$INSTALL_DIR" 2>/dev/null || { echo "Actools not found at \$INSTALL_DIR"; exit 1; }

php_svc() { echo "php_\${1:-prod}"; }

case "\${1:-help}" in
  logs)
    shift
    [[ \$# -gt 0 ]] && docker compose logs -f "\$@" || docker compose logs -f
    ;;
  restart)    docker compose restart \${2:-} ;;
  status)     docker compose ps ;;
  stats)      docker stats --no-trunc ;;

  worker-logs)   docker compose logs -f worker_prod ;;
  worker-status) docker compose exec worker_prod bash -c "cd /var/www/html/prod && ./vendor/bin/drush queue:list" ;;
  worker-run)
    echo "Running queue worker manually on prod..."
    docker compose exec worker_prod bash -c "xelatex --version"
    ;;

  pdf-test)
    echo "=== XeLaTeX Test (inside worker container) ==="
    docker compose exec worker_prod xelatex --version 2>/dev/null \
      && echo "XeLaTeX: OK" \
      || echo "XeLaTeX: FAILED -- rebuild: docker build -t actools_worker:latest -f ~/Dockerfile.worker ~/"
    echo ""
    docker inspect actools_worker_prod --format='  Health: {{.State.Health.Status}}' 2>/dev/null || echo "  (container not running)"
    ;;

  storage-test)
    echo "=== S3 Storage Round-Trip Test ==="
    docker compose exec php_prod bash -c "
      cd /var/www/html/prod
      ./vendor/bin/drush php:eval \"
        \\\$test_content = 'actools-storage-test-' . time();
        \\\$uri = 's3://actools-roundtrip-test.txt';
        \\\$written = file_put_contents(\\\$uri, \\\$test_content);
        if (\\\$written === false) { echo 'WRITE FAILED'; exit(1); }
        echo 'WRITE OK (' . \\\$written . ' bytes)';
        \\\$read = file_get_contents(\\\$uri);
        echo \\\$read === \\\$test_content ? 'READ OK' : 'READ FAILED';
        \\\$deleted = unlink(\\\$uri);
        echo \\\$deleted ? 'DELETE OK' : 'DELETE FAILED';
        echo 'Round-trip: ' . (\\\$read === \\\$test_content && \\\$deleted ? 'PASS' : 'FAIL');
      \" 2>/dev/null || echo 'S3 stream test failed'
    " 2>/dev/null || echo "Could not connect to php_prod"
    ;;

  storage-info)
    ENV_FILE="${REAL_HOME}/actools.env"
    [[ -f "\$ENV_FILE" ]] && { set -a; source "\$ENV_FILE"; set +a; }
    STORAGE_PROVIDER="\${STORAGE_PROVIDER:-\${S3_PROVIDER:-aws}}"
    S3_ENDPOINT_URL="\${S3_ENDPOINT_URL:-\${S3_ENDPOINT:-}}"
    ASSET_CDN_HOST="\${ASSET_CDN_HOST:-\${CLOUDFLARE_CDN_DOMAIN:-}}"
    echo "=== S3 Storage Configuration ==="
    echo "Provider  : \${STORAGE_PROVIDER:-not set}"
    echo "Bucket    : \${S3_BUCKET:-not set}"
    case "\${STORAGE_PROVIDER:-aws}" in
      aws)       echo "Region    : \${AWS_REGION:-not set}" ;;
      backblaze|wasabi|custom) echo "Endpoint  : \${S3_ENDPOINT_URL:-not set}" ;;
    esac
    [[ -n "\${ASSET_CDN_HOST:-}" ]] && echo "CDN host  : \${ASSET_CDN_HOST}"
    echo "XeLaTeX mode: \${XELATEX_MODE:-local}"
    ;;

  dry-run)
    echo "=== DRY-RUN: What 'actools update' would do ==="
    echo "1. Pre-update snapshot of actools_prod"
    echo "2. docker compose pull"
    echo "3. docker compose up -d"
    echo "4. drush updb + cr per environment"
    echo "5. caddy reload"
    ;;

  update)
    echo "Taking pre-update prod snapshot..."
    SNAP="\${INSTALL_DIR}/backups/pre_update_prod_\$(date +%F_%H%M%S).sql.gz"
    docker exec actools_db mariadb-dump --single-transaction --quick \
      -ubackup -p"${backup_pass}" actools_prod \
      | gzip > "\$SNAP" && echo "Snapshot: \$SNAP" || echo "Snapshot failed (non-fatal)"
    docker compose pull db redis php_prod
    docker compose up -d
    for env in $(echo "${ENVIRONMENTS}" | tr ',' ' '); do
      svc=\$(php_svc "\$env")
      if docker compose ps "\$svc" | grep -q "Up"; then
        echo "drush updb on \${env}..."
        docker compose exec -T "\$svc" bash -c \
          "cd /var/www/html/\${env} && ./vendor/bin/drush updb --yes && ./vendor/bin/drush cr" \
          2>&1 || echo "drush updb failed for \${env}"
      fi
    done
    docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
    echo "Update complete."
    ;;

  backup)     /etc/cron.daily/actools-backup ;;

  health)
    for env in $(echo "${ENVIRONMENTS}" | tr ',' ' '); do
      dom="\${env}.${BASE_DOMAIN}"
      [[ "\$env" == "prod" ]] && dom="${BASE_DOMAIN}"
      http=\$(curl -sso /dev/null -w "%{http_code}" --max-time 5 "https://\$dom" 2>/dev/null || echo "ERR")
      hlth=\$(curl -sso /dev/null -w "%{http_code}" --max-time 5 "https://\$dom/health" 2>/dev/null || echo "ERR")
      echo "\$dom: HTTP=\$http  /health=\$hlth"
    done
    ;;

  drush)
    env="\${2:-prod}"
    svc=\$(php_svc "\$env")
    shift 2 2>/dev/null || shift 1 2>/dev/null || true
    docker compose exec "\$svc" bash -c "cd /var/www/html/\${env} && ./vendor/bin/drush \$*"
    ;;
  console)
    env="\${2:-prod}"
    svc=\$(php_svc "\$env")
    docker compose exec "\$svc" bash -c "cd /var/www/html/\${env} && ./vendor/bin/drush php:cli"
    ;;
  shell)      docker compose exec "\${2:-php_prod}" bash ;;

  restore-test)
    LATEST=\$(ls -t "${INSTALL_DIR}/backups"/prod_db_*.sql.gz 2>/dev/null | head -1)
    [[ -z "\$LATEST" ]] && { echo "No prod DB backups found"; exit 1; }
    echo "Testing DB restore: \$LATEST"
    sha256sum -c "\$LATEST.sha256" && echo "Checksum OK" || { echo "CHECKSUM FAILED"; exit 1; }
    docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e \
      "CREATE DATABASE IF NOT EXISTS actools_restore_test CHARACTER SET utf8mb4;"
    gunzip -c "\$LATEST" | docker exec -i actools_db mariadb -uroot -p"${DB_ROOT_PASS}" actools_restore_test
    TC=\$(docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -sN -e \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema='actools_restore_test';")
    docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS actools_restore_test;"
    echo "DB restore test OK -- \${TC} tables restored."
    if [[ "${ENABLE_S3_STORAGE:-true}" == "true" ]]; then
      echo "Running S3 reachability check..."
      actools storage-test
    fi
    ;;

  restore)
    env="\${2:-prod}"
    db="actools_\${env}"
    BACKUP_FILE="\${3:-}"
    [[ -z "\$BACKUP_FILE" ]] && \
      BACKUP_FILE=\$(ls -t "${INSTALL_DIR}/backups"/\${env}_db_*.sql.gz 2>/dev/null | head -1)
    [[ -z "\$BACKUP_FILE" ]] && { echo "No backups found for \$env"; exit 1; }
    echo "Restoring \$env from: \$BACKUP_FILE"
    sha256sum -c "\$BACKUP_FILE.sha256" 2>/dev/null && echo "Checksum OK" || echo "WARNING: no checksum file"
    read -rp "OVERWRITE actools_\${env}? [y/N] " reply
    [[ "\$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    docker exec actools_db mariadb -uroot -p"${DB_ROOT_PASS}" -e \
      "DROP DATABASE IF EXISTS \`\$db\`; CREATE DATABASE \`\$db\` CHARACTER SET utf8mb4;"
    gunzip -c "\$BACKUP_FILE" | docker exec -i actools_db mariadb -uroot -p"${DB_ROOT_PASS}" "\$db"
    echo "Restore complete. Run: actools drush \$env cr"
    ;;

  caddy-reload)
    docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile
    ;;

  tls-status)
    echo "=== TLS Certificate Status ==="
    for domain in "${BASE_DOMAIN}" "stg.${BASE_DOMAIN}" "dev.${BASE_DOMAIN}"; do
      echo -n "\$domain: "
      echo | openssl s_client -connect "\$domain:443" -servername "\$domain" 2>/dev/null \
        | openssl x509 -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2 \
        || echo "not available yet"
    done
    ;;

  slow-log)
    env="\${2:-prod}"
    svc=\$(php_svc "\$env")
    echo "=== PHP-FPM slow log for \$env ==="
    docker compose exec "\$svc" tail -50 /var/log/php/www-slow.log 2>/dev/null \
      || echo "No slow log yet"
    ;;

  redis-info) docker compose exec redis redis-cli info memory 2>/dev/null || echo "Redis not running" ;;
  oom)
    echo "=== Recent OOM Events ==="
    dmesg | grep -i "oom\|out of memory\|killed process" | tail -20 || echo "No OOM events"
    ;;

  migrate)
    echo "=== XeLaTeX Migration Guide ==="
    echo "Current mode: ${XELATEX_MODE:-local}"
    echo ""
    echo "1. Deploy XeLaTeX HTTP service on target server"
    echo "2. Set XELATEX_MODE=remote and XELATEX_ENDPOINT=http://<host>:8081 in actools.env"
    echo "3. Update PdfService.php to use HTTP when XELATEX_MODE=remote"
    echo "4. Rebuild worker image without texlive packages"
    echo "5. Verify: actools pdf-test"
    ;;

  log-dir)
    echo "=== Install Log Directory ==="
    LOG_DIR="${INSTALL_DIR}/logs/install"
    echo "Location: \$LOG_DIR"
    ls -lht "\$LOG_DIR" 2>/dev/null | head -20 || echo "No install logs found."
    echo "Main log: ${INSTALL_DIR}/actools-install.log"
    LATEST=\$(ls -t "\$LOG_DIR"/*.log 2>/dev/null | head -1)
    [[ -n "\$LATEST" ]] && echo "Latest run: tail -f \$LATEST" || true
    ;;


  audit)
    AUDIT_SCRIPT="\${INSTALL_DIR}/modules/audit/audit.sh"
    [[ ! -f "\$AUDIT_SCRIPT" ]] && { echo "audit module not found at \$AUDIT_SCRIPT"; exit 1; }
    export ACTOOLS_HOME="\${INSTALL_DIR}"
    source "\${INSTALL_DIR}/modules/audit/lib/output.sh" 2>/dev/null || true
    cd "\${INSTALL_DIR}"
    set -a; source "\${INSTALL_DIR}/actools.env" 2>/dev/null || true; set +a
    bash "\$AUDIT_SCRIPT" "\${@:2}"
    ;;

  help|*)
    echo "Usage: actools <command> [args]"
    echo ""
    echo "  logs [svc]          Stream logs"
    echo "  restart [svc]       Restart a service"
    echo "  status              Container health"
    echo "  stats               Live Docker resource usage"
    echo "  dry-run             Show what update would do"
    echo "  update              Pre-snapshot + pull + drush updb + caddy reload"
    echo "  backup              Run backup now"
    echo "  restore-test        Verify latest prod backup"
    echo "  restore <env> [f]   Restore with confirmation"
    echo "  health              HTTP + /health status"
    echo "  tls-status          TLS cert expiry"
    echo "  drush <env> <cmd>   Run drush"
    echo "  console <env>       Drush PHP console"
    echo "  shell [svc]         Bash in container"
    echo "  worker-logs         Worker container logs"
    echo "  worker-status       Drupal queue status"
    echo "  worker-run          Run queue worker manually"
    echo "  pdf-test            Test XeLaTeX in worker"
    echo "  storage-test        S3 round-trip test"
    echo "  storage-info        Storage + XeLaTeX config"
    echo "  migrate             XeLaTeX remote migration guide"
    echo "  caddy-reload        Zero-downtime Caddy reload"
    echo "  slow-log [env]      PHP-FPM slow request log"
    echo "  redis-info          Redis memory usage"
    echo "  oom                 Recent OOM events"
    echo "  log-dir             Install log directory"
    echo "  audit               Drupal health audit + scoring"
    ;;
esac
HELPER
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
      read -rp "  Proceed? [y/N] " reply; echo
      [[ "$reply" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }

      setup_stack

      IFS=',' read -ra ENVS <<< "$ENVIRONMENTS"

      TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
      if [[ "${PARALLEL_INSTALL:-false}" == "true" ]] && (( TOTAL_RAM < 6000 )); then
        warn "Only ${TOTAL_RAM}MB RAM -- forcing sequential install."
        PARALLEL_INSTALL=false
      fi

      if [[ "${PARALLEL_INSTALL:-false}" == "true" ]]; then
        log "Parallel install (${TOTAL_RAM}MB RAM)..."
        for env in "${ENVS[@]}"; do install_env "${env// /}" & done
        wait
        log "All environments installed."
      else
        for env in "${ENVS[@]}"; do install_env "${env// /}"; done
      fi

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
      docker exec actools_db mariadb-dump --single-transaction --quick \
        -ubackup -p"${BACKUP_PASS}" actools_prod \
        | gzip > "$SNAP" && log "Snapshot: $SNAP" || warn "Snapshot failed (non-fatal)"
      docker compose pull db redis php_prod
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
      error "Unknown mode: $MODE. Use: fresh | update | env <dev|stg|prod> | dry-run"
      ;;
  esac

  echo "${DRUPAL_ADMIN_PASS}" > "$REAL_HOME/.actools-admin-pass"
  chmod 600 "$REAL_HOME/.actools-admin-pass"
  chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.actools-admin-pass" 2>/dev/null || true

  send_webhook

  section "Installation Complete"
  echo
  echo -e "${G}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${G}║       Actools v14.0 -- Drupal 11 + XeLaTeX in Container  ║${NC}"
  echo -e "${G}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${G}║${NC}  Production : ${C}https://${BASE_DOMAIN}${NC}"
  [[ "$ENVIRONMENT_MODE" == "all-in-one" ]] && {
    echo -e "${G}║${NC}  Staging    : ${C}https://stg.${BASE_DOMAIN}${NC}"
    echo -e "${G}║${NC}  Dev        : ${C}https://dev.${BASE_DOMAIN}${NC}"
  }
  echo -e "${G}║${NC}  Admin user : ${C}${DRUPAL_ADMIN_USER:-admin}${NC}"
  echo -e "${G}║${NC}  Admin pass : ${Y}${DRUPAL_ADMIN_PASS}${NC}   <-- SAVE THIS"
  echo -e "${G}║${NC}  Worker RAM : ${C}${WORKER_MEMORY_LIMIT:-2g}${NC} (XeLaTeX inside actools_worker:latest)"
  echo -e "${G}║${NC}  Storage    : ${C}${STORAGE_PROVIDER}${NC} bucket=${S3_BUCKET:-local}"
  echo -e "${G}║${NC}  XeLaTeX    : ${C}${XELATEX_MODE:-local}${NC}"
  echo -e "${G}║${NC}  DB creds   : ${C}${REAL_HOME}/.actools-db-creds${NC}"
  echo -e "${G}║${NC}  Log        : ${C}${LOG_FILE}${NC}"
  echo -e "${G}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${G}║${NC}  actools status          actools worker-status"
  echo -e "${G}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${G}║${NC}  ${Y}If actools command not found, run:${NC}"
  echo -e "${G}║${NC}    ${C}source ~/.bashrc${NC}  (or reconnect SSH)"
  echo -e "${G}║${NC}  actools pdf-test        actools storage-test"
  echo -e "${G}║${NC}  actools storage-info    actools health"
  echo -e "${G}║${NC}  actools slow-log prod   actools redis-info"
  echo -e "${G}║${NC}  actools drush prod cr   actools backup"
  echo -e "${G}╚══════════════════════════════════════════════════════════╝${NC}"
  echo
}

main "$@"
