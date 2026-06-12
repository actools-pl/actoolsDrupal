# Handoff — P0-L · Backup-Cron Extraction + Orphan Purge

## Repository state

Branch: `phase0/P0-L-backup-cron-extraction` (operator records the applied branch; sandbox base = the actoolsDrupal-main export at Entry 016 / P0-K)
Commit SHA: four implementation commits + one docs commit (sandbox sequence: `24f722e` golden capture → `2e33f66` security-shape guard → `09c5575` extraction → `e6aa398` orphan deletion → docs). Operator records the applied `main` SHA.
Working tree clean? yes (after the docs commit)
Zip/package name if applicable: n/a (sandbox tree)

## Task completed

P0-L per `P0-L-backup-cron-extraction.md`, in the spec's order — **capture + guard
first**, then the move, then the purge:

1. **Golden capture of the cron** — `tests/helpers/capture_backup_cron.sh` renders
   the LIVE `setup_backup_cron` under fixed inputs (`INSTALL_DIR=/opt/actools-golden`,
   `ENVIRONMENTS=prod`, explicit v14 S3 defaults `true`/`""`/`""`/`aws`, retention 7,
   rclone empty) and captured `/etc/cron.daily/actools-backup` as
   `tests/fixtures/golden/backup-cron/actools-backup`
   (sha `bdfaa0c6cb1f8f0a0ddf1540c52d7e7d4d095d62b9331f4d85164d5eaf76f249`).
   The helper pins the real install target (`cat > /etc/cron.daily/actools-backup
   <<BACKUP` + `chmod +x`) and substitutes ONLY the output location in its
   in-memory copy — the heredoc bytes are untouched and no repo file is modified
   at render. The fixture holds **no secret** (the backup password is read from
   `.actools-state.json` at cron runtime; pinned by a test). Drift test:
   `tests/generated/backup_cron_drift_test.bats` (3 tests, re-render → byte-compare).
2. **Cron security-shape guard** — `tests/guards/cron_security_shape_guard_test.bats`
   (4 tests): the rendered cron MUST contain `mariadb-dump --defaults-extra-file=`;
   MUST NOT carry any argv-password form (`-p"…"`/`-p'…'`/`-p$…`/`--password=`);
   MUST fetch `backup_user_pass` from state at runtime; plus a **permanent in-CI
   non-vacuity arm** (a doctored generator copy with the orphan's `-ubackup -p"$BK"`
   form renders through the same pipeline and the oracle must reject it) and a
   generator-source arm. Both suites are CI-gated by the existing recursive bats
   job — no workflow edit.
3. **Extraction** — `setup_backup_cron` moved **verbatim** into
   `modules/backup/cron.sh` (LIVE AUTHORITY (P0-L) header; functions only; on the
   live source-closure). `actools.sh` 835 → 763 lines: the inline block
   (`:584-661`) replaced by `source "${INSTALL_DIR}/modules/backup/cron.sh" ||
   error …` at the exact spot the function occupied. The `setup_cli` canary in
   `tests/helpers/capture_golden_outputs.sh` moved 666-681 → 594-609 (the helper's
   documented maintenance step).
4. **Orphan purge** — `cron/backup.sh` deleted; grep-proof empty (see below).

## Files changed

- `modules/backup/cron.sh` — **new live module** (verbatim `setup_backup_cron`)
- `actools.sh` — inline block → `source` line only (835 → 763 lines)
- `cron/backup.sh` — **deleted**
- `tests/helpers/capture_backup_cron.sh` — new (capture/render/render-from)
- `tests/generated/backup_cron_drift_test.bats` — new (3 tests)
- `tests/fixtures/golden/backup-cron/{actools-backup,SHA256SUMS}` — new fixture
- `tests/guards/cron_security_shape_guard_test.bats` — new (4 tests)
- `tests/helpers/capture_golden_outputs.sh` — `setup_cli` canary line numbers only
- `ROADMAP.md` — one-line doc-truth correction (the orphan-is-present parenthetical
  falsified by the deletion). **Outside the spec's allowed-files list — deliberate,
  flagged for the Review Gate to confirm or revert.**
