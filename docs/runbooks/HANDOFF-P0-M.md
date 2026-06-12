# Handoff — P0-M · Stateful DB Layer Extraction (tests-first) + `wait_db` Hardening

## Repository state

Branch: `phase0/P0-M-db-layer-extraction` (sandbox; operator records the applied branch + real `main` SHA at apply time — the export carried no `.git`)
Commit SHA: five implementation commits + one docs commit (sandbox sequence: `f8830bf` contract/mock tests → `37bf3cd` duplicate-function guard extension → `7b5347a` verbatim extraction → `496ca42` orphan retirement + twin-ban hardening → `e9471ce` `wait_db` hardening → docs)
Working tree clean? yes (after the docs commit)
Zip/package name if applicable: n/a (sandbox working tree)

## Task completed

P0-M per `P0-M-db-layer-extraction.md`: (1) contract/mock tests pinned the inline DB layer's commands and SQL over a PATH-interposed mock `docker` (stateful layer — no golden-capturable output); (2) the duplicate-function guard extended to the six DB names; (3) the six functions extracted **verbatim** into `modules/db/core.sh` (per-function byte-identity; contracts green across the move with zero assertion edits); (4) the stale v9.2 twins `modules/db/{backup_user,credentials,wait}.sh` deleted (content never adopted) and the unconditional twin ban extended to `modules/db`; (5) **the one intentional behavior change** — `wait_db`'s readiness probe hardened from the argv-password form (`mariadb -uroot -p"${_wp}"`, ex-`actools.sh:510`) to the umask-077 `--defaults-extra-file` shape inside the container (printf-builtin stdin; the backup-cron pattern), same probe SQL / 50×3s bounds / outcome, as an isolated, droppable final commit. Entry-017's `wait_db:510` known risk is closed subject to the e2e gate below.

## Files changed

- `modules/db/core.sh` — new live module (`LIVE AUTHORITY (P0-M)`; verbatim six functions; then the isolated `wait_db` hardening)
- `actools.sh` — 763 → 690 lines (the `:450-530` inline region → banner + one `source` line; nothing else)
- `modules/db/backup_user.sh`, `modules/db/credentials.sh`, `modules/db/wait.sh` — **deleted**
- `tests/db/db_layer_loader.bash`, `tests/db/mock_docker.bash`, `tests/db/db_contract_test.bats` (new, 13)
- `tests/guards/duplicate_function_guard_test.bats` — extended (sixteen names; modules/db in the wired-twin + twin-ban arms)
- `tests/guards/wait_db_security_guard_test.bats` (new, 4; permanent non-vacuity arm)
- `tests/helpers/capture_golden_outputs.sh` — `setup_cli` canary 594-609 → 521-536 only
- `docs/runbooks/PHASE0_LEDGER.md` (Entry 018), `docs/architecture/runtime-authority-map.md`, `docs/CHANGELOG.md`, `docs/releases/P0-M-db-layer-extraction.md`, `docs/tests/P0-M-db-layer-extraction.md`, this handoff

## Files not changed but relevant

- `install_env` and its `db_exec_root <<SQL` call sites; `cli/commands/*` DB helpers — **P0-N scope**, untouched
- `main()` (P0-P); all standalone feature orphans (P0-O)
- `.github/workflows/lint.yml` — recursive bats auto-discovers the new suites; the `modules/db/*.sh` shellcheck glob still matches `core.sh`
- `.github/workflows/e2e.yml` — unchanged; it is the hardening's authoritative gate (see Review Gate notes)
- Golden fixtures — none modified
- `modules/backup/cron.sh` — the pattern `wait_db` now mirrors; unchanged

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | none |
| Install stages | none (the `db` stage stays the documented no-op; the DB layer functions moved, their callers did not) |
| CLI | none |
| Generated files | none (drift 6/6 + cron fixture at every commit) |
| Preflight | none |
| Doctor | none |
| Handoff | none |
| **DB access layer (new row)** | `modules/db/core.sh` is the live authority for the six DB functions; the v9.2 twins are deleted; `wait_db`'s probe auth method is the one intentional change (CI-locked secure shape) |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | unchanged (drift 6/6 every commit) |
| Caddyfile | unchanged |
| my.cnf | unchanged |
| Dockerfiles | unchanged |
| CLI | not touched (`cli_authority_test.bats` green) |
| /etc/cron.daily/actools-backup | unchanged (cron drift 3/3; fixture sha `bdfaa0c6…`) |

## Tests run

