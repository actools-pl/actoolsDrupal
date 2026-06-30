#!/usr/bin/env bats
# =============================================================================
# live_module_file_inventory_test.bats — FILE-LEVEL wiring guard (Phase C4)
#
# The dir-level guard (orphan_inventory_guard_test.bats) proves WHICH module dirs
# are live. This guard proves, WITHIN the 6 live dirs, which files are reached on
# the live path vs which ship unwired — so an unwired file cannot (a) ship
# unflagged (every file must be classified in the manifest below) or (b) silently
# flip wiring (an unwired draft cannot enter the live source-closure without
# failing CI).
#
# C4 changes NO module file; disposition of the unwired files is deferred —
# backup/* -> E2/E3; audit/deploy-audit.sh, drupal/{prepare,secure}.sh -> Phase 5.
#
# Update this manifest when a file is added to / removed from a live module, or
# when a file's wiring changes. Non-vacuity demos are recorded in HANDOFF-C4.
# =============================================================================

load live_closure   # build_live_closure + CLOSURE (reused byte-unmodified from C1)

REPO=""
setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# --- the classified manifest (the 34 files of the 6 live modules) ---
# WIRED: reached on the live path (source-closure of actools.sh, OR executed /
# sourced via the cli/actools `audit` command).
EXPECTED_WIRED_FILES=(
  modules/audit/audit.sh
  modules/audit/lib/output.sh
  modules/audit/lib/drupal.sh
  modules/audit/lib/integration.sh
  modules/audit/lib/stack.sh
  modules/audit/lib/security.sh
  modules/audit/lib/report.sh
  modules/backup/cron.sh
  modules/db/core.sh
  modules/drupal/provision.sh
  modules/host/age.sh
  modules/host/docker.sh
  modules/host/firewall.sh
  modules/host/kernel.sh
  modules/host/logrotate.sh
  modules/host/packages.sh
  modules/host/swap.sh
  modules/stack/caddyfile.sh
  modules/stack/compose.sh
  modules/stack/images.sh
  modules/stack/mycnf.sh
)
# DOC: ships as module documentation, executed by no code.
EXPECTED_DOC_FILES=(
  modules/audit/docs/fix_catalog.md
)
# UNWIRED: ship on the box (in-place install) but OFF the live path. Disposition
# deferred — see header. These MUST stay off the live source-closure (test 2).
EXPECTED_UNWIRED_FILES=(
  modules/backup/binlog-rotate.sh
  modules/backup/db-full-backup.sh
  modules/backup/pitr-restore.sh
  modules/backup/cli-pitr.sh
  modules/backup/deploy-pitr.sh
  modules/backup/mariadb-binlog.cnf
  modules/backup/99-binlog.cnf
  modules/backup/docker-compose.binlog.yml
  modules/backup/actools-db-backup.cron
  modules/audit/deploy-audit.sh
  modules/drupal/prepare.sh
  modules/drupal/secure.sh
)

@test "every file in the 6 live modules is classified (no surprise file ships)" {
  local expected actual
  expected="$(printf '%s\n' "${EXPECTED_WIRED_FILES[@]}" "${EXPECTED_DOC_FILES[@]}" "${EXPECTED_UNWIRED_FILES[@]}" | sort -u)"
  actual="$(cd "$REPO" && find modules -type f | sort -u)"
  if [[ "$expected" != "$actual" ]]; then
    echo "Live-module file set drifted from the C4 manifest."
    echo "A file was added/removed/renamed in a live module without updating this"
    echo "guard. Classify it (wired / doc / unwired) and update the inventory in"
    echo "runtime-authority-map.md. diff (expected vs actual):"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    return 1
  fi
}

@test "no unwired live-module file is reached by the live install closure" {
  build_live_closure "$REPO"
  local breach="" f
  for f in "${EXPECTED_UNWIRED_FILES[@]}"; do
    if printf '%s\n' "${CLOSURE[@]}" | grep -qxF "$f"; then
      breach="$breach $f"
    fi
  done
  if [[ -n "$breach" ]]; then
    echo "An UNWIRED live-module file is now on the live source-closure:"
    printf '  %s\n' $breach
    echo "If it was wired intentionally, move it from EXPECTED_UNWIRED_FILES to"
    echo "EXPECTED_WIRED_FILES and update the runtime-authority-map inventory."
    return 1
  fi
}
