#!/usr/bin/env bats
# =============================================================================
# tests/guards/backup_format_contract_guard_test.bats — E1 guard
# (backup-format contract: the live producer<->consumer agreement)
#
# Pins the LIVE (A) backup-artifact contract AND the now-live encrypted (B) contract:
# the daily cron generator (modules/backup/cron.sh -> /etc/cron.daily/actools-backup)
# and the `restore` consumer (cli/actools) must name the SAME artifact. The A agreement
# is four-fold — same root (${INSTALL_DIR}/backups, anchored to the closing quote so a
# 'backups'-prefixed sibling is rejected), same filename stem (_db_), same extension
# (.sql.gz), same checksum-sidecar convention (<artifact>.sha256) — plus the
# integrity-or-delete sidecar the producer writes. The B agreement (E2): with
# ENABLE_ENCRYPTED_BACKUP=true the producer encrypts each artifact to <artifact>.age,
# checksums the CIPHERTEXT (<artifact>.age.sha256), and removes the plaintext; the
# consumer selects *.sql.gz.age and decrypts with the private key before load. See
# docs/backup-format-contract.md for the canonical scheme and the divergence ledger.
#
# This guard pins the live (A) and encrypted (B) agreements. It deliberately asserts
# NOTHING about the PITR (C, db-full-backup.sh / pitr-restore.sh) drafts — those are
# not wired (TARGET / NOT YET LIVE); E3 extends this guard when it wires PITR. (The
# standalone encrypted_backup.sh draft was absorbed into cron.sh and removed in E2.)
#
# Discipline mirrors tests/guards/cron_security_shape_guard_test.bats:
#   - the live patterns are DERIVED from the code, not transcribed into the guard;
#   - the producer is read through the SAME render helper the installer's golden
#     uses (tests/helpers/capture_backup_cron.sh), so the guard checks the bytes the
#     installer would write to /etc/cron.daily/actools-backup;
#   - a single agreement oracle (_assert_agreement) is used by the positive arm AND
#     by the agreement non-vacuity arms (which expect it to FAIL on a doctored copy);
#   - non-vacuity is permanent and runs on OFF-TREE scratch copies — the repo is
#     never modified.
#
# dash/bats-safe: no process substitution; the render helper writes to a file; all
# scratch copies live under a mktemp dir torn down in teardown().
#
# CI wiring: discovered by the recursive bats job (lint.yml: `bats -r tests/`).
# =============================================================================

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CRON_HELPER="${REPO}/tests/helpers/capture_backup_cron.sh"
  CLI="${REPO}/cli/actools"
  RENDER_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "${RENDER_TMP:-}"
}

# ---------------------------------------------------------------------------
# locate_generator — the file that LIVE-defines setup_backup_cron(), found the
# same way the render helper finds it (module after extraction, inline before).
# ---------------------------------------------------------------------------
_locate_generator() {
  if [[ -f "${REPO}/modules/backup/cron.sh" ]] \
     && grep -qE '^setup_backup_cron\(\)' "${REPO}/modules/backup/cron.sh"; then
    echo "${REPO}/modules/backup/cron.sh"
  else
    echo "${REPO}/actools.sh"
  fi
}

# ---------------------------------------------------------------------------
# _producer_db_signature <rendered-cron-file>
# Derive the DB-artifact signature the PRODUCER writes, normalized to
# <stem>*<ext> by collapsing the runtime timestamp placeholder to `*`. The live
# generator builds it as:  DUMPFILE="${BACKUP_DIR}/${env}_db_${TIMESTAMP}.sql.gz"
# -> signature `_db_*.sql.gz`. Prints the signature; rc 1 (empty) if not found.
# ---------------------------------------------------------------------------
_producer_db_signature() {
  local rendered="$1" line sig
  [[ -f "$rendered" ]] || { echo "producer: rendered cron missing: $rendered" >&2; return 1; }
  line="$(grep -E 'DUMPFILE=.*\$\{env\}.*\.sql\.gz' "$rendered" | head -1)"
  [[ -n "$line" ]] || { echo "producer: no DB dump (DUMPFILE … .sql.gz) builder found" >&2; return 1; }
  sig="$(printf '%s\n' "$line" | sed -e 's/.*\${env}//' -e 's/".*$//' -e 's/\${TIMESTAMP}/*/g')"
  [[ -n "$sig" ]] || { echo "producer: could not normalize DB signature from: $line" >&2; return 1; }
  printf '%s\n' "$sig"
}