```bash
bash -n actools.sh && bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/db/                                 # 13/13
bats tests/guards/                             # 13/13 (dup-fn 3 + wait_db security 4 + cron shape 4 + authority/closure 2)
bats tests/generated/                          # 9/9 (compose 6 + cron 3)
bats -r tests/                                 # 216/216
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 modules/db/core.sh
shellcheck --exclude=SC2034,SC2015,SC2164,SC2119,SC2120 modules/db/*.sh
grep -rn "modules/db/backup_user.sh\|modules/db/credentials.sh\|modules/db/wait.sh" . --include='*.sh' --include='*.yml' --include='*.bats'   # no references
```

## Test result

PASS — 216/216 (199 → 216); drift 6/6 + cron fixture at every commit; per-function byte-identity for the extraction (and re-verified for the five non-`wait_db` functions after the hardening); guard non-vacuity captured twice (wired-twin demo at commit-2 state; three-arm end-state demo); `wait_db` security non-vacuity captured (permanent arm + live injection demo that also failed the contract oracle); old-vs-new `wait_db` outcome-identical against the mock in all scenarios; container-side temp-file mechanics proven under real `sh`. All verbatim outputs: `docs/tests/P0-M-db-layer-extraction.md`.

## Docs updated

Ledger Entry 018 (closes the Entry-017 `wait_db:510` known risk, subject to the e2e gate); runtime authority map (new DB-layer row, corrected DB-provisioning row, P0-M test-surface addendum); release note; test report.

## Changelog / release notes updated

`docs/CHANGELOG.md` (P0-M Unreleased section); `docs/releases/P0-M-db-layer-extraction.md`; `docs/tests/P0-M-db-layer-extraction.md`.

## Ledger entry

Entry number: **018**

## Known risks

- **The e2e gate is pending CI.** The hardening's authoritative equivalence proof — a real install reaching DB-ready (`e2e.yml`) — cannot run in the coding sandbox (no docker daemon / `HCLOUD_TOKEN`). Mock-level outcome equivalence and real-`sh` mechanics are proven; real-MariaDB auth via `--defaults-extra-file` is not exercised here. Mitigation: the hardening is the isolated final implementation commit (`e9471ce`) and is droppable without touching steps 1–4 (the spec's split rule). **Do not Approve before the e2e is green.**
- Spec wording vs code: "poll until the DB answers `SELECT 1`" was read against the authoritative inline code — `wait_db`'s probe is the v9.2-fix4 **write-check** (preserved verbatim); `SELECT 1` is `check_db_creds`' probe (also pinned). No probe SQL changed.
- The `setup_cli` canary reads 521-536; future edits above `setup_cli` must update it (the helper fails loudly).
- The security oracle checks executable text (comments stripped); a multi-line string-built argv password would evade the static arms — the behavioral mock arm and the contract stdin pin are the backstop.

## Blockers

None.

## Exact next allowed task

**P0-N — `install_env` / CLI extraction** (per the post-closure plan and Entry 018's "Next safe task").

## Explicitly forbidden scope for next task

No standalone-feature-orphan wiring before P0-O's audit; `main()` stays until P0-P; no generated-file change; no edit to `modules/db/core.sh`, its contracts, or its guards without an explicit release note; the retired `modules/db` twins must never be restored (the twin ban bites).

## Review Gate notes

Verify, in order:
1. **Contracts green and unchanged across the move** — `bats tests/db/` 13/13; confirm via `git log -p tests/db/db_contract_test.bats` that the only post-capture edit is the commit-5 `_assert_wait_db_probe_shape` update (the documented intentional change); confirm the loader origin flipped inline → module with zero assertion edits in the extraction commit.
2. **Byte identity** — re-run the per-function diff (test report §2); the five non-`wait_db` functions must also match the pre-extraction texts at HEAD.
3. **Drift** — `bats tests/generated/` 9/9; `git diff --stat` shows no fixture touched.
4. **Guards bite** — reproduce either non-vacuity demo from the test report (§3) or trust the captured outputs + the permanent in-CI arms; all three dup-fn arms cover the six DB names.
5. **`wait_db` secure and still polling** — `bats tests/guards/wait_db_security_guard_test.bats` 4/4; the contract's polling-outcome tests unchanged; **then the CI e2e: the real install must reach DB-ready** (watch the `Waiting for MariaDB (write-check)... / MariaDB ready.` window). If it does not, mark **Needs revision** and direct the operator to drop commit `e9471ce` only.
6. **Orphans gone + unreferenced** — the grep proof (empty), and `ls modules/db/` shows only `core.sh`.
7. **No behavior change beyond the hardening** — the only `actools.sh` hunk is `:450-530` → the source block; call sites byte-untouched; `ACTOOLS_VERSION` still `14.0`.
