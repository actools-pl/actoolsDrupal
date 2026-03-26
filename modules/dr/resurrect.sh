#!/usr/bin/env bash
# /home/actools/modules/dr/resurrect.sh
# Phase 4.5 — Resurrect server from DNA snapshot
# Run this on a FRESH server to restore Actools in < 15 minutes
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/actools-pl/actoolsDrupal/main/modules/dr/resurrect.sh | bash
#   OR: ./resurrect.sh --dna /path/to/dna.json.age --key /path/to/age-key.txt

set -euo pipefail

DNA_FILE=""
AGE_KEY=""
SKIP_DB=false
DRY_RUN=false
START_TIME=$(date +%s)

usage() {
  cat << EOF
Usage: $0 --dna <dna-file.json.age> --key <age-key.txt> [--skip-db] [--dry-run]

  --dna       Path to encrypted DNA snapshot (required)
  --key       Path to age private key (required)
  --skip-db   Skip database restore (stack only)
  --dry-run   Show steps without executing
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dna)     DNA_FILE="$2"; shift 2 ;;
    --key)     AGE_KEY="$2"; shift 2 ;;
    --skip-db) SKIP_DB=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) usage ;;
  esac
done

[[ -z "${DNA_FILE}" || -z "${AGE_KEY}" ]] && usage

log()  { echo "$(date -u +%FT%TZ) [resurrect] $*"; }
step() { echo ""; echo "══ Step $1: $2 ══════════════════════════════"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

if [[ "${DRY_RUN}" == "true" ]]; then
  log "DRY RUN — no changes will be made"
fi

# ── Decrypt DNA ───────────────────────────────────────────────────────────────
step 1 "Decrypt DNA snapshot"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

DNA_JSON="${WORK_DIR}/dna.json"
age --decrypt -i "${AGE_KEY}" -o "${DNA_JSON}" "${DNA_FILE}"
ok "DNA decrypted"

ACTOOLS_VERSION=$(python3 -c "import json; d=json.load(open('${DNA_JSON}')); print(d.get('actools_version','unknown'))")
CREATED=$(python3 -c "import json; d=json.load(open('${DNA_JSON}')); print(d.get('created','unknown'))")
log "Snapshot: ${ACTOOLS_VERSION} created ${CREATED}"

# ── Install dependencies ──────────────────────────────────────────────────────
step 2 "Install system dependencies"
if [[ "${DRY_RUN}" == "false" ]]; then
  apt-get update -qq
  apt-get install -y -qq git curl age python3 2>/dev/null
  ok "System packages installed"

  # Install Docker if not present
  if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    ok "Docker installed"
  else
    ok "Docker already installed: $(docker --version)"
  fi
fi

# ── Create actools user ────────────────────────────────────────────────────────
step 3 "Create actools user"
if [[ "${DRY_RUN}" == "false" ]]; then
  if ! id actools &>/dev/null; then
    useradd -m -s /bin/bash actools
    usermod -aG docker actools
    ok "actools user created"
  else
    ok "actools user already exists"
  fi
fi

# ── Clone repository ──────────────────────────────────────────────────────────
step 4 "Clone Actools repository"
REPO="https://github.com/actools-pl/actoolsDrupal"
if [[ "${DRY_RUN}" == "false" ]]; then
  if [[ ! -d /home/actools/.git ]]; then
    git clone "${REPO}" /home/actools
    chown -R actools:actools /home/actools
    ok "Repository cloned"
  else
    ok "Repository already present"
  fi
fi

# ── Restore env and keys ──────────────────────────────────────────────────────
step 5 "Restore secrets"
warn "ACTION REQUIRED — copy these files manually from secure storage:"
echo "    /home/actools/actools.env     (environment variables)"
echo "    /home/actools/.age-key.txt    (age private key)"
echo "    /home/actools/.age-public-key (age public key)"
echo "    /home/actools/certs/          (MariaDB SSL certificates)"
echo ""
if [[ "${DRY_RUN}" == "false" ]]; then
  read -r -p "  Press ENTER once secrets are in place..."
  [[ -f /home/actools/actools.env ]] || { echo "ERROR: actools.env missing"; exit 1; }
  ok "Secrets verified"
fi

# ── Start the stack ───────────────────────────────────────────────────────────
step 6 "Start Docker stack"
if [[ "${DRY_RUN}" == "false" ]]; then
  cd /home/actools
  sudo -u actools docker compose up -d
  log "Waiting 30s for stack to initialise..."
  sleep 30
  ok "Stack started"
fi

# ── Restore database ──────────────────────────────────────────────────────────
step 7 "Restore database"
if [[ "${SKIP_DB}" == "true" ]]; then
  warn "Database restore skipped (--skip-db)"
else
  LATEST_DUMP=$(python3 -c "
import json
d = json.load(open('${DNA_JSON}'))
print(d.get('modules', {}).get('backup', {}).get('latest_dump', ''))
")
  if [[ -n "${LATEST_DUMP}" ]]; then
    log "Latest dump from DNA: ${LATEST_DUMP}"
    warn "ACTION REQUIRED — restore the database:"
    echo "    actools migrate --point-in-time \"$(date '+%Y-%m-%d %H:%M:%S')\""
    echo "    OR restore specific dump:"
    echo "    age --decrypt -i /home/actools/.age-key.txt ${LATEST_DUMP} | zcat | mariadb -uroot -p\$DB_ROOT_PASS"
  else
    warn "No dump path in DNA snapshot — restore manually"
  fi
fi

# ── Install CLI ───────────────────────────────────────────────────────────────
step 8 "Install actools CLI"
if [[ "${DRY_RUN}" == "false" ]]; then
  cp /home/actools/cli/actools /usr/local/bin/actools-real
  cp /home/actools/modules/security/actools-audit /usr/local/bin/actools-audit
  chmod +x /usr/local/bin/actools-real /usr/local/bin/actools-audit
  ln -sf /usr/local/bin/actools-audit /usr/local/bin/actools
  ok "CLI installed"
fi

# ── Install cron ─────────────────────────────────────────────────────────────
step 9 "Install cron jobs"
if [[ "${DRY_RUN}" == "false" ]]; then
  cp /home/actools/modules/backup/actools-db-backup.cron /etc/cron.d/actools-db-backup
  chmod 644 /etc/cron.d/actools-db-backup
  ok "Cron installed"
fi

# ── Install sudoers ───────────────────────────────────────────────────────────
step 10 "Install RBAC sudoers"
if [[ "${DRY_RUN}" == "false" ]]; then
  cp /home/actools/modules/security/sudoers-roles /etc/sudoers.d/actools-roles
  chmod 440 /etc/sudoers.d/actools-roles
  visudo -c -f /etc/sudoers.d/actools-roles
  ok "Sudoers installed"
fi

# ── Health check ─────────────────────────────────────────────────────────────
step 11 "Final health check"
if [[ "${DRY_RUN}" == "false" ]]; then
  sleep 10
  actools health 2>/dev/null && ok "Health check passed" || warn "Health check failed — check logs"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS=$(( ELAPSED % 60 ))

echo ""
echo "══════════════════════════════════════════════════"
echo " Resurrection complete in ${MINUTES}m ${SECONDS}s"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. actools health --verbose"
echo "  2. curl https://feesix.com/health"
echo "  3. Update DNS if IP changed"