# ---------------------------------------------------------------------------
# _consumer_db_signature <cli-file>
# Derive the default-backup signature the CONSUMER (the `restore` arm) globs for,
# normalized the same way. The restore arm selects:
#   ls -t "${INSTALL_DIR}/backups"/"${env}"_db_*.sql.gz | head -1
# -> signature `_db_*.sql.gz`. Scoped to the restore) arm only (the restore-test)
# arm's prod_db_*.sql.gz glob is a different consumer and is not the contract pin).
# Prints the signature; rc 1 (empty) if not found.
# ---------------------------------------------------------------------------
_consumer_db_signature() {
  local cli="$1" arm line sig
  [[ -f "$cli" ]] || { echo "consumer: cli file missing: $cli" >&2; return 1; }
  arm="$(awk '/^[[:space:]]*restore\)/{f=1} f{print} f&&/;;/{exit}' "$cli")"
  [[ -n "$arm" ]] || { echo "consumer: restore) arm not found in $cli" >&2; return 1; }
  line="$(printf '%s\n' "$arm" | grep -E 'ls -t .*backups.*\.sql\.gz' | head -1)"
  [[ -n "$line" ]] || { echo "consumer: default-backup glob not found in restore) arm" >&2; return 1; }
  sig="$(printf '%s\n' "$line" | sed -e 's/.*"\${env}"//' -e 's/\.sql\.gz.*/.sql.gz/')"
  [[ -n "$sig" ]] || { echo "consumer: could not normalize glob signature from: $line" >&2; return 1; }
  printf '%s\n' "$sig"
}

