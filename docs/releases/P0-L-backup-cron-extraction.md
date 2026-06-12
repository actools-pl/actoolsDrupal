# P0-L — Backup-Cron Extraction + Orphan Purge

**Status:** implemented; pending Review Gate
**Behavior change:** none — the generated `/etc/cron.daily/actools-backup` is byte-identical
**Suite:** 192 → 199 bats tests, all green; golden drift 6/6 at every commit (no compose fixture modified)

## What changed

### 1. The backup cron is now a golden-captured generated file

The daily backup cron was the one generated file without a fixture. P0-L closes that
gap per the generated-file contract's "generated backup/cron/systemd helper files,
if present" clause:

- `tests/helpers/capture_backup_cron.sh` renders the **live** `setup_backup_cron`
  generator under fixed deterministic inputs (`INSTALL_DIR=/opt/actools-golden`,
  `ENVIRONMENTS=prod`, explicit v14 S3 defaults, retention 7, rclone empty). The
  helper locates whichever file live-defines the function — `modules/backup/cron.sh`
  after this phase, the inline `actools.sh` block before it — so **the same renderer
  spans the extraction**, which is what makes a green drift run the byte-identity
  proof for the move. It pins the real install target
  (`cat > /etc/cron.daily/actools-backup <<BACKUP` + `chmod +x`) and substitutes
  only the output location in its in-memory copy; the heredoc bytes and every
  render-time expansion are untouched, and no repo file is modified at render.
- Fixture: `tests/fixtures/golden/backup-cron/{actools-backup,SHA256SUMS}`
  (sha `bdfaa0c6cb1f8f0a0ddf1540c52d7e7d4d095d62b9331f4d85164d5eaf76f249`).
  **The fixture holds no secret**: the backup password is read from
  `.actools-state.json` at cron *runtime* (the `jq` line in the script); the
  generator's `backup_pass` local never reaches the heredoc. A dedicated test
  pins both facts, which is what makes the fixture committable.
- Drift gate: `tests/generated/backup_cron_drift_test.bats` (3 tests) re-renders
  and byte-compares on every CI run, discovered by the existing recursive bats job.

### 2. The secure cron shape is CI-locked

`tests/guards/cron_security_shape_guard_test.bats` (4 tests) encodes the security
rule this phase exists to protect:

- The generated cron **must** contain `mariadb-dump --defaults-extra-file=` — the
  secure form: credentials written to a `umask 077` temp file *inside* the DB
  container, fed over stdin, removed on exit.
- The generated cron **must not** pass a password on argv — no `-p"…"`, `-p'…'`,
  `-p$…`, or `--password=` form (argv is visible to every local user via `ps`).
- The password path is pinned: `backup_user_pass` fetched from state at runtime,
  never baked at install time.
- **Non-vacuity is permanent, not a one-off demo**: an in-CI arm doctors a copy of
  the live generator with the retired orphan's exact `-ubackup -p"$BK"` invocation,
  renders it through the same pipeline, and requires the shape oracle to reject it.
  A live injection demo (outputs verbatim in `docs/tests/P0-L-backup-cron-extraction.md`)
  additionally shows guard arms 1/2/4 *and* the drift test failing against a
  doctored `actools.sh`, then green after a byte-identical revert.

### 3. `setup_backup_cron` extracted verbatim into `modules/backup/cron.sh`

- The function body was moved **byte-for-byte** (verified by `diff` of the
  extracted function text against the pre-extraction inline block, using the P0-K
  brace-counting primitive — confirmed heredoc-safe against the raw line range).
- `actools.sh` 835 → 763 lines: the inline block (`:584-661`) is replaced by
  `source "${INSTALL_DIR}/modules/backup/cron.sh" || error …` at the exact spot
  the function occupied (the P0-K source-line style). The `main()` call site and
  everything else are untouched; the module carries a `LIVE AUTHORITY (P0-L)`
  header and is functions-only (inert under `set -u`), on the live source-closure
  the P0-K live-authority guard checks.
- The `setup_cli` line canary in `tests/helpers/capture_golden_outputs.sh` moved
  666-681 → 594-609 — the helper's own documented maintenance step.

### 4. The insecure orphan `cron/backup.sh` is deleted

`cron/backup.sh:27` ran `mariadb-dump … -ubackup -p"${BACKUP_PASS}" "$DB"` — the
DB password on argv. It was unwired (nothing sourced, copied, or executed it; the
P0-J closure review had already rejected the recommendation to treat it as safe)
and is now gone. Grep-proof: `grep -rn "cron/backup.sh" . --include='*.sh'
--include='*.yml' --include='*.bats'` returns nothing. `cron/stats.sh` remains, so
the CI `cron/*.sh` shellcheck glob stays non-empty — no workflow edit. The one
`ROADMAP.md` sentence describing the orphan as present in the repo was corrected.

## What deliberately did not change

- The generated cron's bytes (the phase's hard rule) — and the six compose-stack
  golden fixtures (drift 6/6, fixtures unmodified).
- The other inline heredocs: the `db_exec_root <<SQL` DB-user heredocs
  (`actools.sh:492,563`) and the help/version `<<EOF` (`:59`).
- DB layer / `install_env` / CLI extraction (P0-M / P0-N); the remaining
  `modules/backup/*` orphans (P0-O audit first); `main()` (P0-P).
- `ACTOOLS_VERSION` stays `14.0`; `.github/workflows/lint.yml` untouched (the
  recursive bats job auto-discovers the new suites).

## Evidence index

- Byte-identity: re-render sha == fixture sha `bdfaa0c6…` at every commit since
  capture; per-function `diff` clean module-vs-inline.
- Guard bite: in-CI non-vacuity arm + the live demo in the test report.
- Orphan purge: the grep-proof above.
- Ledger: `docs/runbooks/PHASE0_LEDGER.md` Entry 017.
- Handoff for the Review Gate: `docs/runbooks/HANDOFF-P0-L.md`.