- Docs: `PHASE0_LEDGER.md` (Entry 017), `runtime-authority-map.md` (new row +
  P0-L answer + test-surface addendum), `CHANGELOG.md`,
  `docs/releases/P0-L-backup-cron-extraction.md`,
  `docs/tests/P0-L-backup-cron-extraction.md`, this handoff

## Files not changed but relevant

- The other inline heredocs — the `db_exec_root <<SQL` DB-user heredocs
  (`actools.sh:492,563` — line numbers unchanged; the edit begins at `:584`) and
  the help/version `<<EOF` (`:59`) — **byte-unchanged** (forbidden scope held)
- `main()` and the `setup_backup_cron` call site — untouched
- The remaining `modules/backup/*` files (encrypted_backup, pitr, binlog, …) —
  untouched P0-O-audit orphans
- `.github/workflows/lint.yml` — untouched (recursive bats auto-discovers the new
  suites; `cron/*.sh` shellcheck glob still matches `cron/stats.sh`)
- The six compose-stack golden fixtures — **no fixture modified** (drift 6/6)
- `core/*.sh`, `installer/*`, `cli/*`, `profiles/*` — untouched

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | none |
| Install stages | none (the dispatcher and the trailing `setup_backup_cron` call are untouched; only the function's *definition* moved) |
| CLI | none |
| Generated files | the backup cron is now golden-captured; its bytes are **unchanged**. New authority row: backup-cron generator = `modules/backup/cron.sh` (live module); the insecure orphan `cron/backup.sh` is deleted |
| Preflight | none |
| Doctor | none |
| Handoff | none |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | unchanged (drift 6/6 at every commit) |
| Caddyfile | unchanged (drift 6/6) |
| my.cnf | unchanged (drift 6/6) |
| Dockerfiles | unchanged (drift 6/6) |
| CLI | not touched (`cli_authority_test.bats` green in the full suite) |
| /etc/cron.daily/actools-backup | **unchanged — byte-identical** (re-render sha == pre-extraction fixture sha `bdfaa0c6…`) |

## Tests run

```bash
bash -n actools.sh && bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/generated/        # 9/9 (cron capture 3 + compose drift 6)
bats tests/guards/           # 9/9 (cron security shape 4 + P0-K guards 5)
bats -r tests/               # 199/199
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 modules/backup/cron.sh
shellcheck --exclude=SC2034,SC2015,SC2164 cron/*.sh
grep -rn "cron/backup.sh" . --include='*.sh' --include='*.yml' --include='*.bats'  # → empty
```

## Test result

PASS — 199/199 (192 → 199); golden drift 6/6 at every commit; cron fixture
byte-identical across the extraction; guard non-vacuous (in-CI arm + live demo).

## Docs updated

Ledger Entry 017; runtime-authority-map (backup-cron row, P0-L answer,
test-surface 192 → 199); release note; test report (with the verbatim
non-vacuity demo outputs); this handoff. Generated-file contract needed no edit
(its "generated backup/cron helper files" clause is now satisfied by the new
fixture).

## Changelog / release notes updated

`docs/CHANGELOG.md` ([Unreleased] — P0-L section);
`docs/releases/P0-L-backup-cron-extraction.md`;
`docs/tests/P0-L-backup-cron-extraction.md`.

## Ledger entry

Entry number: **017**

## Known risks

- The `setup_cli` canary now reads 594-609; any future edit above `setup_cli` in
  `actools.sh` must update it (the helper fails loudly with instructions).
- The cron renderer interposes only the output location after pinning the real
  target strings; if a future phase renames `/etc/cron.daily/actools-backup`,
  the helper hard-fails rather than silently capturing the wrong artifact.
- `lint.yml` does not shellcheck `modules/backup/*.sh` (pre-existing — P0-O
  orphans live there). The new module is shellcheck-clean locally and
  behavior-gated by three bats suites; CI shellcheck for the directory belongs
  to the P0-O audit.
- The `ROADMAP.md` one-line correction is an allowed-files deviation (doc-truth
  fix for a claim the deletion falsified) — Review Gate to confirm or revert.
- Entry 016's "Next safe task" had predicted "P0-L — DB layer extraction"; the
  plan renumbered (this phase's spec is authoritative). Entry 017 records the
  discrepancy and points Next safe task at **P0-M — DB layer extraction**.

## Blockers

None.

## Exact next allowed task

**P0-M — DB layer extraction** (post-closure track, renumbered plan). Still NOT
community-plus feature work.

## Explicitly forbidden scope for next task

No `install_env`/CLI extraction outside its own phase file; no
standalone-feature-orphan wiring before P0-O's audit; `main()`'s hardcoded
profile source stays until P0-P; no generated-file change; no edit to
`modules/backup/cron.sh` or the cron fixture without an explicit re-capture +
release note.

## Review Gate notes

Verify each Definition-of-Done item independently:

1. **Byte-identical generated cron.** `bash tests/helpers/capture_backup_cron.sh
   render /tmp/x && sha256sum /tmp/x tests/fixtures/golden/backup-cron/actools-backup`
   → both `bdfaa0c6…`. Confirm the fixture's commit (`24f722e`, capture) PRECEDES
   the extraction commit (`09c5575`) — the fixture pins the inline generator's
   output and the module re-renders it. Independently: `diff` the function text
   in `modules/backup/cron.sh` against `actools.sh:584-661` at the pre-extraction
   commit (the test report shows the `extract_inline_fn` method).
2. **The guard bites.** Run `bats tests/guards/cron_security_shape_guard_test.bats`
   (4/4 green; test 3 is the permanent non-vacuity arm). Optionally repeat the
   live demo from the test report: inject the orphan form into `actools.sh`
   (working tree), observe arms 1/2/4 + the drift test fail, revert.
3. **Orphan gone + unreferenced.** `[[ ! -e cron/backup.sh ]]` and the grep-proof
   command above → empty. Note the module/guard comments intentionally avoid the
   literal path so the proof grep stays empty.
4. **Golden drift 6/6, no compose fixture modified.** `bats
   tests/generated/golden_drift_test.bats` + `git log --stat` on
   `tests/fixtures/golden/{default,redis-off,s3-on,cadvisor-on,all-in-one}` → no
   change.
5. **No other heredoc / behavior changed.** `git diff <base>..HEAD -- actools.sh`
   shows exactly one hunk: the `:584-661` block → the 6-line P0-L source block.
   The `db_exec_root <<SQL` heredocs (`:492,563`) and help/version `<<EOF` (`:59`)
   are byte-unchanged.
6. **No argv-password form on the backup path.** Guard arms 2/4 prove it for the
   generated cron and its generator; `cli/actools` (the `backup` command) and
   `cli/commands/update.sh` use the same `--defaults-extra-file` shape. A
   tree-wide sweep (`grep -rnE '(^|[[:space:]])-p["'"'"'$]' actools.sh
   modules/backup/cron.sh cli/actools`) surfaces exactly ONE hit, and it is
   **pre-existing and out of P0-L scope**: `actools.sh:510` — the v9.2-fix4
   `wait_db()` readiness probe (`mariadb -uroot -p"${_wp}"`, the DB **root**
   password, not the backup password). It is byte-identical to the baseline
   (P0-L's only `actools.sh` hunk is the `:584-661` block), it predates this
   phase, and hardening it is a behavior change belonging to the DB-layer phase
   (P0-M candidate — flagged in the ledger's Known risks). The backup password
   is on argv NOWHERE.
7. **Allowed-files deviations to adjudicate:** the `setup_cli` canary line-number
   update in `tests/helpers/capture_golden_outputs.sh` (the P0-K-documented
   maintenance step — required, or the drift suite fails) and the one-line
   `ROADMAP.md` correction (optional — revert if judged scope-bleed; the runtime
   outcome is unaffected).

Render: **Approved / Needs revision / Blocked**.
