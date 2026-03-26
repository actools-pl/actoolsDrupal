#!/usr/bin/env bash
# =============================================================================
# core/bootstrap.sh — Actools Engine: Variable Init, Logging, Lock File
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

export ACTOOLS_VERSION="9.2"
MODE="${1:-fresh}"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"

export ENV_FILE="$REAL_HOME/actools.env"
export STATE_FILE="$REAL_HOME/.actools-state.json"
LOCK_FILE="/tmp/actools.lock"
LOG_FILE="$REAL_HOME/actools-install.log"
LOG_DIR="$REAL_HOME/logs/install"
export INSTALL_DIR="$REAL_HOME"
export PKG_DONE_FLAG="/var/lib/actools/.packages_done"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

# Logging
log()     { echo -e "${G}[INFO ]${NC} $(date '+%F %T') $*"; }
warn()    { echo -e "${Y}[WARN ]${NC} $(date '+%F %T') $*"; }
error()   { echo -e "${R}[ERROR]${NC} $(date '+%F %T') $*"; exit 1; }
section() {
  echo -e "\n${C}══════════════════════════════════════════════════${NC}"
  echo -e "${C}  $*${NC}"
  echo -e "${C}══════════════════════════════════════════════════${NC}"
}

# Per-run log setup
mkdir -p "$LOG_DIR" 2>/dev/null || true
RUN_LOG="$LOG_DIR/actools-$(date +%F_%H%M%S).log"
exec > >(tee -a "$LOG_FILE" | tee -a "$RUN_LOG") 2>&1

# Dry-run mode
DRY_RUN=false
[[ "$MODE" == "dry-run" ]] && DRY_RUN=true
dryrun() { "$DRY_RUN" && { echo -e "${Y}[DRY-RUN]${NC} Would run: $*"; return 0; } || "$@"; }

# Lock file — prevents concurrent installs
touch "$LOCK_FILE" 2>/dev/null || true
exec 200>"$LOCK_FILE"
flock -n 200 || error "Another actools installation is already running."