# ---------------------------------------------------------------------------
# _assert_agreement <rendered-cron-file> <cli-file>
# The single contract oracle every arm uses (including the two non-vacuity arms,
# which expect it to FAIL on a doctored copy). The producer and consumer must name
# the SAME artifact: identical normalized DB signature, AND both rooted at the
# ${INSTALL_DIR}/backups tree. Echoes a "CONTRACT DRIFT" diagnosis on failure.
# ---------------------------------------------------------------------------
_assert_agreement() {
  local rendered="$1" cli="$2" psig csig

  psig="$(_producer_db_signature "$rendered")" || {
    echo "CONTRACT DRIFT: cannot derive producer DB signature."; return 1; }
  csig="$(_consumer_db_signature "$cli")" || {
    echo "CONTRACT DRIFT: cannot derive consumer (restore) DB signature."; return 1; }

  # Core invariant: producer stem+extension == consumer stem+extension.
  if [[ "$psig" != "$csig" ]]; then
    echo "CONTRACT DRIFT: producer writes '${psig}' but the restore consumer globs '${csig}'."
    echo "The producer and consumer no longer name the same artifact."
    return 1
  fi

  # Both sides must be rooted under ${INSTALL_DIR}/backups.
  grep -qE '^BACKUP_DIR="[^"]*/backups"$' "$rendered" || {
    echo "CONTRACT DRIFT: producer BACKUP_DIR is not rooted at .../backups."
    return 1
  }
  local cline
  cline="$(awk '/^[[:space:]]*restore\)/{f=1} f{print} f&&/;;/{exit}' "$cli" \
            | grep -E 'ls -t .*backups.*\.sql\.gz' | head -1)"
  printf '%s\n' "$cline" | grep -qF '${INSTALL_DIR}/backups"' || {
    echo "CONTRACT DRIFT: restore consumer glob is not rooted at \${INSTALL_DIR}/backups."
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 1 — Producer DB pattern.
# The rendered live cron writes DB dumps as <env>_db_<…>.sql.gz under a …/backups path.
# ---------------------------------------------------------------------------
@test "producer: live cron writes <env>_db_<…>.sql.gz under backups/" {
  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  # The DB-artifact builder carries the _db_ stem with the .sql.gz extension …
  local psig
  psig="$(_producer_db_signature "${RENDER_TMP}/live-cron")"
  [ "$psig" = "_db_*.sql.gz" ] || { echo "producer signature was '${psig}', expected '_db_*.sql.gz'"; return 1; }

  # … under a backups/ root.
  grep -qE '^BACKUP_DIR="[^"]*/backups"$' "${RENDER_TMP}/live-cron"
}

# ---------------------------------------------------------------------------
# Arm 2 — Producer integrity sidecar (integrity-or-delete invariant).
# The rendered cron writes <dump>.sha256 and verifies it with `sha256sum -c`.
# ---------------------------------------------------------------------------
@test "producer: live cron writes a <dump>.sha256 sidecar and runs sha256sum -c" {
  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  # Sidecar write on the DB dump.
  grep -qF '$DUMPFILE.sha256' "${RENDER_TMP}/live-cron" || {
    echo "producer: no '\$DUMPFILE.sha256' sidecar write found in the rendered cron."
    return 1
  }
  # Integrity verification.
  grep -qE 'sha256sum -c' "${RENDER_TMP}/live-cron" || {
    echo "producer: no 'sha256sum -c' integrity check found in the rendered cron."
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 3 — Consumer<->producer agreement (the core contract invariant).
# Live render + the real restore arm: same stem, same extension, same backups root.
# ---------------------------------------------------------------------------
@test "agreement: the restore consumer globs the same artifact the producer writes" {
  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  run _assert_agreement "${RENDER_TMP}/live-cron" "$CLI"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# ---------------------------------------------------------------------------
# Arm 4 — Consumer checksum convention.
# The restore arm reads the producer's <file>.sha256 sidecar (sha256sum -c).
# ---------------------------------------------------------------------------
@test "agreement: the restore consumer reads the producer's <file>.sha256 sidecar" {
  local arm
  arm="$(awk '/^[[:space:]]*restore\)/{f=1} f{print} f&&/;;/{exit}' "$CLI")"
  [ -n "$arm" ] || { echo "restore) arm not found"; return 1; }
  printf '%s\n' "$arm" | grep -qF 'sha256sum -c "$BACKUP_FILE.sha256"' || {
    echo "consumer: restore arm does not verify the '<file>.sha256' sidecar with sha256sum -c."
    echo "--- restore arm ---"; printf '%s\n' "$arm"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 5 — Non-vacuity #1: PRODUCER drift.
# Doctor an OFF-TREE copy of the live generator so it emits a different stem
# (_db_ -> _database_), render it through the SAME helper, and the agreement
# oracle MUST FAIL. The repo is never touched.
# ---------------------------------------------------------------------------
@test "non-vacuous: a producer whose stem drifts (_db_ -> _database_) FAILS agreement" {
  local gen doctored
  gen="$(_locate_generator)"
  doctored="${RENDER_TMP}/doctored-generator.sh"

  cp "$gen" "$doctored"
  # Surgical: only the ${env}_db_ artifact stem (unique to the DUMPFILE builder).
  sed -i 's/\${env}_db_/\${env}_database_/' "$doctored"

  # Sanity (else this arm is vacuous): the doctored generator must now render a
  # DRIFTED producer signature, not the live one.
  run bash "$CRON_HELPER" render-from "$doctored" "${RENDER_TMP}/drifted-cron"
  [ "$status" -eq 0 ] || { echo "doctored render failed: $output"; return 1; }
  local dpsig
  dpsig="$(_producer_db_signature "${RENDER_TMP}/drifted-cron")"
  [ "$dpsig" = "_database_*.sql.gz" ] || {
    echo "VACUOUS: doctored producer signature was '${dpsig}', expected '_database_*.sql.gz' — the doctor did not bite."
    return 1
  }

  # The oracle MUST reject the drifted producer against the real consumer.
  run _assert_agreement "${RENDER_TMP}/drifted-cron" "$CLI"
  [ "$status" -ne 0 ] || {
    echo "VACUOUS GUARD: a producer with a drifted stem PASSED the agreement check."
    return 1
  }
  [[ "$output" == *"CONTRACT DRIFT"* ]] || {
    echo "agreement failed for an unexpected reason (not the producer-drift arm):"
    echo "$output"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 6 — Non-vacuity #2: CONSUMER drift.
# Doctor an OFF-TREE copy of cli/actools so the restore glob no longer matches the
# producer (_db_ -> _database_ in the restore arm only), and the agreement oracle
# MUST FAIL against the live producer. The repo is never touched.
# ---------------------------------------------------------------------------
@test "non-vacuous: a restore glob that drifts (_db_ -> _database_) FAILS agreement" {
  local doctored_cli
  doctored_cli="${RENDER_TMP}/doctored-cli"
  cp "$CLI" "$doctored_cli"
  # Surgical: only the restore arm's "${env}"_db_ globs; the restore-test arm's
  # prod_db_*.sql.gz glob (no "${env}" prefix) is intentionally left untouched. The
  # sed is GLOBAL because the restore arm now carries two "${env}"_db_ globs (the
  # plaintext .sql.gz and the encrypted .sql.gz.age selection); a non-global sed would
  # leave the .age glob undoctored and make the consumer signature read as live (vacuous).
  sed -i 's/"\${env}"_db_/"\${env}"_database_/g' "$doctored_cli"

  # Sanity (else this arm is vacuous): the doctored consumer must now derive a
  # DRIFTED signature, and the restore-test glob must be unchanged.
  local dcsig
  dcsig="$(_consumer_db_signature "$doctored_cli")"
  [ "$dcsig" = "_database_*.sql.gz" ] || {
    echo "VACUOUS: doctored consumer signature was '${dcsig}', expected '_database_*.sql.gz' — the doctor did not bite."
    return 1
  }
  grep -qF 'prod_db_*.sql.gz' "$doctored_cli" || {
    echo "VACUOUS: the surgical consumer doctor unexpectedly altered the restore-test glob."
    return 1
  }

  # Render the live producer and assert the oracle rejects the drifted consumer.
  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  run _assert_agreement "${RENDER_TMP}/live-cron" "$doctored_cli"
  [ "$status" -ne 0 ] || {
    echo "VACUOUS GUARD: a drifted restore glob PASSED the agreement check."
    return 1
  }
  [[ "$output" == *"CONTRACT DRIFT"* ]] || {
    echo "agreement failed for an unexpected reason (not the consumer-drift arm):"
    echo "$output"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 7 — Encrypted producer (B).
# Rendered with ENABLE_ENCRYPTED_BACKUP=true, the cron encrypts each DB dump to
# <dump>.age (recipient = the .age-public-key), checksums the CIPHERTEXT, and removes
# the plaintext dump + sidecar after a successful encrypt+verify.
# ---------------------------------------------------------------------------
@test "producer (encrypted): cron with ENABLE_ENCRYPTED_BACKUP=true writes <env>_db_<…>.sql.gz.age, checksums the ciphertext, removes the plaintext" {
  run env ENABLE_ENCRYPTED_BACKUP=true bash "$CRON_HELPER" render "${RENDER_TMP}/enc-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  # (i) encrypts the DB dump to <dump>.age with the public-key recipient …
  grep -qF 'age -r "$(cat ${INSTALL_DIR}/.age-public-key)" -o "$DUMPFILE.age" "$DUMPFILE"' "${RENDER_TMP}/enc-cron" || {
    echo "encrypted producer: no 'age -r … -o \$DUMPFILE.age \$DUMPFILE' step found."
    echo "--- rendered ---"; cat "${RENDER_TMP}/enc-cron"; return 1
  }
  # … and the DB dump itself is still _db_*.sql.gz, so .age sits on the canonical stem.
  local psig
  psig="$(_producer_db_signature "${RENDER_TMP}/enc-cron")"
  [ "$psig" = "_db_*.sql.gz" ] || { echo "producer signature was '${psig}', expected '_db_*.sql.gz'"; return 1; }

  # (ii) checksum is computed over the CIPHERTEXT (.age), not the plaintext.
  grep -qF 'sha256sum "$DUMPFILE.age" > "$DUMPFILE.age.sha256"' "${RENDER_TMP}/enc-cron" || {
    echo "encrypted producer: checksum is not computed over the ciphertext (\$DUMPFILE.age)."
    return 1
  }

  # (iii) the plaintext dump + its sidecar are removed after a successful encrypt.
  grep -qF 'rm -f "$DUMPFILE" "$DUMPFILE.sha256"' "${RENDER_TMP}/enc-cron" || {
    echo "encrypted producer: plaintext dump + sidecar are not removed after encryption."
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 8 — Encrypted consumer (B).
# The restore arm must (a) consider *.sql.gz.age in its default selection, (b) detect a
# .age suffix, and (c) decrypt with the private key (${INSTALL_DIR}/.age-key.txt) before
# decompressing — i.e. it must not "normalize the .age away" and try to gunzip ciphertext.
# ---------------------------------------------------------------------------
@test "consumer (encrypted): the restore arm selects *.sql.gz.age and decrypts with the private key before load" {
  local arm
  arm="$(awk '/^[[:space:]]*restore\)/{f=1} f{print} f&&/;;/{exit}' "$CLI")"
  [ -n "$arm" ] || { echo "restore) arm not found"; return 1; }

  # (a) default selection also considers the encrypted artifact.
  printf '%s\n' "$arm" | grep -qF '"${env}"_db_*.sql.gz.age' || {
    echo "consumer: restore default-selection does not consider *.sql.gz.age artifacts."
    printf '%s\n' "$arm"; return 1
  }
  # (b) detects the .age suffix.
  printf '%s\n' "$arm" | grep -qF '== *.age' || {
    echo "consumer: restore arm has no '== *.age' detection branch."; return 1
  }
  # (c) decrypts with the Age private key before decompressing.
  printf '%s\n' "$arm" | grep -qF 'age --decrypt -i "${INSTALL_DIR}/.age-key.txt"' || {
    echo "consumer: restore arm does not decrypt with the Age private key before load."; return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 9 — Non-vacuity #3: anchored-root.
# Re-root an OFF-TREE copy of the restore glob at a sibling that SHARES the 'backups'
# prefix (…/backups-evil). The agreement oracle's root check is anchored to the closing
# quote, so it MUST reject the sibling. (With an un-anchored check this arm is vacuous.)
# The repo is never touched.
# ---------------------------------------------------------------------------
@test "non-vacuous (anchored root): a restore glob rooted at a backups-prefixed sibling FAILS agreement" {
  local doctored_cli
  doctored_cli="${RENDER_TMP}/doctored-cli-root"
  cp "$CLI" "$doctored_cli"
  # Re-root the backups path to a 'backups'-prefixed sibling. The closing-quote anchor in
  # _assert_agreement must reject '.../backups-evil'.
  sed -i 's#"\${INSTALL_DIR}/backups"#"\${INSTALL_DIR}/backups-evil"#g' "$doctored_cli"

  # Sanity (else vacuous): the doctored restore glob must now root at backups-evil.
  local arm
  arm="$(awk '/^[[:space:]]*restore\)/{f=1} f{print} f&&/;;/{exit}' "$doctored_cli")"
  printf '%s\n' "$arm" | grep -qF '${INSTALL_DIR}/backups-evil"' || {
    echo "VACUOUS: the root doctor did not re-root the restore glob to backups-evil."
    return 1
  }

  run bash "$CRON_HELPER" render "${RENDER_TMP}/live-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  run _assert_agreement "${RENDER_TMP}/live-cron" "$doctored_cli"
  [ "$status" -ne 0 ] || {
    echo "VACUOUS GUARD: a restore glob rooted at a backups-prefixed sibling PASSED agreement."
    return 1
  }
  [[ "$output" == *"CONTRACT DRIFT"* ]] || {
    echo "agreement failed for an unexpected reason (not the anchored-root arm):"
    echo "$output"; return 1
  }
}

# ---------------------------------------------------------------------------
# Arm 10 — Non-vacuity #4: ciphertext checksum (encrypted path).
# Doctor an OFF-TREE copy of the RENDERED encrypted cron so the DB sidecar is computed
# over the PLAINTEXT dump while still named .age.sha256 — the exact mistake the contract
# forbids — and prove arm 7's ciphertext-checksum oracle then FAILS. Rendered-output
# doctor (not generator doctor) is used for sed/dash-safety. The repo is never touched.
# ---------------------------------------------------------------------------
@test "non-vacuous (ciphertext checksum): an encrypted producer that checksums the plaintext FAILS the ciphertext-checksum assertion" {
  run env ENABLE_ENCRYPTED_BACKUP=true bash "$CRON_HELPER" render "${RENDER_TMP}/enc-cron"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  # Precondition: the live encrypted producer checksums the CIPHERTEXT.
  grep -qF 'sha256sum "$DUMPFILE.age" > "$DUMPFILE.age.sha256"' "${RENDER_TMP}/enc-cron" || {
    echo "precondition failed: live encrypted producer does not checksum the ciphertext."
    return 1
  }

  # Doctor: make the DB sidecar checksum the PLAINTEXT ($DUMPFILE) while keeping the
  # .age.sha256 name.
  local doctored="${RENDER_TMP}/enc-cron-plainck"
  cp "${RENDER_TMP}/enc-cron" "$doctored"
  sed -i 's/sha256sum "\$DUMPFILE\.age" > "\$DUMPFILE\.age\.sha256"/sha256sum "\$DUMPFILE" > "\$DUMPFILE.age.sha256"/' "$doctored"

  # Sanity (else vacuous): the doctored producer now checksums the plaintext …
  grep -qF 'sha256sum "$DUMPFILE" > "$DUMPFILE.age.sha256"' "$doctored" || {
    echo "VACUOUS: the checksum doctor did not bite."
    return 1
  }
  # … and arm 7's ciphertext-checksum oracle now FAILS on the doctored copy.
  if grep -qF 'sha256sum "$DUMPFILE.age" > "$DUMPFILE.age.sha256"' "$doctored"; then
    echo "VACUOUS GUARD: the doctored producer still satisfies the ciphertext-checksum oracle."
    return 1
  fi
}
