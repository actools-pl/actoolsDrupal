# Handoff — P0-C · Golden Behavior Capture

## Repository state

Branch: `phase0/P0-C-golden-behavior-capture`
Commit SHA: (record at `git commit` time)
Working tree clean? No — 1 modified + 4 untracked (all within docs/ and tests/)
Zip/package name if applicable: n/a

## Task completed

P0-C — Golden Behavior Capture.  All 5 variants of the generated-file matrix
captured as byte-exact golden fixtures; drift-detecting BATS test suite passing
6/6; no generator or runtime file touched.

## Files changed

**New (tests/)**

- `tests/helpers/capture_golden_outputs.sh` — capture helper; extracts
  `setup_stack()` (actools.sh:569-1028) and `setup_cli()` (actools.sh:1247-1528)
  from the live source via `sed`+`eval`; runs them in isolated subshells with
  no-op bash-function shims for `docker`, `chown`, `section`, `log`, `warn`,
  `error`, `setup_backup_db_user`
- `tests/generated/golden_drift_test.bats` — 6 BATS tests; re-renders and
  sha256-compares each variant; fails with diff output on unexplained mismatch
- `tests/fixtures/golden/default/` — 8 files (7 generated + SHA256SUMS)
- `tests/fixtures/golden/redis-off/` — 8 files
- `tests/fixtures/golden/s3-on/` — 8 files
- `tests/fixtures/golden/cadvisor-on/` — 8 files
- `tests/fixtures/golden/all-in-one/` — 8 files

**New (docs/)**

- `docs/tests/P0-C-golden-behavior-capture.md` — test report with matrix,
  limitations, acceptance rule, and intentional-difference table (empty)

**Modified (docs/)**

- `docs/runbooks/PHASE0_LEDGER.md` — Entry 008 added

## Files not changed but relevant

- `actools.sh` — generators frozen; untouched
- `cli/actools` — untouched
- `installer/*`, `core/*`, `modules/*`, `profiles/*` — untouched
- `.github/workflows/*` — untouched
- `docs/architecture/generated-file-contract.md` — governs acceptance rule

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | None |
| Init | None |
| Profile loading | None |
| Install stages | None |
| CLI | None — setup_cli() captured, not changed |
| Generated files | None — generators captured, not changed |
| Preflight | None |
| Doctor | None |
| Handoff | None |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | Not touched (generator at actools.sh:795 unedited) |
| Caddyfile | Not touched (generator at actools.sh:663 unedited) |
| my.cnf | Not touched (generator at actools.sh:595 unedited) |
| Dockerfiles | Not touched (generators at actools.sh:607/624/634 unedited) |
| CLI | Not touched (HELPER heredoc at actools.sh:1251-1520 and cli/actools unedited) |

## Tests run

```bash
bash -n tests/helpers/capture_golden_outputs.sh          # → syntax OK
bash tests/helpers/capture_golden_outputs.sh all         # → 5 variants captured
bash tests/helpers/capture_golden_outputs.sh default /tmp/v2 && \
  diff tests/fixtures/golden/default/SHA256SUMS /tmp/v2/default/SHA256SUMS
  # → no diff (deterministic)
bats tests/generated/golden_drift_test.bats              # → 6/6 ok
git diff --stat -- ':!docs' ':!tests'                    # → empty
git diff actools.sh cli/actools installer/ core/ modules/ profiles/  # → empty
```

## Test result

PASS — 6/6 bats tests; determinism confirmed; drift-detection confirmed

## Docs updated

- `docs/tests/P0-C-golden-behavior-capture.md` (new)
- `docs/runbooks/PHASE0_LEDGER.md` Entry 008

## Changelog / release notes updated

Not applicable (no user-visible change; capture infrastructure only).

## Ledger entry

Entry number: 008

## Known risks

1. **Line-number coupling:** The capture helper hardcodes actools.sh line ranges
   (SS_START=569, SS_END=1028, SC_START=1247, SC_END=1528).  The `_assert_fn_range()`
   guard detects drift before producing a wrong capture, but the helper must be
   updated when actools.sh line numbers change (e.g., after P0-D/P0-G edits).
   Update `SS_START`/`SS_END`/`SC_START`/`SC_END` at the same time as the
   actools.sh edit.

2. **redis-off depends_on quirk:** With `ENABLE_REDIS=false`, the compose file
   still has `depends_on: redis:` for php_prod and worker_prod.  The fixture
   captures this as-is.  P0-G must add an intentional-difference entry when it
   fixes this generator quirk.

3. **Dockerfile.php fallback:** The fixture captures the heredoc fallback path
   (actools.sh:624), not the repo's tracked `Dockerfile.php`.  In real installs
   the repo copy is used instead.  The golden test covers the generator code
   path, not the production path.

## Blockers

None.

## Exact next allowed task

**P0-D — Stage Dispatcher Scaffold:** wire `main()` in `actools.sh` to iterate
`PROFILE_INSTALL_STAGES` via a `run_install_stage`/`resolve_install_stage` loop
(append-only guard, behavior-preserving, community profile unchanged).  The
golden fixtures from P0-C serve as the safety net: run
`bats tests/generated/golden_drift_test.bats` before and after P0-D and confirm
6/6 green.

## Explicitly forbidden scope for next task

- No generator/runtime change before Review Gate approval of P0-C.
- No CI shellcheck additions (P0-I scope).
- No CLI consolidation (P0-F scope).
- No promotion of `docs/target/phase0/operator/` to `docs/operator/`.
- No dispatcher/resolver/profile wiring beyond P0-D's narrow append-only scaffold.

## Review Gate notes

Reviewer (Opus): confirm the variant matrix is complete — both OFF and ON
branches of every toggle must appear in the matrix.  Check:
- ENABLE_REDIS OFF → redis-off ✓  |  ON → default, s3-on, cadvisor-on, all-in-one ✓
- ENABLE_S3_STORAGE OFF → default, redis-off, cadvisor-on, all-in-one ✓  |  ON → s3-on ✓
- ENABLE_CADVISOR OFF → default, redis-off, s3-on, all-in-one ✓  |  ON → cadvisor-on ✓
- ENVIRONMENT_MODE production-isolated → default, redis-off, s3-on, cadvisor-on ✓  |
  all-in-one → all-in-one ✓
