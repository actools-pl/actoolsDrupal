# Phase 0 Ledger

## Purpose

This ledger is the durable memory of the project. Update it after every phase, even if no code changed.

## Current status

Phase 0 status: CLOSED — GO (see `PHASE0_UNLOCK_MEMO.md`)  
Post-closure track (P0-K…P0-P): UNLOCKED  
community-plus feature work: gated behind P0-K…P0-P

## Ledger entry template

````markdown
## Entry 000 — Title

Date:
Branch:
Commit SHA:
Actor / Claude session (model):
Phase:
Task prompt source:

### Objective

### Files changed

- 

### Files intentionally not changed

- 

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
|  |  |  |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml |  |  |
| Caddyfile |  |  |
| my.cnf |  |  |
| Dockerfiles |  |  |
| CLI |  |  |

### Tests run

```bash
# paste exact commands
```

### Test result

PASS / FAIL / PARTIAL

### Documentation updated

- [ ] Runtime authority map
- [ ] Generated-file contract
- [ ] CLI authority contract
- [ ] Operator target docs
- [ ] Test plan

### Changelog / release notes

- [ ] CHANGELOG.md updated
- [ ] Release note added
- [ ] Test report added
- [ ] Review notes added

### Known risks

### Blockers

### Review Gate decision

Approved / Needs revision / Blocked

### Next safe task

### Forbidden next scope
````

## Entry 019 — P0-N · CLI DB-Layer Convergence (live `doctor.sh`)

Date: 2026-06-12
Branch: `phase0/P0-N-cli-db-convergence` (operator records the applied branch + `main` SHA)
Commit SHA: three implementation commits + one docs commit (sandbox sequence: `7b88539` swap → `e7ba619` live-CLI-path guard → `8d33573` focused authority test → docs)
Actor / Claude session (model): Coding Window
Phase: P0-N — CLI DB-Layer Convergence (live `doctor.sh`)
Task prompt source: `P0-N-cli-db-convergence.md` + coding-window prompt (filled)

### Objective

Eliminate the one **live** second-order dual-truth left after P0-M: `cli/commands/doctor.sh` carried its **own copy** of `db_exec_root` (`:27`, byte-identical to `modules/db/core.sh:45` — re-verified, including the `:24-26` comment ≡ `core.sh:42-44`), so a future fix to the module would silently not reach `doctor`. The live `doctor` command now **sources the canonical module** at the exact top-level spot the local def occupied and the local copy is **deleted** — the DB layer has exactly one authority across both runtimes. A **live-CLI-path guard** makes any future redefinition on the live CLI path fail CI. This is a verbatim-equivalent swap: the `:160` call site is byte-untouched (and still at `:160` — the replacement is 6-for-6 lines); `doctor`'s behavior and output do not change; **not** an extraction, **not** a behavior change.

### The swap (commit 1) — and one flagged deviation

`doctor.sh:24-29` (the local def + its comment) replaced in place by a pointer comment + `source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true`. Grounding re-verified before the swap: `core.sh` is pure function defs (sourced cleanly under `set -u` in an empty env, defining exactly the six names); the only live consumer of `doctor.sh` is `cli/actools:90`, which resolves `INSTALL_DIR` at `:7` first (the `installer/*` mentions are header comments); nothing `doctor.sh` sources (`dispatch.sh`, `output.sh`, `doctor_deep.sh`) defines any of the six names — no double definition. Top-level placement (the spec's in-place reading) preserves the **old source-time semantics**: `db_exec_root` is defined when `cli/actools` sources `doctor.sh`, before `run_doctor` runs, exactly as the local def was.

**Flagged deviation (Review Gate to confirm):** the spec snippet showed a *bare* `source`; the landed line is **best-effort** (`2>/dev/null || true`). A bare source broke 9 existing tests (`doctor_test.bats` 4, `test_p0h_dispatch` 2, `test_p0i` 3): the deep-gate suites stage **minimal sandbox** `INSTALL_DIR`s without `modules/`, a contract `doctor.sh:37-39` itself documents ("best-effort … e.g. a minimal sandbox") and the same pattern its `dispatch.sh` source already uses. Best-effort restores that contract (suite 230/230); its non-vacuity is pinned by the focused authority test (a typo'd module path leaves `db_exec_root` undefined → the resolution arm goes red — demonstrated live in the test report). The alternative — staging `core.sh` into the sandboxes of 5 existing test files — was out of the allowed-files list.

### Live-CLI-path guard (commit 2)

`tests/guards/cli_db_authority_guard_test.bats` (7 arms): the **live CLI path** is derived statically — `cli/actools` plus every `source "${INSTALL_DIR}/cli/commands/<f>.sh"` target parsed out of `cli/actools` (today: `doctor.sh`; one level, per the spec). Main arm: none of the six canonical names is **defined** (`^name()`) on that set; the authority `modules/db/core.sh` is excluded **by construction** (not a `cli/commands` file; the builder never recurses into live command files' source lines). Sanity arms pin the known live shape and that the authority still defines all six. **Permanent non-vacuity arms** (fixture tree): an injected `db_exec_root` on a live command file fails; an injected `wait_db` on `cli/actools` fails; a missing live source target fails loudly (wrong wiring is not an exemption). Dead-twin arm: the eight dead twins are **not** in `cli/actools`'s source set — naturally excluded, guard green pre-P0-O (several still define DB-fn copies on disk) and post-P0-O (existence-conditional). **Live demo (captured in the test report):** re-adding the old `db_exec_root` def to `doctor.sh` failed the main arm at `cli/commands/doctor.sh:257`; reverted byte-identical (sha-verified).

### Focused authority test (commit 3)

`tests/cli/doctor_db_authority_test.bats` (7) + `tests/cli/doctor_loader.bash`: no local `db_exec_root` def remains; the authority source line is present; sourcing `doctor.sh` is **inert** (rc 0, no output); with `INSTALL_DIR` at the repo, `db_exec_root` is defined **at source time** and its `declare -f` body is **byte-equal** to the canonical `core.sh` body (all six arrive; five inert); the **non-vacuity twin** — in a sandbox without the module, `db_exec_root` does *not* come out defined, proving the definition arrives via `${INSTALL_DIR}/modules/db/core.sh`; and a mock-docker **oracle** (the P0-M stub) pins that the resolved function issues the exact canonical container command (same argv pin as `tests/db/`).

### Files changed

- `cli/commands/doctor.sh` — the 6-for-6 in-place swap (only hunk in the file; `:160` call site byte-untouched at `:160`)
- `tests/guards/cli_db_authority_guard_test.bats` (new, 7)
- `tests/cli/doctor_db_authority_test.bats` + `tests/cli/doctor_loader.bash` (new, 7)
- Docs: this ledger (Entry 019 + Entry 018 ratification), `runtime-authority-map.md`, `docs/CHANGELOG.md`, `docs/releases/P0-N-cli-db-convergence.md`, `docs/tests/P0-N-cli-db-convergence.md`, `docs/runbooks/HANDOFF-P0-N.md`

### Files intentionally not changed

- **The eight dead twins** (`backup`, `ci_generate`, `cost_optimize`, `health`, `restore`, `storage`, `update`, `worker`) — untouched; their DB-fn copies (`cost_optimize.sh:10`, `restore.sh:9,:15`, `update.sh:10`) are **P0-O**
- `modules/db/core.sh` — the authority; no edits (P0-M contracts/guards untouched: `tests/db/` 13/13, dup-fn + wait_db guards green)
- `actools.sh`, `main()`, `installer/`, `profiles/`; generated files / golden fixtures (drift 6/6 + cron 3/3, no fixture modified)
- `.github/workflows/` — the recursive bats job auto-discovers `tests/cli/` and the new guard

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| `db_exec_root` on the live CLI path (`doctor`) | local copy in `cli/commands/doctor.sh:27` (byte-identical dual truth) | resolved from `modules/db/core.sh` (single authority across installer **and** CLI), CI-locked by the live-CLI-path guard |
| Other five DB functions on the live CLI path | undefined | defined (inert) from the module at `doctor.sh` source time — no call sites |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | golden drift 6/6 at every commit |
| Caddyfile | Not touched | golden drift 6/6 |
| my.cnf | Not touched | golden drift 6/6 |
| Dockerfiles | Not touched | golden drift 6/6 |
| CLI | Not touched (`cli/actools` byte-unchanged; `doctor.sh` is the one swapped file, behavior-identical) | `cli_authority_test.bats` green in the full suite; doctor-smoke = e2e backstop |
| /etc/cron.daily/actools-backup | Not touched | cron drift 3/3 at every commit |

### Tests run

```bash
bash -n cli/commands/doctor.sh && bash -n cli/actools
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 cli/commands/doctor.sh   # pre-existing info SC2012(:200) only — identical on the baseline file
bats tests/guards/                 # 20/20: existing 13 + new cli_db_authority 7
bats tests/cli/                    # 7/7 (new)
bats tests/db/                     # 13/13 — P0-M contracts unaffected
bats tests/generated/              # 9/9: drift 6/6 + cron 3/3
bats -r tests/                     # 230/230 (216 → 230: +7 guard, +7 cli)
grep -nE '^db_exec_root\(\)' cli/commands/doctor.sh                       # EMPTY
grep -nE 'source.*modules/db/core\.sh' cli/commands/doctor.sh             # :29 present
for f in db_exec_root db_exec_root_stdin db_dump_container setup_backup_db_user wait_db check_db_creds; do
  grep -nE "^${f}\(\)" cli/actools cli/commands/doctor.sh ; done          # EMPTY
```

### Test result

PASS — full suite 230/230 at every commit (216 → 230); drift 6/6 + cron 3/3 unchanged; the live-CLI-path guard non-vacuous (three permanent fixture arms + the captured live injection demo); the focused authority test proves the resolved `db_exec_root` ≡ `core.sh` byte-equal and that the resolution genuinely travels the module path.

### Documentation updated

- [x] Runtime authority map (Doctor row + DB-layer row: single authority across both runtimes; P0-N answer + test-surface addendum)
- [ ] Generated-file contract — no change needed (nothing generated changed)
- [ ] CLI authority contract — `cli/actools` byte-unchanged (install-by-copy untouched)
- [ ] Operator target docs — no operator-visible change (doctor output identical)
- [x] Test plan / test report

### Changelog / release notes

- [x] CHANGELOG.md updated
- [x] Release note added (`docs/releases/P0-N-cli-db-convergence.md`)
- [x] Test report added (`docs/tests/P0-N-cli-db-convergence.md`)
- [x] Review notes — for the Review Gate, see the handoff (`docs/runbooks/HANDOFF-P0-N.md`)

### Known risks

- **The best-effort `|| true` deviation** (see the swap section): in a hypothetically broken install missing `modules/db/core.sh`, doctor's DB check would report "Database unreachable" instead of erroring at the source line. Pre-P0-N such an install was already catastrophically broken (the installer itself sources `core.sh`); the typo-risk the `|| true` could mask is pinned red by the focused test's resolution arm, and the real-install backstop is the existing doctor-smoke (`e2e.yml:126`).
- The guard's live-CLI-set derivation is static (`sed` over `cli/actools`, one level). A future dynamically-computed `source` of a command file would not be derived — but it would also be a new wiring pattern the Review Gate of that phase must extend the builder for (the missing-target arm fails loudly on half-wired states).

### Blockers

None.

### Review Gate decision

Pending — a separate session verifies, in order: (1) `doctor.sh` sources the module and the local def is gone (grep proofs); (2) the resolved `db_exec_root` is byte-identical to `core.sh` (the focused test's `declare -f` arm; the deleted local def re-verified byte-identical to the authority against the baseline); (3) the live-CLI-path guard **bites** (permanent fixture arms + the captured live demo); (4) drift 6/6 + cron 3/3; (5) the eight dead twins untouched; (6) the doctor-smoke passes (branch e2e dispatch recommended, not gating — this is not a behavior change, so there is **no new e2e gate**). The `|| true` deviation is flagged for explicit confirmation. **APPROVE on green.**

### Next safe task

**P0-O — delete the eight dead twins** (deadness already proven: `cmd_*` called 0× in `cli/actools`) + the doc-authority lock.

### Forbidden next scope

No wiring of any dead twin (the guard's missing-target and definition arms both bite); no edits to `modules/db/core.sh` or the P0-M contracts/guards without an explicit release note; no generated-file change; `main()`'s hardcoded profile source stays until P0-P.

---


## Entry 018 — P0-M · Stateful DB Layer Extraction (tests-first) + `wait_db` Hardening

Date: 2026-06-12
Branch: `phase0/P0-M-db-layer-extraction` (operator records the applied branch + `main` SHA)
Commit SHA: five implementation commits + one docs commit (sandbox sequence: `f8830bf` contract/mock tests → `37bf3cd` guard extension → `7b5347a` extraction → `496ca42` orphan retirement + twin-ban hardening → `e9471ce` `wait_db` hardening → docs). **Merged to `main` as `cd0d0d9` (PR #47)** — *stamped at P0-N ratification, 2026-06-12.*
Actor / Claude session (model): Coding Window
Phase: P0-M — Stateful DB Layer Extraction (tests-first) + `wait_db` Hardening
Task prompt source: `P0-M-db-layer-extraction.md` + coding-window prompt (filled)

### Objective

Pin the inline DB layer with contract/mock tests, extract the six DB functions **verbatim** from `actools.sh` into `modules/db/core.sh` (retiring the stale v9.2 `modules/db/*` twins and extending the duplicate-function guard to cover the six names), then harden `wait_db`'s readiness probe so the DB **root** password is no longer passed on argv — closing the Entry-017 `wait_db:510` known risk — with **no install-behavior change except that one isolated, e2e-gated security fix**. The authority rule held throughout: the live inline v14 code was copied; the stale twins' content (a divergent `check_db_creds` error message, a `wait_db` with `cd || exit`) did **not** survive.

### Contract/mock tests (commit 1; CI-gated by the existing recursive bats job — no `lint.yml` edit needed)

The layer is **stateful** (every function execs against a live MariaDB container), so there is no rendered output to golden-capture. Behavior is pinned instead by `tests/db/db_contract_test.bats` (13 tests) over a mock `docker` interposed on PATH (`tests/db/mock_docker.bash`: NUL-separated argv capture per invocation — the `sh -c` bodies contain newlines — stdin capture, and fail-N-then-succeed / fixed-rc knobs). Pinned contracts: `db_exec_root` → `docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ …` (password from container env, never on host argv; heredoc stdin reaches the client); `db_exec_root_stdin` → same shape with `"$1"` as the positional target database, SQL piped; `db_dump_container` → the umask-077 `--defaults-extra-file` dump inside the container, `[mariadb-dump]`/user/password fed over stdin, dump args passed through, password on **no** argv; `setup_backup_db_user` → `wait_db` **first**, then the exact least-privilege SQL (`CREATE USER IF NOT EXISTS 'backup'@'%' …; GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* …; FLUSH PRIVILEGES;`); `wait_db` → polls the `mysql.actools_write_check` readiness probe (the v9.2-fix4 write-check — the spec's "poll until the DB answers" is THIS statement, pinned verbatim) until success then returns 0, bounded give-up via `error` at exactly 50 tries / `sleep 3`; `check_db_creds` → the `SELECT 1` probe through `db_exec_root`, `error "Cannot authenticate…"` on rejection. The loader (`tests/db/db_layer_loader.bash`) auto-locates the live layer — inline pre-extraction, the module after — so the **same assertions running green across the move is the faithfulness proof** (the P0-L `capture_backup_cron.sh` pattern, adapted for a stateful unit).

### Guard extension (commit 2) + twin-ban hardening (commit 4)

- `tests/guards/duplicate_function_guard_test.bats` now also covers the six DB names (`DB_RISKY_FUNCTIONS`, merged into `ALL_RISKY_FUNCTIONS`): the closure exactly-once arm iterates all sixteen names; the wired-twin arm scans sourced `modules/db/*.sh` alongside sourced `core/*.sh`. **Non-vacuity proven live (commit-2 state, output verbatim in the test report):** wiring `modules/db/wait.sh` into `actools.sh` while the inline `wait_db` existed failed arm 1 (`wait_db: defined 2x on the live path [actools.sh(x1) modules/db/wait.sh(x1)]`) and arm 2 (named wrong wiring); reverted byte-identical (sha-verified).
- The **unconditional twin ban** (arm 3) was extended to `modules/db/*.sh` in commit 4 — the P0-K sequencing: unsatisfiable while the stale twins existed, enabled by their retirement. **End-state non-vacuity (output verbatim in the test report):** a reintroduced inline `wait_db(){ :; }` failed **all three arms** including the twin ban; reverted byte-identical.

### Extraction (commit 3; function bodies verbatim — per-function byte-identity verified)

- The six functions → **`modules/db/core.sh`** (live module, `LIVE AUTHORITY (P0-M)` header documenting required globals — `INSTALL_DIR`, `DB_ROOT_PASS` — and collaborators `log`/`error` (core/bootstrap.sh); functions only, inert under `set -u`). The module carries `actools.sh`'s `:450-530` region (the four section banners + doc comments + six definitions) byte-for-byte; byte-identity proof: `diff` of each function's text (the P0-K `extract_inline_fn` primitive) pre- vs post-extraction — all six identical.
- `actools.sh` 763 → 690 lines: the inline region (`:450-530`) replaced by a retained DB LAYER banner + `source "${INSTALL_DIR}/modules/db/core.sh" || error …` at the exact spot the definitions occupied. The call sites (`:446` `setup_backup_db_user`; the pre-extraction `:490,:560` `wait_db`; `:708,:734` `check_db_creds` — now shifted by −73 where below the region) are **byte-untouched**; only the definitions moved.
- `tests/helpers/capture_golden_outputs.sh` — the `setup_cli` line canary only (`SC_START/SC_END` 594-609 → 521-536; the helper's own documented maintenance step — capture logic untouched, no fixture modified).
- The new module is on the live source-closure (live-authority guard green with its `LIVE AUTHORITY` marker); the contract suite re-ran green against the module with zero assertion edits (loader origin flipped inline → module).

### Orphan purge (commit 4)

- **`modules/db/backup_user.sh`, `modules/db/credentials.sh`, `modules/db/wait.sh` deleted** (stale v9.2 twins; unwired — sourced/copied/executed by nothing, verified before deletion; their divergent content did not survive). Grep proof: `grep -rn "modules/db/backup_user.sh\|modules/db/credentials.sh\|modules/db/wait.sh" . --include='*.sh' --include='*.yml' --include='*.bats'` → **no references** (guard/module comments describe the retirement without the literal paths so the proof grep stays empty — the P0-L convention). `modules/db/core.sh` keeps `lint.yml`'s `modules/db/*.sh` shellcheck glob non-empty — no workflow edit.

### `wait_db` hardening (commit 5 — the one intentional behavior change, isolated and droppable)

- **Before** (`actools.sh:510` pre-extraction; v9.2-fix4): `docker compose exec -T db mariadb -uroot -p"${_wp}" -e "<write-check>"` — the DB root password on argv inside the container, visible to every local user via `ps`.
- **After** (`modules/db/core.sh::wait_db`): `printf '%s\n' '[client]' 'user=root' "password=${_wp}" | docker compose exec -T db sh -c '<umask 077; t=$(mktemp /tmp/actools-wait.XXXXXX.cnf); trap rm EXIT; cat > $t; mariadb --defaults-extra-file="$t" "$@">' _ -e "<write-check>"` — the backup-cron pattern: the password is fed by the printf **builtin** (no host process carries it on argv either), lands in a **umask-077** temp defaults file **inside the container**, and is removed on exit. The probe SQL, the 50×3s bounds, the `_wp` local (the v9.2-fix4 `set -u` rationale — expansion in the current shell, no spawned subshell) and the log/error lines are **unchanged**.
- **Security test:** `tests/guards/wait_db_security_guard_test.bats` (4 arms): (1) the live `wait_db` source MUST carry `--defaults-extra-file=` + `umask 077` (executable text only — a comment cannot vacuously satisfy it); (2) MUST NOT carry any argv-password form (`-p"…"`/`-p'…'`/`-p$…`/`--password=`; comment lines stripped — the in-function comment legitimately *describes* the retired form); (3) **permanent non-vacuity arm**: a doctored copy re-introducing the retired `-p"${_wp}"` probe MUST FAIL the same oracle (self-checks the doctoring took); (4) behavioral: the live `wait_db` run against the mock puts the password on **no** host argv — it travels only on the client's stdin — and still issues the unchanged write-check. **Non-vacuity additionally proven live** (output verbatim in the test report): injecting the argv probe into the live module failed security arms 1/2/4 **and** the `wait_db` contract test; reverted byte-identical (sha == the hardening commit).
- **Outcome equivalence (local, mock):** old vs new `wait_db` run against identical mock scenarios (immediate success / fail-3-then-succeed / always-fail) produced **identical** rc, attempt counts (1/4/50), nap counts (0/3/49) and log/error lines. **Container-side mechanics proven** under real `sh` with a fake `mariadb`: the defaults file is created mode **600**, holds the stdin-fed `[client]` credentials, the `-e <SQL>` args pass through `"$@"`, and the temp file is removed on exit.
- **e2e gate — PENDING CI (flagged, not guessed):** the real-install e2e (`e2e.yml`, Hetzner VM) cannot run in the coding sandbox (no docker daemon / cloud token). The hardening is therefore shipped as the **isolated final implementation commit**: if the CI e2e does not reach DB-ready, the operator drops/reverts that one commit (steps 1–4 stand alone) per the spec's split rule. The Review Gate must confirm the e2e before Approve.

### Files changed

- `modules/db/core.sh` — **new live module**: `LIVE AUTHORITY (P0-M)` header + the verbatim six functions (then the isolated `wait_db` hardening in commit 5)
- `actools.sh` — 763 → 690 lines: inline region `:450-530` → banner + `source` line (nothing else)
- `modules/db/backup_user.sh`, `modules/db/credentials.sh`, `modules/db/wait.sh` — **deleted**
- `tests/db/db_layer_loader.bash`, `tests/db/mock_docker.bash`, `tests/db/db_contract_test.bats` (new, 13)
- `tests/guards/duplicate_function_guard_test.bats` — extended to the six DB names (all three arms)
- `tests/guards/wait_db_security_guard_test.bats` (new, 4)
- `tests/helpers/capture_golden_outputs.sh` — `setup_cli` canary 594-609 → 521-536 only
- Docs: this ledger, `runtime-authority-map.md`, `docs/CHANGELOG.md`, `docs/releases/P0-M-db-layer-extraction.md`, `docs/tests/P0-M-db-layer-extraction.md`, `docs/runbooks/HANDOFF-P0-M.md`

### Files intentionally not changed

- `install_env` (its inline DB-provisioning SQL and the `db_exec_root <<SQL` call sites `:492,:563` pre-shift) and the CLI's own DB helpers (`cli/commands/*`) — **P0-N**
- `main()` (P0-P); all standalone feature orphans (P0-O audit first)
- `.github/workflows/lint.yml` — the recursive bats job auto-discovers `tests/db/` and the new guard; the `modules/db/*.sh` shellcheck glob still matches `modules/db/core.sh`
- Golden fixtures — drift 6/6 + cron fixture with **no fixture modified**
- `ACTOOLS_VERSION` stays `14.0` — the phase-0 convention (the hardening changes the auth *method*, not any generated byte or install outcome)

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| DB access layer (`db_exec_root`/`db_exec_root_stdin`/`db_dump_container`/`setup_backup_db_user`/`wait_db`/`check_db_creds`) | inline `actools.sh:450-530` | `modules/db/core.sh` (**live module**) |
| Stale v9.2 DB twins (`modules/db/{backup_user,credentials,wait}.sh`) | orphans (unwired, divergent content; `wait.sh` carried the argv-password probe) | **deleted** |
| `wait_db` readiness probe auth | root password on argv (`mariadb -uroot -p"…"`, `actools.sh:510`) | umask-077 `--defaults-extra-file` inside the container; **no argv password anywhere** (CI-locked, non-vacuous) |
| DB provisioning SQL in `install_env` | inline `actools.sh` | **unchanged** (inline; P0-N+) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Unchanged | golden drift 6/6 at every commit |
| Caddyfile | Unchanged | golden drift 6/6 |
| my.cnf | Unchanged | golden drift 6/6 |
| Dockerfiles | Unchanged | golden drift 6/6 |
| CLI | Not touched | `cli_authority_test.bats` green in the full suite |
| /etc/cron.daily/actools-backup | Unchanged | cron drift 3/3 (re-render sha == fixture `bdfaa0c6…`) at every commit |

### Tests run

```bash
bash -n actools.sh && bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/db/                                 # 13/13 contract/mock
bats tests/guards/                             # 13/13: dup-fn (3, DB-extended) + wait_db security (4) + cron shape (4) + live-authority/closure (2)
bats tests/generated/                          # 9/9: compose drift 6 + cron 3 — no fixture modified
bats -r tests/                                 # 216/216
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 modules/db/core.sh
shellcheck --exclude=SC2034,SC2015,SC2164,SC2119,SC2120 modules/db/*.sh   # the CI glob — still non-empty
grep -rn "modules/db/backup_user.sh\|modules/db/credentials.sh\|modules/db/wait.sh" . --include='*.sh' --include='*.yml' --include='*.bats'   # no references
```

### Test result

PASS — full suite 216/216 (199 → 216: +13 DB contracts, +4 `wait_db` security); golden drift 6/6 + cron fixture at every commit (no fixture modified); the DB-extended duplicate-function guard non-vacuous (commit-2 wired-twin demo + end-state three-arm demo) and the `wait_db` security test non-vacuous (permanent in-CI arm + live injection demo); old-vs-new `wait_db` outcome-identical across all mock scenarios.

### Documentation updated

- [x] Runtime authority map (new DB-layer row; DB-provisioning row corrected; P0-M test-surface addendum 199 → 216)
- [ ] Generated-file contract — no change needed (no generated output changed)
- [ ] CLI authority contract — untouched
- [ ] Operator target docs — no operator-visible change (install logs identical; only the probe's auth method changed)
- [x] Test plan / test report

### Changelog / release notes

- [x] CHANGELOG.md updated
- [x] Release note added (`docs/releases/P0-M-db-layer-extraction.md`)
- [x] Test report added (`docs/tests/P0-M-db-layer-extraction.md`)
- [x] Review notes — for the Review Gate, see the handoff (`docs/runbooks/HANDOFF-P0-M.md`)

### Known risks

- ~~**The `wait_db` hardening is e2e-gated and the e2e has not run yet**~~ **RESOLVED at P0-N ratification (2026-06-12): the CI e2e confirmed the gate — run #75 reached `MariaDB ready.` on the real install.** *(Original risk text, for the record:)* (sandbox has no docker daemon / cloud credentials). Outcome equivalence is proven at the mock level (identical rc/attempts/logs in all scenarios) and the container-side mechanics under real `sh`, but the authoritative gate is the CI real install reaching DB-ready (`e2e.yml`). The hardening is the **isolated final implementation commit** so it can be dropped without touching steps 1–4 if the e2e fails — the spec's split rule, exercised as a flag rather than a guess.
- The spec's shorthand "poll until the DB answers `SELECT 1`" was interpreted against the authoritative inline code: `wait_db`'s probe is the v9.2-fix4 **write-check** (`CREATE TABLE … actools_write_check; DROP TABLE …`), preserved byte-identically; `SELECT 1` is `check_db_creds`' probe, also pinned. No probe SQL was changed.
- The `setup_cli` canary now reads 521-536; any future edit above `setup_cli` in `actools.sh` must update it (the helper fails loudly with self-describing instructions — the canary working, not breaking).
- The `wait_db` security oracle checks **executable** text (comment lines stripped): a future refactor hiding an argv password inside a string built across lines would evade a static grep — the behavioral arm (mock argv scan) and the contract stdin pin are the backstop.
- Closing Entry-017's known-risk item: **`wait_db:510` argv exposure — CLOSED — e2e-confirmed** *(flipped at P0-N ratification, 2026-06-12: e2e run #75 reached `MariaDB ready.`; the original "subject to the e2e gate" caveat is discharged).*

### Blockers

None.

### Review Gate decision

**APPROVED — ratified at P0-N (2026-06-12): merged to `main` as `cd0d0d9` (PR #47); the e2e gate confirmed (run #75 reached `MariaDB ready.` — the real install hit DB-ready under the hardened probe).** *(Original pending text, for the record:)* a separate session verifies: the extracted functions issue the **same** commands (contracts 13/13 green across the move; per-function byte-identity diffs; the five non-`wait_db` functions byte-identical to the inline originals **after** the hardening commit too); golden drift 6/6 + cron fixture unchanged with no fixture modified; the DB-extended duplicate-function guard **bites** (both captured demos in the test report); the `wait_db` security test **bites** (permanent arm + the live injection demo); `wait_db` uses the secure `--defaults-extra-file` form with **no argv password and still polls** — mock-equivalence is in the test report, and the Review Gate must see the **CI e2e green (real install reaches DB-ready)** before Approve, or direct the operator to split off commit `e9471ce` per the spec; the orphan twins are **gone and unreferenced** (the grep proof); and no behavior changed beyond the `wait_db` hardening (the only `actools.sh` hunk is `:450-530` → the source block).

### Next safe task

**P0-N — `install_env` / CLI extraction** (post-closure track order). Still NOT community-plus feature work.

### Forbidden next scope

No standalone-feature-orphan wiring before P0-O's audit; `main()`'s hardcoded profile source stays until P0-P; no generated-file change; no edit to `modules/db/core.sh` (or its guards/contracts) without an explicit release note; the retired `modules/db` twins must never be restored (the twin ban bites).

---


## Entry 017 — P0-L · Backup-Cron Extraction + Orphan Purge

Date: 2026-06-11
Branch: `phase0/P0-L-backup-cron-extraction` (operator records the applied branch + `main` SHA)
Commit SHA: four implementation commits + one docs commit (sandbox sequence: `24f722e` golden capture → `2e33f66` security-shape guard → `09c5575` extraction → `e6aa398` orphan deletion → docs)
Actor / Claude session (model): Coding Window
Phase: P0-L — Backup-Cron Extraction + Orphan Purge
Task prompt source: `P0-L-backup-cron-extraction.md` + coding-window prompt (filled)

> Numbering note: Entry 016's "Next safe task" line predicted "P0-L — DB layer
> extraction". The post-closure plan renumbered: P0-L is the backup-cron phase
> (this entry, per the `P0-L-backup-cron-extraction.md` spec); the DB layer /
> `install_env` / CLI extractions are P0-M / P0-N. The spec governs.

### Objective

Lock the secure backup-cron shape behind a golden capture and a security guard, extract the inline `setup_backup_cron` generator **verbatim** from `actools.sh` into `modules/backup/cron.sh`, and delete the insecure orphan `cron/backup.sh` — with **no change to the generated cron's bytes**. The security rule held throughout: the live inline generator (umask-077 temp defaults file inside the container, `mariadb-dump --defaults-extra-file="$t"`, password read from `.actools-state.json` at cron runtime — never on argv, never baked into the script) is authoritative; the orphan's argv-password form (`-ubackup -p"${BACKUP_PASS}"`, visible in `ps`) was deleted, never adopted.

### Capture + guard (commits 1–2; CI-gated by the existing recursive bats job — no `lint.yml` edit needed)

- **Backup-cron golden capture** — `tests/helpers/capture_backup_cron.sh` renders the LIVE `setup_backup_cron` (locates `modules/backup/cron.sh` post-extraction, the inline `actools.sh` block before it — the same renderer across the move is the faithfulness proof) under fixed deterministic inputs (`INSTALL_DIR=/opt/actools-golden`, `ENVIRONMENTS=prod`, S3 defaults explicit: `true`/`""`/`""`/`aws`, retention 7, rclone empty). It **pins** the real install target (`cat > /etc/cron.daily/actools-backup <<BACKUP` + `chmod +x`) and substitutes ONLY the output location in its in-memory copy — the heredoc bytes and every render-time expansion are untouched; no repo file is modified at render. Fixture: `tests/fixtures/golden/backup-cron/{actools-backup,SHA256SUMS}` (sha `bdfaa0c6…`); **no secret baked** (the password is fetched from state at cron runtime — pinned by a test). Drift test: `tests/generated/backup_cron_drift_test.bats` (3 tests: byte-compare re-render, manifest self-consistency, no-secret pin). Render proven deterministic against a hostile ambient env (exported `ENABLE_S3_STORAGE=false`/`BACKUP_RETENTION_DAYS=30`/`RCLONE_REMOTE=junk`/`ENVIRONMENTS=dev,stg` → identical sha).
- **Cron security-shape guard** — `tests/guards/cron_security_shape_guard_test.bats`, four arms: (1) the rendered cron MUST contain `mariadb-dump --defaults-extra-file=`; (2) the rendered cron MUST NOT carry any argv-password form (`-p"…"`/`-p'…'`/`-p$…`/`--password=`) and MUST read `backup_user_pass` from state at runtime; (3) **permanent non-vacuity arm**: a doctored copy of the live generator re-introducing the orphan's `-ubackup -p"$BK"` invocation is rendered through the SAME pipeline and the same oracle must FAIL it (the arm also self-checks that the doctoring took); (4) the generator SOURCE carries the secure `umask 077` heredoc and no argv-password text. **Non-vacuity additionally proven live** (outputs verbatim in the test report): injecting the orphan form into `actools.sh` failed guard arms 1/2/4 **and** the new cron drift test (the diff showing the insecure rendered line); reverted byte-identical, all green.

### Extraction (commit 3; function body verbatim — per-function byte-identity verified twice)

- `setup_backup_cron` → **`modules/backup/cron.sh`** (live module, `LIVE AUTHORITY (P0-L)` header documenting required globals — `INSTALL_DIR`, `ENVIRONMENTS`, the S3/retention/rclone optionals — and collaborators `section`/`log` (core/bootstrap.sh), `get_backup_pass` (core/secrets.sh); functions only, inert under `set -u`). Byte-identity proof: `diff` of the extracted function text (via the P0-K `extract_inline_fn` brace-counting primitive, verified heredoc-safe against the raw line range) against the pre-extraction inline block — identical; and the re-rendered cron sha matches the fixture captured from the inline generator (`bdfaa0c6…`).
- `actools.sh` 835 → 763 lines: the inline block (`:584-661`) replaced by `source "${INSTALL_DIR}/modules/backup/cron.sh" || error …` at the exact spot the function occupied (P0-K source-line style; the DAILY BACKUP CRON section banner retained). The `main()` call site, the spine, and everything else untouched.
- `tests/helpers/capture_golden_outputs.sh` — the `setup_cli` line canary only (`SC_START/SC_END` 666-681 → 594-609; the helper's own documented maintenance step — capture logic untouched, no fixture modified).
- The new module is on the live source-closure (live-authority guard green with its `LIVE AUTHORITY` marker); `setup_backup_cron` is not among the ten duplicate-guard names, but the capture helper itself hard-fails on a dual definition (module + inline) as belt-and-braces.

### Orphan purge (commit 4)

- **`cron/backup.sh` deleted.** Its `:27` `-ubackup -p"${BACKUP_PASS}"` put the DB password on argv. It was unwired (sourced/copied/executed by nothing — verified before deletion). Grep proof: `grep -rn "cron/backup.sh" . --include='*.sh' --include='*.yml' --include='*.bats'` → **no references** (module/guard comments describe the retirement without the literal path so the proof grep stays empty). `cron/stats.sh` remains, so `lint.yml`'s `cron/*.sh` shellcheck glob stays non-empty — no workflow edit.
- `ROADMAP.md:29` — one-line doc-truth correction of the parenthetical made false by the deletion ("the `cron/backup.sh` file in the repo is an unwired duplicate" — the file no longer exists). ROADMAP was not on the phase's allowed-files list; the edit is deliberate, minimal, and flagged here for the Review Gate.

### The other heredocs — untouched (forbidden scope held)

The `db_exec_root <<SQL` DB-user heredocs (now `actools.sh:492,563`) and the help/version `<<EOF` (`:59`) are unchanged; no DB-layer / `install_env` / CLI extraction (P0-M/P0-N); no feature-orphan wiring; `main()` untouched (P0-P).

### Files changed

- `modules/backup/cron.sh` — **new live module**: `LIVE AUTHORITY (P0-L)` header + the verbatim `setup_backup_cron`
- `actools.sh` — 835 → 763 lines: inline block → `source` line (only the `setup_backup_cron` block; nothing else)
- `cron/backup.sh` — **deleted**
- `tests/helpers/capture_backup_cron.sh` (new), `tests/generated/backup_cron_drift_test.bats` (new, 3), `tests/fixtures/golden/backup-cron/{actools-backup,SHA256SUMS}` (new fixture), `tests/guards/cron_security_shape_guard_test.bats` (new, 4)
- `tests/helpers/capture_golden_outputs.sh` — `setup_cli` canary 666-681 → 594-609 only
- `ROADMAP.md` — the one-line orphan-parenthetical correction (flagged above)
- Docs: this ledger, `runtime-authority-map.md`, `CHANGELOG.md`, `docs/releases/P0-L-backup-cron-extraction.md`, `docs/tests/P0-L-backup-cron-extraction.md`, `docs/runbooks/HANDOFF-P0-L.md`

### Files intentionally not changed

- The `db_exec_root <<SQL` heredocs and the help/version `<<EOF` (out of scope; small, idiomatic)
- DB layer / `install_env` / CLI (P0-M / P0-N); `main()`'s hardcoded profile source (P0-P); all standalone feature orphans incl. the rest of `modules/backup/*` (P0-O audit first)
- `.github/workflows/lint.yml` — the recursive bats job auto-discovers the new suites; the `cron/*.sh` shellcheck glob still matches `cron/stats.sh`
- Golden compose fixtures — drift 6/6 with **no fixture modified**
- `ACTOOLS_VERSION` stays `14.0` — no behavior change

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Backup-cron generator (`setup_backup_cron`) | inline `actools.sh:584-661` | `modules/backup/cron.sh` (**live module**) |
| Insecure orphan backup cron (`cron/backup.sh`) | orphan (unwired, argv-password) | **deleted** |
| Generated `/etc/cron.daily/actools-backup` | inline heredoc output | **byte-identical** (golden capture `bdfaa0c6…`) |
| Cron security shape | convention only | **CI-locked** (security-shape guard, non-vacuous) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Unchanged | golden drift 6/6 at every commit |
| Caddyfile | Unchanged | golden drift 6/6 |
| my.cnf | Unchanged | golden drift 6/6 |
| Dockerfiles | Unchanged | golden drift 6/6 |
| CLI | Not touched | `cli_authority_test.bats` green in the full suite |
| /etc/cron.daily/actools-backup | Unchanged | new cron golden capture: re-render sha == fixture sha (`bdfaa0c6…`) at every commit since capture |

### Tests run

```bash
bash -n actools.sh && bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/generated/                          # 9/9: cron capture (3) + compose drift (6)
bats tests/guards/                             # 9/9: cron security shape (4, incl. non-vacuity) + P0-K guards (5)
bats -r tests/                                 # 199/199
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 modules/backup/cron.sh
shellcheck --exclude=SC2034,SC2015,SC2164 cron/*.sh
grep -rn "cron/backup.sh" . --include='*.sh' --include='*.yml' --include='*.bats'   # no references
```

### Test result

PASS — full suite 199/199 (192 → 199: +3 cron drift, +4 security-shape guard); golden drift 6/6 at every commit (no fixture modified); the new cron fixture byte-identical across the extraction; the security-shape guard non-vacuous (permanent in-CI arm + live injection demo in the test report).

### Documentation updated

- [x] Runtime authority map (new backup-cron row; P0-L answer; test-surface addendum 192 → 199)
- [ ] Generated-file contract — no change needed (the contract already lists "generated backup/cron/systemd helper files, if present"; the cron now has its golden fixture per that contract)
- [ ] CLI authority contract — untouched
- [ ] Operator target docs — no operator-visible change (the installed cron is byte-identical)
- [x] Test plan / test report

### Changelog / release notes

- [x] CHANGELOG.md updated
- [x] Release note added (`docs/releases/P0-L-backup-cron-extraction.md`)
- [x] Test report added (`docs/tests/P0-L-backup-cron-extraction.md`)
- [x] Review notes — for the Review Gate, see the handoff (`docs/runbooks/HANDOFF-P0-L.md`)

### Known risks

- The `setup_cli` canary in `tests/helpers/capture_golden_outputs.sh` now reads 594-609; any future edit above `setup_cli` in `actools.sh` must update it (the helper fails loudly with self-describing instructions — the canary working, not breaking).
- The cron capture interposes ONLY the output location (`/etc/cron.daily/actools-backup` → sandbox path) in its in-memory copy of the function, after pinning the real target strings; the heredoc bytes are untouched. If a future phase renames the install target, the helper hard-fails with instructions rather than silently capturing the wrong artifact.
- `lint.yml` does not shellcheck `modules/backup/*.sh` (pre-existing — the directory holds unaudited P0-O orphans that predate this phase). The new `modules/backup/cron.sh` is shellcheck-clean locally (command above) and behavior-gated by three bats suites; adding the directory to CI shellcheck belongs to the P0-O orphan audit.
- **Pre-existing argv exposure, out of scope (P0-M candidate):** `wait_db()` (`actools.sh:510`, v9.2-fix4) probes readiness with `mariadb -uroot -p"${_wp}"` — the DB root password on argv inside the `docker compose exec`. Unchanged since before this phase (P0-L's only `actools.sh` hunk is `:584-661`); hardening it is a behavior change belonging to the DB-layer extraction. The **backup** password is on argv nowhere.
- `ROADMAP.md` one-line correction is outside the spec's allowed-files list (see Orphan purge above) — deliberate doc-truth fix for a claim the deletion falsified; Review Gate to confirm or revert.

### Blockers

None.

### Review Gate decision

Pending — a separate session verifies: the generated cron is **byte-identical** (re-render sha == fixture sha `bdfaa0c6…`; the fixture was captured from the pre-extraction inline generator and the renderer now sources the module); the security guard **bites** (the in-CI non-vacuity arm + the live injection demo in `docs/tests/P0-L-backup-cron-extraction.md`); the orphan is **gone and unreferenced** (the grep proof); golden drift 6/6 with no fixture modified; the other heredocs (`:492,563` SQL — now at those lines post-shift — and the help/version `<<EOF`) byte-unchanged; and no argv-password form exists anywhere on the **backup path** (the generated cron, `modules/backup/cron.sh`, `cli/actools` backup, `cli/commands/update.sh` — all `--defaults-extra-file`). NOTE for the sweep: the pre-existing `wait_db()` readiness probe (`actools.sh:510`, v9.2-fix4) passes the DB **root** password on argv — byte-identical to baseline, outside P0-L scope, flagged below as a P0-M candidate.

### Next safe task

**P0-M — DB layer extraction** (post-closure track, per the renumbered plan). Still NOT community-plus feature work.

### Forbidden next scope

No `install_env`/CLI extraction before its own phase (P0-M/P0-N split per the phase files); no standalone-feature-orphan wiring before P0-O's audit; `main()`'s hardcoded profile source stays until P0-P; no generated-file change; no edit to the backup-cron module or its fixture without an explicit re-capture + release note.

---


## Entry 016 — P0-K · Guards + Stateless Core Extraction

Date: 2026-06-11
Branch: `phase0/P0-K-guards-stateless-core` (operator records the applied branch + `main` SHA)
Commit SHA: six implementation commits + one docs commit (sandbox sequence: `11ea38d` guards → `c8e32b7` behavior capture → `3efc1d5` bootstrap → `6200979` state → `0f012c5` secrets → `9018a0c` validate + guard hardening → docs)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-K — Guards + Stateless Core Extraction
Task prompt source: `P0-K-guard-and-stateless-extraction.md` + coding-window prompt (filled)

### Objective

Install two anti-regression CI guards, then extract the stateless core — bootstrap, state, secrets, validate — from the live inline v14 code in `actools.sh` into `core/*.sh` modules, retiring the stale v9.2 orphan twins, with **zero install-behavior change** (golden drift 6/6 at every commit). The authority rule held throughout: when in doubt, copy from `actools.sh`, never from the orphans.

### Guards (commit 1; CI-gated by the existing recursive bats job — no `lint.yml` edit needed)

- **Live-authority guard** (`tests/guards/live_authority_guard_test.bats`) — every file declaring the P0-G `LIVE AUTHORITY` marker must be on the live install path (the transitive source-closure of `actools.sh`, computed by `tests/guards/live_closure.bash`: static + loop-expanded `${INSTALL_DIR}`-anchored sources; resolves the known 20-file path, now 24 with the core modules). Catches authoritative-looking orphans — the Entry-015 failure mode.
- **Duplicate-function guard** (`tests/guards/duplicate_function_guard_test.bats`) — each of the ten risky names (`validate_env rand_pass gen_if_empty init_state set_state get_state is_installed mark_installed get_db_pass get_backup_pass`) must be defined **exactly once** on the live path; an explicit second arm names the exact regression (inline + sourced-core dual = the wrong wiring the Entry-015 review rejected, which would flip `ENABLE_S3_STORAGE` off). **Hardened in the final commit** with an unconditional twin ban (never in both `actools.sh` and any `core/*.sh`, sourced or not) — satisfiable only once the stale twins were retired, which is why it lands at 6/6 rather than 1/6.
- **Non-vacuity proven three times** (outputs verbatim in the test report): an orphan claiming authority fails guard 1; wiring `core/validate.sh` while inline `validate_env` exists fails both arms of guard 2; a reintroduced inline `validate_env(){ :; }` at end-state fails all three arms including the twin ban.

### Extractions (one unit per commit; every function body verbatim — per-function byte-identity to the inline block verified with the test extractor)

- **bootstrap → `core/bootstrap.sh`** (`log warn error section dryrun`; the `DRY_RUN=false` / dry-run flip stays inline — spine state, not unit functions). The orphan's `INSTALL_DIR="$REAL_HOME"`, `$REAL_HOME`-anchored `ENV_FILE`/`STATE_FILE`/`LOG_*`, `ACTOOLS_VERSION="9.2"`, and its own lock/exec-redirect logic did **not** survive.
- **state → `core/state.sh`** (`init_state set_state get_state is_installed mark_installed`). jq/state-file semantics unchanged (atomic tmp+mv, literal `"null"`, `INSTALL_DIR`-anchored `STATE_FILE`). The orphan's `get_db_pass`/`get_backup_pass` twins did **not** survive here — they belong to the secrets unit.
- **secrets → `core/secrets.sh`** (`rand_pass gen_if_empty get_db_pass get_backup_pass`). The top-level secret flow stays inline in its original order — `gen_if_empty DB_ROOT_PASS` / `DRUPAL_ADMIN_PASS`, then the v9.2-fix7 writeback loop (**secret-writeback order unchanged**). The orphan's `writeback_secrets()` twin did **not** survive.
- **validate → `core/validate.sh`** (`validate_env` only). The S3 gate stays **top-level inline** with the v14 default `${ENABLE_S3_STORAGE:-true}` (4 occurrences in `actools.sh`, zero `:-false` anywhere), as do provider auto-detection and the XeLaTeX/env-mode/disk checks. The orphan's `validate_s3` (`:-false`), `detect_s3_provider`, `validate_xelatex`, `validate_environment_mode`, `validate_disk` twins did **not** survive.

Each module carries a `LIVE AUTHORITY (P0-K)` header documenting its required globals/collaborators (`set -u` handled: function definitions only, no module-level variable reads or assignments).

### Files changed

- `core/bootstrap.sh`, `core/state.sh`, `core/secrets.sh`, `core/validate.sh` — overwritten with the live v14 implementations (stale v9.2 content retired in full)
- `actools.sh` — 871 → 835 lines: the four inline definition blocks replaced by four `source "${INSTALL_DIR}/core/<x>.sh"` lines at the exact spots the definitions occupied; all calls, top-level spine code, and `main()` untouched
- `tests/guards/live_closure.bash`, `tests/guards/live_authority_guard_test.bats`, `tests/guards/duplicate_function_guard_test.bats` — new
- `tests/core/extract_inline.bash` (new), `tests/core/bootstrap_test.bats` (new, 12), `tests/core/state_test.bats` (new, 10), `tests/core/secrets_test.bats` (rewritten, 17), `tests/core/validate_test.bats` (rewritten, 11) — behavior captured against the inline code at commit 2, re-pointed at each live module in its extraction commit (same assertions = faithfulness proof); orphan-content ban statics added per unit
- `tests/helpers/capture_golden_outputs.sh` — the `setup_cli` line canary only (`SC_START/SC_END` 702-717 → 666-681 across the four extractions; the helper's own documented maintenance step — capture logic untouched, no fixture modified)
- Docs: this ledger, `runtime-authority-map.md`, `CHANGELOG.md`, `docs/releases/P0-K-guards-and-stateless-core.md`, `docs/tests/P0-K-guards-and-stateless-core.md`, `docs/runbooks/HANDOFF-P0-K.md`

### Files intentionally not changed

- `main()`'s hardcoded `source profiles/community.profile` (P0-P scope)
- DB layer / `install_env` / cron / CLI (P0-L / P0-M / P0-N scope)
- All standalone feature orphans (P0-O audit first)
- `.github/workflows/lint.yml` — the recursive bats job auto-discovers `tests/guards/`, so the guards are CI-gated with zero workflow edit
- Golden fixtures — drift 6/6 with **no fixture modified**
- `ACTOOLS_VERSION` stays `14.0` — this phase allows no behavior change

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Bootstrap helpers (log/warn/error/section/dryrun) | inline `actools.sh` | `core/bootstrap.sh` (**live module**) |
| State (init/set/get/is_installed/mark_installed) | inline `actools.sh` | `core/state.sh` (**live module**) |
| Secrets (rand_pass/gen_if_empty/get_db_pass/get_backup_pass) | inline `actools.sh` | `core/secrets.sh` (**live module**) |
| Validation (validate_env) | inline `actools.sh` | `core/validate.sh` (**live module**) |
| Path semantics, S3 gate, secret flow order, spine | inline `actools.sh` | **unchanged** (inline) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Unchanged | golden drift 6/6 at every commit |
| Caddyfile | Unchanged | golden drift 6/6 |
| my.cnf | Unchanged | golden drift 6/6 |
| Dockerfiles | Unchanged | golden drift 6/6 |
| CLI | Not touched | `cli_authority_test.bats` green in the full suite |

### Tests run

```bash
bash -n actools.sh && bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/core/                              # 50/50 against the live modules + inline spine
bats tests/guards/                            # 5/5 (both guards incl. the twin-ban arm)
bats tests/generated/golden_drift_test.bats   # 6/6
bats -r tests/                                # 192/192
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 core/*.sh
```

### Test result

PASS — full suite 192/192 (158 → 192: +5 guard tests; `tests/core/*` rebuilt 21 → 50); golden drift 6/6 at each of the six commits; both guards non-vacuous (three captured failure demos).

### Documentation updated

- [x] Runtime authority map (Bootstrap row reworked; new stateless-core row; P0-K answer; test-surface addendum)
- [ ] Generated-file contract — no change needed (no generated output changed)
- [ ] CLI authority contract — untouched
- [ ] Operator target docs — no operator-visible change
- [x] Test plan / test report

### Changelog / release notes

- [x] CHANGELOG.md updated
- [x] Release note added (`docs/releases/P0-K-guards-and-stateless-core.md`)
- [x] Test report added (`docs/tests/P0-K-guards-and-stateless-core.md`)
- [x] Review notes — for the Review Gate, see the handoff (`docs/runbooks/HANDOFF-P0-K.md`)

### Known risks

- The `setup_cli` line canary in the capture helper now reads 666–681; any future edit above `setup_cli` in `actools.sh` must update it. The helper fails loudly with self-describing instructions — that is the canary working, not breaking.
- The closure builder expands `${INSTALL_DIR}`-anchored static sources and single-level `for`-loop interpolations — the only live patterns. A future exotic sourcing pattern would need a builder extension; the closure-sanity test pins the known path shape so silent under-resolution fails CI instead of passing vacuously.

### Blockers

None.

### Review Gate decision

Pending — a separate session verifies: golden drift held 6/6; both guards bite (three non-vacuity demos in the test report); each extracted module matches inline behavior — **especially the S3 default** (`:-true` ×4 in `actools.sh`, `:-false` ×0 anywhere on the live path) **and path semantics** (`INSTALL_DIR` BASH_SOURCE-relative; `ENV_FILE`/`STATE_FILE` INSTALL_DIR-anchored); and no stale orphan content survived (orphan-ban statics in `tests/core/*`).

### Next safe task

**P0-L — DB layer extraction** (post-closure track order). Still NOT community-plus feature work.

### Forbidden next scope

No `install_env`/cron/CLI extraction before P0-M/P0-N; no standalone-feature-orphan wiring before P0-O's audit; `main()`'s hardcoded profile source stays until P0-P; no generated-file change.

---


## Entry 015 — P0-J · Closure Review + Documentation Truth Pass

Date: 2026-06-11
Branch: `phase0/P0-J-doc-closure` (+ direct doc commits to `main`)
Commit SHA: (operator records the P0-J doc-closure commit on `main`; prior doc commits `1404fc3` / `f7dbac1` / `112c845` — command-reference / enterprise / privacy)
Actor / Claude session (model): Review Gate (Opus) + Conductor
Phase: P0-J — Phase 0 closure review

### Objective

Render the Phase 0 closure decision and correct the documentation falsehoods the review surfaced, so the operator docs match the code before unlocking the post-closure track. No runtime change.

### Closure review outcome

Three-way external review (Closure Report, executed 158/158; ChatGPT; Gemini) plus independent verification. The architecture is sound; every blocker was documentation, not runtime: phantom operator commands taught across the docs; the two-CLI problem described as unsolved though P0-F resolved it; stale architecture counts; orphan modules described as live. Gemini's inverted recommendation (wire the orphan `core/*.sh`; treat `cron/backup.sh` as safe) was rejected on the evidence (it would flip `ENABLE_S3_STORAGE` off and deploy an argv-password cron). Verdict: **Needs Revision (doc-only)** -> **Approved** after the doc-truth pass below.

### Documentation truth pass (12 files)

- Phantom/experimental command relabeling: `command-reference`, `advanced`, `enterprise`, `privacy`, `hardening`, `README` — `gdpr` / `immortalize` / `resurrect` / `ai` / `branch` / `ci` / `cost-optimize` and `migrate --point-in-time` relabeled experimental/not-wired or removed (none has a branch in `cli/actools`).
- CLI authority: `ROADMAP` + `operations` rewritten — single canonical `cli/actools`, copied by `setup_cli()` (`actools.sh:702-717`); heredoc generator removed; `cli_authority_test.bats` enforces no-heredoc.
- Architecture: 76 -> 158 tests; observability/grafana marked optional-not-default; RBAC / per-invocation-logging marked planned-tier; directory tree annotated experimental/orphan + pointer to `runtime-authority-map.md`.
- Backup: `ROADMAP` `cron/backup.sh` misattribution corrected (the basic gzip cron is generated inline; the file is an unwired duplicate).
- Observability: nonexistent `modules/observability/alerts.yml` noted absent.
- Profiles: `test.profile` noted CI-only.
- CHANGELOG: v10.x "Phase 1 complete / 32 modules" + `migrate` / `cost-optimize` disclaimed historical-not-current (history kept).
Deferred (recorded, not done here): orphan module "Extracted v9.2" headers and the broad stale-content reconcile -> **P0-O**.

### Test result

Doc-only; CI green on the push (lint + e2e). No runtime change; golden drift unaffected.

### Review Gate decision

**APPROVED** — Phase 0 closure conditions met. Decision recorded in `docs/runbooks/PHASE0_UNLOCK_MEMO.md` (**GO**; post-closure track P0-K unlocked).

### Next safe task

Post-closure track **P0-K** (guards + stateless core extraction). NOT "Phase 1" (term retired). community-plus feature work gated behind P0-K…P0-P.

### Forbidden next scope

No runtime behavior change outside the per-phase allowed files; no wiring of standalone feature orphans before P0-O's audit; do not adopt stale orphan content (the inline v14 code is authoritative).

---


## Entry 014 — P0-I · Fake-Profile End-to-End + CI Hardening

Date: 2026-06-10
Branch: `phase0/P0-I-fake-profile-e2e`
Commit SHA: `457f3b4` (merged via #44)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-I — Fake-profile end-to-end + CI hardening
Task prompt source: `P0-I-fake-profile-e2e.md` + coding-window prompt (filled, archived)

### Objective

Deliver the end-to-end test the acceptance criteria require (acceptance #8/#9 and
LOCKED §11 build-trigger #1: "e2e with a **fake downstream profile**", "fake
profile exercises **every dispatch point**") and close the two CI gaps the
authority map flagged as P0-I scope (`actools.sh` never shellchecked; `e2e.yml`
install never driven through a non-default profile). Add tests and CI only — no
runtime change, `community` byte-identical.

### Scope decision (this phase)

The window surfaced a real tension between the spec (§S2: "add the
fake-downstream-profile e2e to `e2e.yml`") and the reconciliation note, and
resolved it (Conductor-approved): the e2e is a **hermetic harness for the
dispatch SEAMS** (what Phase 0 hardened), defined **once** as a single bats file
and invoked from **both** workflows — `e2e.yml` (a dedicated hermetic job,
honouring §S2 and keeping the conceptual home) and the `lint.yml` suite (the fast
PR merge gate, free because the e2e is a suite member). Two guarantees, not
duplication; one artifact, so the assertions cannot diverge. A "VM-live"
fake-profile install was rejected because it would force the deferred
install-spine profile selection plus stub handlers that cannot build a working
Drupal. Going hermetic is precisely **why `actools.sh` is not touched** (the
guardrail is honoured by the interpretation, not bypassed).

### Files changed

- **New** `profiles/test.profile` — loadable test-only seam profile; inherits the
  community base via `source "${INSTALL_DIR}/profiles/community.profile"` and
  **appends** with `+=` (passes the append-only stage guard); one extra in every
  profile array (`+seam` stage, `PROFILE_PREFLIGHT_EXTRA=(check missing)`,
  `+section` handoff, `+seam_field` init); `PROFILE_REQUIRES_ACTOR`/`_CHANGE_TICKET=true`.
  `community`'s live install never selects it (selection deferred), so it is inert
  for community operators.
- **New** `tests/test_p0i_fake_profile_e2e.bats` (13 tests) — the single e2e
  artifact (integration test asserting all 10 handler markers + granular per-seam
  tests + failure paths + exec-bit guard + community-routes-through-NONE).
- **New** `tests/fixtures/profiles/test/stage_handlers.sh` (`test_host`…`test_worker`,
  `test_seam`) and `tests/fixtures/profiles/test/commands/seam_feature.sh`
  (generic feature-handler Tier-1 override).
- **Extended** (guarded `ACTOOLS_MARKER_DIR` marker writes; sentinels + exit codes
  preserved) `tests/fixtures/profiles/test/manifest.sh`, `.../commands/doctor_deep.sh`,
  `.../plus_preflight_check.sh`, `.../plus_handoff_section.sh`, `.../plus_doctor_check.sh`.
- `.github/workflows/lint.yml` — bats job → full recursive suite
  (`bats --print-output-on-failure -r tests/`); shellcheck job → `actools.sh`
  added with `--exclude=SC2034,SC2015,SC2164,SC1091` (documented; no `actools.sh`
  edit).
- `.github/workflows/e2e.yml` — install step `tee` exit-masking fixed
  (`pipefail` + `if !`; `install.log` artifact preserved); new hermetic
  `fake-profile-e2e` job invoking the single e2e artifact.
- `tests/test_d0_dispatch.bats` — §4.4 sibling-scope audit preserved; companion
  **resolver-bypass audit** added (LOCKED §10 Risk 2). 48 → 49 tests.

### Files intentionally not changed

- `actools.sh` (flag-don't-edit guardrail; the hermetic e2e needs no change to
  it), `installer/dispatch.sh`, `installer/profile.sh`, `installer/preflight.sh`,
  `installer/handoff.sh`, `installer/init.sh`, `installer/output.sh`,
  `cli/commands/doctor.sh`, `cli/commands/doctor_deep.sh` — all byte-identical.
- All six golden fixtures — unchanged (drift 6/6).
- `profiles/README.md` — out of the allowed scope; `test.profile` is documented in
  the test report + this entry instead.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (none) | — | No authority moved. P0-I adds tests + CI only; the seam, the surfaces, and `actools.sh` are byte-identical. |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Unchanged | golden drift 6/6 |
| Caddyfile | Unchanged | golden drift 6/6 |
| my.cnf | Unchanged | golden drift 6/6 |
| Dockerfiles | Unchanged | golden drift 6/6 |
| CLI | Not touched | `cli/actools` untouched; `cli_authority_test.bats` unchanged |

### Tests run

```bash
bats tests/test_p0i_fake_profile_e2e.bats     # 13/13 (new)
bats tests/test_d0_dispatch.bats              # 49/49 (48 + resolver-bypass audit)
bats tests/generated/golden_drift_test.bats   # 6/6   (community byte-identical)
bats -r tests/                                # 158/158 (whole tree)
bash -n actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh   # clean
```

### Test result

PASS — 158/158 (144 baseline + 13 e2e + 1 resolver-bypass audit); community drift
6/6; `shellcheck actools.sh` clean with documented exclusions; no runtime change.

### Documentation updated

- [x] Runtime authority map (resolver-bypass guard + CI-gap bullets updated; P0-I answer added)
- [ ] Generated-file contract (no change — no generated file touched)
- [ ] CLI authority contract (no change — CLI untouched)
- [ ] Operator target docs (no operator-facing behaviour change)
- [x] Test plan (`docs/tests/P0-I-fake-profile-e2e.md` added)

### Changelog / release notes

- [x] CHANGELOG.md updated
- [x] Release note added (`docs/releases/P0-I-fake-profile-e2e.md`, incl. Rollback)
- [x] Test report added (`docs/tests/P0-I-fake-profile-e2e.md`)
- [x] Handoff added (`docs/runbooks/HANDOFF-P0-I.md`)

### Known risks

- The e2e is hermetic by design (seams, not a live install). The live full-install
  path is covered for `community` by `fresh-install`; a fake-profile *VM* install
  is deliberately out of scope (would need the deferred install-spine selection +
  stub handlers that cannot build a working site).
- Shipping a `test.profile` under `profiles/` is mitigated: it is clearly
  test-only, never selected by the community install, and the only scanner of
  `profiles/*.profile` (the append-only guard) passes it (`+=`).

### Blockers

None.

### Review Gate decision

**APPROVED** — cross-model (Opus) Review Gate session. Verified: golden drift 6/6 (community byte-identical), whole tree 158/158, `shellcheck actools.sh` clean (documented exclusions), exec-bit guard non-vacuous, resolver-bypass audit encodes LOCKED §10 Risk 2, `actools.sh`/surfaces/`community.profile` byte-identical.
Scope decision **RATIFIED**: the hermetic seam-e2e — a single bats artifact invoked from both `e2e.yml` (dedicated job, honours §S2) and `lint.yml` (fast PR gate) — is the correct interpretation of §S2; a VM-live fake-profile install was rightly rejected (it would force the deferred install-spine selection plus stub handlers that cannot build a working Drupal), which is precisely why `actools.sh` is untouched.
Merged at `457f3b4` (#44).

### Next safe task

Phase 0 closure review (LOCKED §11): with P0-I, the build-trigger #1 conditions
("Phase 0 PRs merged, green CI, e2e with a fake downstream profile") are
implemented pending review; confirm green CI on the PR, then proceed to the
closure decision / community-plus Phase-1 unblock evaluation.

### Forbidden next scope

No real community-plus feature work (stubs only); no runtime behaviour change; do
**not** edit `actools.sh` (flag instead); no new `modules/plus_*` live code; do
not modify any golden fixture or `community.profile`.

---

## Entry 013 — P0-H · Profile-Aware init, preflight, doctor, and handoff

Date: 2026-06-10
Branch: `phase0/P0-H-profile-aware-surfaces`
Commit SHA: (operator records the merge SHA at apply time — applied from the supplied diff against `main`)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-H — Profile-aware init, preflight, doctor, and handoff
Task prompt source: `P0-H-profile-aware-surfaces.md` + coding-window prompt (filled, archived)

### Objective

Wire the three remaining operator surfaces (`doctor`, `preflight`, `handoff`)
through the P0-E resolver primitives so a non-default profile can supply
extras, while `community` stays **byte-identical** (its resolvers short-circuit
to empty). `init` was already made profile-aware in P0-E; P0-H only confirms it
and adds a fake-profile init-field test. No resolver code changes — this phase
consumes the seam P0-E built.

### Files changed

- `cli/commands/doctor.sh` — `run_doctor` reworked so the env file and
  `installer/dispatch.sh` are sourced **at the top** (best-effort `|| true`),
  making the resolver available to the deep gate. The `--deep` gate no longer
  hard-sources `doctor_deep.sh`; it resolves via
  `actools::dispatch::resolve_feature_handler doctor_deep` (guarded by
  `declare -F`), sources the resolved handler when present, and **falls back to
  the built-in `cli/commands/doctor_deep.sh`** when the resolver is empty
  (`community`) or unavailable. `output.sh` sourcing moved to after the deep
  gate. Header `--deep` comment updated to describe resolver routing.
- `installer/preflight.sh` — the profile-extra loop (was a `print_skip`) now
  routes each `PROFILE_PREFLIGHT_EXTRA` entry through
  `actools::dispatch::resolve_profile_check "preflight"`. A resolved+installed
  handler runs (`"$handler" "$extra"`; non-zero return → `((fails++)) || true`);
  an extra **declared but with no installed handler is a hard FAIL**
  (`print_fail` + `print_fix` + `((fails++)) || true`) for a non-default
  profile. The stale trailing "not called in D.0" comment was removed.
- `installer/handoff.sh` — the silent `*)` arm now routes non-built-in sections
  through `actools::dispatch::resolve_handoff_section` (guarded by `declare -F`):
  a resolved+installed handler renders the section; an **unresolved section
  emits a visible, non-fatal notice**. The in-function "not called in D.0"
  comment was updated.
- `tests/fixtures/profiles/fake-surfaces.profile` — **new** pure-data fixture
  (staged as `profiles/test.profile`) that declares a non-default value at each
  surface: an extra `PROFILE_INIT_FIELDS` entry, `PROFILE_PREFLIGHT_EXTRA=(check
  missing)` (one resolvable, one unknown), `PROFILE_HANDOFF_SECTIONS` with one
  extra section, and `PROFILE_DOCTOR_EXTRA=()` (loop deferred).
- `tests/fixtures/profiles/test/commands/doctor_deep.sh` — **new** Tier-1
  override fixture; its `run_doctor_deep` echoes a sentinel and returns 7.
- `tests/test_p0h_dispatch.bats` — **new** consolidated phase suite (9 tests):
  doctor override-wins (status 7 + sentinel), doctor community→built-in gate
  (status 2, override ignored), preflight resolved+unknown-fails (status 1),
  preflight community→no profile-check output, handoff resolved (sentinel),
  handoff community→no dispatch/notice + built-ins render, init fake-profile
  extra-field succeeds + not persisted, resolver-level community-all-empty
  (`"|||"`), and fixture side-effect-free. Reuses the existing
  `plus_preflight_check.sh` / `plus_handoff_section.sh` stubs.
- `docs/architecture/runtime-authority-map.md` (Preflight/Doctor/Handoff rows
  flipped to **consumed (P0-H)**; resolver-layer row updated; Init status
  updated; surface-blindness note closed; test count 135 → 144; P0-H answer
  added), `docs/architecture/phase0-seam-contract.md` (P0-H status note),
  `docs/CHANGELOG.md`, `docs/releases/P0-H-profile-aware-surfaces.md`,
  `docs/tests/P0-H-profile-aware-surfaces.md`,
  `docs/runbooks/HANDOFF-P0-H.md`, and this ledger entry (Entry 013).

### Files intentionally not changed

- `installer/dispatch.sh` — **byte-identical.** No resolver code changed; P0-H
  only consumes the P0-E primitives.
- `installer/init.sh` — **byte-identical.** Already profile-aware (P0-E);
  confirmed by the new fake-profile init-field test, not edited.
- `actools.sh` — **byte-identical.** Install-spine profile *selection* (sourcing
  the selected profile vs hardcoded `community.profile`) is a separate concern,
  out of P0-H scope.
- `installer/profile.sh`, `installer/output.sh`, `cli/commands/doctor_deep.sh`
  — **byte-identical** (the built-in deep gate is unchanged; community falls
  back to it).
- `modules/audit/audit.sh` — **out of scope** (a `--deep` *mode flag*, not a
  hardcoded source; modules are forbidden scope). Verified, nothing to do.
- No golden fixture modified; drift 6/6.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| doctor `--deep` handler | hard `source cli/commands/doctor_deep.sh` | `resolve_feature_handler doctor_deep` (3-tier) with baseline fallback to the built-in gate; `community` short-circuits to the built-in (byte-identical) |
| preflight profile extras | `print_skip` (never fails) | `resolve_profile_check "preflight"`: resolved runs; **unknown is a hard fail** for a non-default profile; `community` list empty (loop body never runs) |
| handoff non-built-in sections | silent `*)` | `resolve_handoff_section`: resolved renders; unresolved is a **visible non-fatal notice**; `community` never hits `*)` |
| init | profile-aware (P0-E) | **unchanged**; extra-init-field consumption now test-covered (collected as a no-op, not persisted) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Unchanged | golden drift 6/6 |
| Caddyfile | Unchanged | golden drift 6/6 |
| my.cnf | Unchanged | golden drift 6/6 |
| Dockerfiles | Unchanged | golden drift 6/6 |
| CLI | Not touched | `cli/actools` unchanged; `cli_authority_test.bats` 14/14 |

### Tests run

```bash
export PATH="$PWD/../bats-core-1.11.0/bin:$PATH"
# new phase suite
bats tests/test_p0h_dispatch.bats                       # 9/9
# community-unchanged regression
bats tests/installer/doctor_test.bats                   # 5/5
bats tests/installer/preflight_test.bats                # 6/6
bats tests/installer/init_profile_test.bats             # 10/10
bats tests/test_d0_dispatch.bats                        # 48/48
bats tests/generated/golden_drift_test.bats             # 6/6
# whole tree
bats -r tests/                                          # 144/144
# syntax + lint
bash -n actools.sh; for f in $(find installer cli core modules -name '*.sh'); do bash -n "$f"; done
shellcheck installer/preflight.sh installer/handoff.sh installer/init.sh cli/commands/doctor.sh installer/dispatch.sh
```

### Test result

PASS — 144/144 across the tree (9 new). Community behavior suites unchanged
(doctor 5, preflight 6, init_profile 10, d0_dispatch 48); **golden drift 6/6**.
shellcheck shows only pre-existing info-level `SC2012` (`ls -t` on untouched
lines) and a pre-existing `SC2034` in the unedited `init.sh`; no new findings.

### Documentation updated

- [x] Runtime authority map
- [x] Generated-file contract (no change; drift 6/6 noted)
- [x] CLI authority contract (no change; CLI untouched)
- [x] Operator target docs (seam-contract status note)
- [x] Test plan (test report added)

### Changelog / release notes

- [x] CHANGELOG.md updated
- [x] Release note added (`docs/releases/P0-H-profile-aware-surfaces.md`)
- [x] Test report added (`docs/tests/P0-H-profile-aware-surfaces.md`)
- [x] Review notes added (P0-H answer in the authority map; HANDOFF-P0-H.md)

### Known risks

- **`PROFILE_DOCTOR_EXTRA` per-check loop deliberately deferred (recorded scope
  call):** doctor deep handler wired via `resolve_feature_handler` + baseline
  fallback; per-check `PROFILE_DOCTOR_EXTRA` dispatch loop deliberately
  deferred — `resolve_doctor_check` primitive exists and is tested, consumer
  loop to be added when a profile defines doctor extras
  (community-plus/Phase-1). Spec #3's "deep/extra" is satisfied at the deep
  handler; the extra loop has no consumer in Phase 0. (Consistent with the
  LOCKED-alignment §4.1 pin, which scopes doctor to replacing the hard
  `source doctor_deep.sh` with `resolve_feature_handler`.)
- Profile preflight-extra handlers are expected to print their own OK/WARN/FAIL
  line and return non-zero to register a failure; this convention is documented
  in the surface comment and the release note.
- The handoff fail/skip **asymmetry** with preflight is deliberate: handoff is a
  post-install display surface, so an unresolved section is a visible notice,
  not a hard failure (documented in the release note).

### Blockers

None.

### Review Gate decision

Approved — pending operator re-run of the test + lint gate on the devbox after
applying the diff against `main`.

### Next safe task

P0-I — extend the resolver-bypass guard (sibling-scope audit) to `actools.sh`
and add the fake-profile e2e; then P0-J phase-0 closure review.

### Forbidden next scope

Install-spine profile **selection** (sourcing the selected profile in
`actools.sh::main`) and any community-plus handler implementation — both are
Phase-1 / later-phase scope, not P0-H.

## Entry 012 — P0-G · Extract Host and Stack Logic

Date: 2026-06-09
Branch: `phase0/P0-G-extract-host-stack`
Commit SHA: G1 `de64958`, G2 `47b05d8`, G3 `860d4a0`, G4 `74bc5b0`, G5 `e6af4fb`, G6 `0b220ce`, G7 `433a3c2` (operator records the merge SHA at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-G — Extract Host and Stack Logic
Task prompt source: `P0-G-extract-host-stack.md` + coding-window prompt (filled, archived)

### Objective

Move the live host-provisioning and stack-generation business logic out of the
monolithic `actools.sh::setup_stack()` into the canonical modules that existed as
orphans — `modules/host/*` and `modules/stack/*` — and drive them through the
install-stage dispatcher (`stage_host`) and the now-thin `setup_stack`. Hold all
30 golden fixtures **byte-identical** (drift 6/6). Unlike P0-F, this is an
**authority** move (which file is authoritative) with **no change to generated
output**.

### Approach (one unit per commit; drift re-run after every move)

Each generator was assembled by **byte-for-byte `sed` extraction** of its monolith
heredoc block, wrapped in a function, and verified with an empty `diff` of the
function body against the source range. Each move re-ran golden drift before
commit. The host block was extracted first (G1 modules carry bytes; G2 wires
`stage_host` and deletes the monolith host block), then the four stack generators
one file at a time (G3 my.cnf, G4 Dockerfiles, G5 Caddyfile, G6 compose), then the
harness was switched from sed-extract/eval of `setup_stack` to calling the module
generators directly (G7).

### Files changed

- `actools.sh` — **1416 → 871 lines.**
  - The inline host block (7 steps) is **deleted**; `stage_host` now drives
    `modules/host/*`.
  - Two module-sourcing loops added after init: host
    (`packages age kernel swap firewall docker logrotate`) and stack
    (`mycnf images caddyfile compose`).
  - `setup_stack()` (`:430-483`) is now a **thin orchestrator** (~53 lines):
    mkdir/chown prologue, `BACKUP_PASS=$(get_backup_pass)`, then
    `generate_mycnf` → `build_caddy_image`/`build_php_image`/`build_worker_image`
    → `generate_caddyfile` → `generate_compose`, then `docker compose
    pull/down/up`, then the out-of-scope `setup_backup_db_user "$BACKUP_PASS"`.
    The ten stack heredocs are removed (relocated to modules).
  - `setup_cli()` (`:702-717`) untouched (still pinned by the harness canary).
- `modules/host/{packages,age,kernel,swap,firewall,docker,logrotate}.sh` —
  **now live authority**; byte-identical to the monolith host steps. `docker.sh`'s
  `local bashrc` is the one intentional adaptation. `packages.sh` restores the
  `age` package.
- `modules/stack/mycnf.sh::generate_mycnf` — body byte-identical to the monolith
  my.cnf block; env-default `${INNODB_BUFFER_POOL:-1G}` (followed code, not the
  spec's stale "RAM-derived" claim); dropped the orphan's stale trailing
  `log "my.cnf generated."`.
- `modules/stack/images.sh::{build_caddy_image,build_php_image,build_worker_image}`
  — each body byte-identical; caddy heredoc QUOTED; php keeps the
  `if [[ ! -f Dockerfile.php ]]` guard + verbatim multi-space `docker build`;
  worker multi-line `docker build --build-arg`. Replaced the stale orphan (which
  lacked `build_php_image`).
- `modules/stack/caddyfile.sh::generate_caddyfile` — body byte-identical; UNQUOTED
  `CADDY` heredoc; full security headers; `/health` + `/csp-violations`; `@login
  rate_limit`; embedded all-in-one `$(… ALLINONE …)` fragment. Replaced the very
  stale orphan (which carried a `servers { protocols h1 h2 h3 }` block absent from
  the monolith).
- `modules/stack/compose.sh::generate_compose` — body byte-identical **except** a
  single `# shellcheck disable=SC2034` on `local REDIS_MEM` (confirmed false
  positive — `REDIS_MEM` is used at `:262-263` in the nested `REDIS_SVC` fragment;
  no output impact). Preserves the redis-off `depends_on` quirk. Replaced the very
  stale orphan (prod-only, inline env, no all-in-one/cadvisor).
- `tests/helpers/capture_golden_outputs.sh` — **harness rework.** Sources the four
  stack modules and calls the generators directly; the `eval "$(sed -n
  SS_START,SS_END)"` + `setup_stack` call removed; `SS_START`/`SS_END` deleted;
  `_assert_fn_range "setup_stack"` replaced by a new `_assert_fn_defined()` guard
  (module-file + generator existence); `SC_START`/`SC_END` (`setup_cli`) pin kept
  as the P0-F drift canary; header/comments/log text updated.
- `tests/installer/dispatch_stages_test.bats` — `setup()` now exports
  `ACTOOLS_SH`; **+2 tests**: `stage_host` canonical-order (G2) and `setup_stack`
  delegation order (G7); BLOCK 2 header notes the modular delegation.
- `docs/architecture/runtime-authority-map.md` (Host/Stack/Worker/Generated-file
  rows flipped to **modules = live (P0-G)**; install-stage `host` no-op → wired;
  test count 133 → 135; CI-gaps note updated; P0-G answer added),
  `docs/architecture/phase0-seam-contract.md` (P0-G status note),
  `docs/CHANGELOG.md`, `docs/releases/P0-G-extract-host-stack.md`,
  `docs/tests/P0-G-extract-host-stack.md`, `docs/runbooks/HANDOFF-P0-G.md`, and
  this ledger entry (Entry 012).

### Files intentionally not changed

- **No golden fixture was modified.** All 30 fixtures (5 variants × 6 files) are
  byte-identical; drift 6/6 proves the relocation preserved output.
- DB user/credential creation (`setup_backup_db_user`, the `install_env` DB SQL)
  — **folded, out of scope**; the `db` stage remains a documented no-op.
- Worker **runtime** (the worker compose service) — stays inside the compose
  generator; the `worker` stage remains a no-op. Only the worker **image** build
  moved (`build_worker_image`, part of `images.sh`).
- `docker compose pull/down/up` — stays in `setup_stack` (orchestration).
- The harness range guard was **replaced/kept**, never widened or disabled.
- `docker-compose.observability.yml` / `modules/observability/prometheus.sh` —
  **git-ignored**, untracked, out of scope (not authored or modified).

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Host provisioning | inline in `setup_stack` (`modules/host/*` orphan) | **`modules/host/*` (live)** invoked by dispatcher `stage_host` in the canonical 7-step order; monolith host block deleted |
| Stack file generation | inline heredocs in `setup_stack` (`modules/stack/*` orphan) | **`modules/stack/*` (live)** — `setup_stack` calls `generate_mycnf`/`build_*_image`/`generate_caddyfile`/`generate_compose` |
| `setup_stack` role | ~468-line monolith (host + 10 heredocs) | thin orchestrator (~53 lines): secret-gen order → 6 generators → `docker compose pull/down/up` → backup user |
| `host` stage handler | documented no-op (P0-D) | **wired** to the seven `modules/host/*` functions in monolith order |
| Worker image | inline `Dockerfile.worker` heredoc in `setup_stack` | `modules/stack/images.sh::build_worker_image` (live); worker **service** still in the compose generator (folded) |
| Golden capture mechanism | sed-extract + `eval` of `setup_stack` (SS_* line range) | sources `modules/stack/*` and **calls the generators directly**; SS_* removed; `_assert_fn_defined` guard |
| DB / worker runtime | folded (P0-D no-ops) | **unchanged** (still folded) |
| CLI / `setup_cli` | install-by-copy (P0-F) | **unchanged** |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | **Unchanged** (generation relocated) | `modules/stack/compose.sh::generate_compose`; golden drift 6/6 |
| Caddyfile | **Unchanged** (generation relocated) | `modules/stack/caddyfile.sh::generate_caddyfile`; golden drift 6/6 |
| my.cnf | **Unchanged** (generation relocated) | `modules/stack/mycnf.sh::generate_mycnf`; golden drift 6/6 |
| Dockerfiles | **Unchanged** (generation relocated) | `modules/stack/images.sh::build_*_image`; golden drift 6/6 |
| CLI | Not touched | P0-F; `setup_cli` untouched |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline @ 37b09c8):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# AFTER (re-run at every generated-file move):
bats tests/generated/golden_drift_test.bats                                 # 6/6 (fixtures unchanged)
bats tests/installer/dispatch_stages_test.bats                              # 14/14
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 129/129

# Syntax + lint:
bash -n actools.sh
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
shellcheck modules/host/*.sh modules/stack/*.sh                             # clean
shellcheck --severity=warning tests/helpers/capture_golden_outputs.sh      # clean
```

### Test result

PASS — golden drift **6/6** before and after (six stack files byte-identical;
**fixtures untouched**). Unit/integration **129/129** (127 prior + 2 new),
**135/135** overall. All `bash -n` clean; `modules/host/*`, `modules/stack/*`, and
the harness shellcheck-clean (warning+). `actools.sh` 1416 → 871 lines.

### Documentation updated

- [x] Runtime authority map — Host/Stack/Worker/Generated-file rows flipped to modules=live; install-stage `host` no-op→wired; test count 133→135; CI-gaps note; P0-G answer
- [x] Phase 0 seam contract — P0-G status note (host/stack now dispatcher-driven)
- [ ] Generated-file contract — no change to the doc (output unchanged; relocation recorded here + release note)
- [x] Test plan / report — `docs/tests/P0-G-extract-host-stack.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → P0-G section)
- [x] Release note added — `docs/releases/P0-G-extract-host-stack.md` (incl. Rollback + per-file table + host-behaviour diffs + SC2034 note)
- [x] Test report added — `docs/tests/P0-G-extract-host-stack.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **`setup_stack` body coverage moved off the golden path.** The harness no longer
  exercises `setup_stack` (it calls generators directly). Mitigated by the new
  delegation test, which runs the real `setup_stack` against recorder stubs and
  asserts generator order. A reviewer should confirm that test, not just drift.
- **Host steps are now fresh-install-only.** Four deliberate behaviour
  differences (dry-run/interactive-N/update/env) — see the release note. The
  fresh-install happy path is byte-identical; host steps were already idempotent.
- **One `compose.sh` SC2034 suppression.** Confirmed false positive (`REDIS_MEM`
  used in the nested `REDIS_SVC` fragment); no output impact; drift 6/6.
- **Stale `modules/stack/*` orphans replaced.** The previous orphans were v9.2 and
  divergent; each was overwritten with the monolith's current exact bytes. A
  reviewer should treat the module as the live authority.

### Blockers

None.

### Review Gate decision

Pending — a **separate session (ideally a different model)** renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) golden drift **6/6**
with **fixtures unmodified** (the relocation preserved output); (2) only allowed
files touched; (3) `modules/host/*` + `modules/stack/*` bodies are byte-identical
to the monolith blocks (the one exception is the documented `compose.sh` SC2034
comment, no output impact); (4) `stage_host` drives the seven host functions in
monolith order and `setup_stack` delegates to the six generators in canonical
order (both asserted by tests); (5) the harness renders via the modules directly
(no `setup_stack` eval / no `SS_*`), and `_assert_fn_defined` + the `setup_cli`
canary are green, not widened/disabled; (6) the redis-off `depends_on` quirk is
preserved (validated by the `redis-off` golden).

### Next safe task

**P0-H — Surface wiring** (wire the *selected* profile into the install spine and
route the preflight/doctor/handoff surfaces through the resolvers), or the Review
Gate's chosen sequencing. With host/stack extracted behind the dispatcher and the
CLI consolidated (P0-F), the remaining Phase-0 work is surface/resolver wiring and
the CI/shellcheck hardening (P0-I).

### Forbidden next scope

No DB user/credential extraction or worker-runtime extraction (still folded); no
profile-semantics changes; no community-plus feature commands; no touching the
golden fixtures or widening/disabling the harness guards; no authoring or
modifying observability (out of scope, git-ignored).

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. P0-G relocates host/stack authority into
the modules behind the dispatcher but wires no community-plus feature.

---

## Entry 011 — P0-F · CLI Authority Consolidation

Date: 2026-06-09
Branch: `phase0/P0-F-cli-authority`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-F — CLI Authority Consolidation
Task prompt source: `P0-F-cli-authority.md` + coding-window prompt (filled, archived)

### Objective

Collapse the two divergent operator CLIs into **one canonical source**. Adopt
**Option A**: `cli/actools` is canonical; the installer (`setup_cli`) installs it
by copying it verbatim; the duplicate `cat > /usr/local/bin/actools <<HELPER`
generator is deleted. Preserve safe secret handling, retain every command's
behavior (parity matrix), declare the CLI **Changed intentionally** while proving
the six non-CLI generated files stay byte-identical (golden drift 6/6).

### Decision (Option A)

Option A over Option B because no runtime substitution is required: the CLI reads
all install-time state at runtime (`ACTOOLS_HOME`, `actools.env`, `.actools-state.json`).
The single value the heredoc baked in (`INSTALL_DIR`) is now resolved at runtime
via `INSTALL_DIR="${ACTOOLS_HOME:-$(self-locate)}"`. `setup_cli` already writes
`ACTOOLS_HOME` to `/etc/environment`; the fallback covers in-repo execution
(tests, `./cli/actools`). Because the installed file is a verbatim copy, the CLI
is **no longer a generated artifact** and is removed from the golden-fixture set;
its integrity is proven directly by an installed==source test.

### Files changed

- `cli/actools` — **now the single canonical CLI.**
  - `:7` `INSTALL_DIR="${ACTOOLS_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"`
    (was self-location only) so the verbatim copy resolves correctly at
    `/usr/local/bin/actools`.
  - Stale comment (old `:12-15`, "no setup_cli.sh heredoc generator… audited")
    **rewritten** to describe install-by-copy and point at the contract.
  - `update` — snapshot switched to the **safe** `--defaults-extra-file` path
    (password fed via stdin into a temp cnf created **inside** the db container
    with `umask 077` + `trap` cleanup; never in argv), reusing the already-loaded
    `BACKUP_PASS` and keeping its guard; **kept** static's strict `exit 1` +
    rollback hint and `pull db redis php_prod`; **changed** the `drush updb` loop
    to env-driven (`for env in $(echo "${ENVIRONMENTS:-prod}" | tr ',' ' ')`).
  - `restore` / `restore-test` — root DB ops switched to
    `docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"'`
    (password from the db container's own env var, never in argv); removed the now
    **dead** `[[ -z "$DB_ROOT_PASS" ]]` guards (`DB_ROOT_PASS` is not exported to
    the host); kept confirmation/checksum/glob and the backtick-escaped DB name;
    **kept** `restore-test`'s `.restore-test-last` marker (consumed by
    `cli/commands/doctor.sh:194`); **dropped** the generated CLI's S3 reachability
    chain (accepted consequence — no functional dependency, avoids noise on
    non-S3 installs).
  - `storage-info` — `ENV_FILE` `/home/actools/actools.env` → `${INSTALL_DIR}/actools.env`.
  - `migrate` — `Current mode: local` → `Current mode: ${XELATEX_MODE:-local}`.
  - `health` — loop made env-driven (matches generated; identical for community).
  - **`audit` command added** (ported verbatim from the generated CLI; sets
    `ACTOOLS_HOME`, sources `modules/audit/lib/output.sh`, runs
    `modules/audit/audit.sh "${@:2}"`) + `audit` entries added to both help tiers.
    Parity preservation: the module already ships; only `--deep` is edition-gated.
- `actools.sh` — `setup_cli()` (`:1247-1262`): the `HELPER` heredoc (old
  `:1251-1520`) and the dead `local backup_pass=$(get_backup_pass)` removed;
  replaced with `install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools`;
  `chmod +x` / `log` / `ACTOOLS_HOME` write tail kept. `setup_stack` (`:569-1028`)
  untouched. (`get_backup_pass` retained — still used at `:588/:1169/:1629`.)
- `tests/helpers/capture_golden_outputs.sh` — `SC_END` 1528 → **1262**
  (`SC_START` 1247, `SS_*` unchanged); the PHASE-2 CLI render and the PHASE-3
  `actools-cli` copy removed; `actools-cli` dropped from the PHASE-4 sha manifest;
  orphaned `FIXED_CLI_INSTALL_DIR` removed. The `_assert_fn_range "setup_cli"`
  **drift guard is kept and updated** (range-checked though no longer rendered).
- `tests/fixtures/golden/{default,redis-off,s3-on,cadvisor-on,all-in-one}/` —
  `actools-cli` fixture deleted; each `SHA256SUMS` reduced to **6** entries by
  removing only the `actools-cli` line (the six stack-file sums are **byte-for-byte
  preserved**, so a passing drift run proves the non-CLI files are unchanged).
- `tests/generated/golden_drift_test.bats` — meta-test manifest-entry assertion
  7 → **6**.
- `tests/installer/cli_authority_test.bats` — **new, 14 tests.**
- `docs/architecture/cli-authority-contract.md` (Option A decision + 12-row matrix
  filled + Status: satisfied), `docs/architecture/runtime-authority-map.md`
  (CLI-install / Generated-CLI / Doctor / Handoff rows; test count 119→133),
  `docs/CHANGELOG.md`, `docs/releases/P0-F-cli-authority.md`,
  `docs/tests/P0-F-cli-authority.md`, `docs/runbooks/HANDOFF-P0-F.md`, and this
  ledger entry (Entry 011).

### Files intentionally not changed

- `actools.sh::setup_stack()` and the six non-CLI generators (`my.cnf`,
  `Dockerfile.{caddy,php,worker}`, `Caddyfile`, `docker-compose.yml`) — **not
  touched**; golden drift 6/6.
- `modules/audit/*` — the `audit` command was **wired**, not authored; the module
  ships as-is.
- `cli/commands/*.sh` — unchanged (the `.restore-test-last` consumer in
  `doctor.sh` verified intact by a test).
- `modules/dr/resurrect.sh` — its independent `actools-real` copy is **out of
  scope** (P0-J).
- The harness range guard was **updated, not widened or disabled**.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| CLI source | **two** divergent CLIs: a generated `HELPER` heredoc in `setup_cli` **and** static `cli/actools` | **one** canonical source: `cli/actools`; installer copies it verbatim |
| CLI install (`setup_cli`) | `cat > /usr/local/bin/actools <<HELPER …` (install-time `$`/`$()` expansion) | `install -m 0755 "${INSTALL_DIR}/cli/actools" …` (verbatim copy) |
| CLI `INSTALL_DIR` resolution | heredoc baked `INSTALL_DIR=<literal>` | runtime `"${ACTOOLS_HOME:-<self-locate>}"` |
| CLI golden coverage | rendered `actools-cli` fixture in all 5 variants (7-entry manifests) | **no CLI fixture** (6-entry manifests); installed==source proven by `cli_authority_test.bats` |
| DB secrets in CLI | snapshot `-p"$BACKUP_PASS"`; root ops `-p"$DB_ROOT_PASS"` (argv-visible) | snapshot `--defaults-extra-file` (umask 077 + trap); root ops `MYSQL_PWD` in-container — **never in argv** |
| `audit` in static CLI | absent | present (parity) |
| Install path / `setup_stack` | dispatcher-driven (P0-D) | **unchanged** |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | no generator edited; golden drift 6/6 |
| Caddyfile | Not touched | no generator edited; golden drift 6/6 |
| my.cnf | Not touched | no generator edited; golden drift 6/6 |
| Dockerfiles | Not touched | no generator edited; golden drift 6/6 |
| CLI (`actools-cli`) | **Changed intentionally** | CLI authority consolidated to `cli/actools` (Option A); CLI is no longer generated; `actools-cli` fixture retired; installed==source proven by `cli_authority_test.bats`. See release note. |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline @ aa881de):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6 (six non-CLI files byte-identical)
bats tests/installer/cli_authority_test.bats                                # 14/14 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# Syntax:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# Secret-safety static check (in the new suite):
grep -nE '(-p"?\$|--password=)' cli/actools                                 # no matches
```

### Test result

PASS — golden drift **6/6** before and after (six non-CLI generated files
byte-identical; `actools-cli` fixture retired by design). Unit/integration
**127/127** (113 prior + 14 new), **133/133** overall. All `bash -n` clean. No
password-in-argv pattern remains in `cli/actools`.

### Documentation updated

- [x] Runtime authority map — CLI-install / Generated-CLI / Doctor / Handoff rows; test count 119→133
- [ ] Generated-file contract — no change to the doc itself (the CLI's "Changed intentionally" status is recorded in the release note, per its rule)
- [x] CLI authority contract — Option A decision recorded + 12-row parity matrix filled + Status: satisfied
- [ ] Operator target docs — none this phase
- [x] Test plan / report — `docs/tests/P0-F-cli-authority.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → P0-F section)
- [x] Release note added — `docs/releases/P0-F-cli-authority.md` (incl. Rollback + "Changed intentionally" justification)
- [x] Test report added — `docs/tests/P0-F-cli-authority.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **CLI is now "Changed intentionally" (not byte-identical).** This is the first
  generated-file behavior change in Phase 0. It is bounded by the parity matrix
  and justified in the release note; the six **non-CLI** generated files remain
  byte-identical (drift 6/6). A reviewer should read the matrix, not just the
  drift result.
- **`INSTALL_DIR` now trusts `ACTOOLS_HOME`.** On an installed host this is set by
  `setup_cli`; if `/etc/environment` is wiped, the CLI falls back to self-location
  which, from `/usr/local/bin`, resolves to `/usr/local` (wrong). The risk is the
  same class the heredoc baked around; mitigated because `setup_cli` always
  (re)writes `ACTOOLS_HOME` at install. Tests pin `ACTOOLS_HOME` for determinism.
- **Dropped `restore-test` S3 reachability chain.** Operators who relied on
  `restore-test` implicitly running `storage-test` must call `actools storage-test`
  explicitly. Documented in the release note.
- **Installed CLI gains `tunnel` and a 2-tier `help`** (previously only in static)
  and the `audit` command. These are additive; documented.
- **`worker-run`** keeps the static `drush queue:run …` (the generated CLI's
  `xelatex --version` anomaly is intentionally dropped). Documented.

### Blockers

None.

### Review Gate decision

Pending — a **separate session (ideally a different model)** renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) the six non-CLI
generated files are byte-identical (drift 6/6) and the CLI's "Changed
intentionally" status matches the parity matrix; (2) only allowed files touched;
(3) `setup_cli` installs by verbatim copy with no heredoc and the installed CLI
equals `cli/actools`; (4) **no** DB password appears in any argv (snapshot uses a
defaults file, root ops use `MYSQL_PWD` in-container) and the temp cnf uses
`umask 077` + trap; (5) the harness range guard is updated (SC_END=1262) and
green, not widened/disabled.

### Next safe task

**P0-G — Host/stack extraction**, or **P0-H — Surface wiring** (the Review Gate
owns sequencing). With the CLI consolidated, the remaining generated-file authority
work (extracting `setup_stack`'s host/stack heredocs into `modules/*` behind the
dispatcher, with golden fixtures) can proceed independently of CLI concerns.

### Forbidden next scope

No host/stack extraction in this phase (that is P0-G); no community-plus feature
commands beyond the existing stubs/gates; no broad rewrite of command behavior
beyond the documented parity matrix; no touching `setup_stack` or the six non-CLI
generators; no widening or disabling the golden harness range guard.

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. P0-F removes the CLI duplication and locks
the CLI to a single safe source, but wires no community-plus feature.

---

## Entry 010 — P0-E · Profile Validation and Resolver Contract

Date: 2026-06-09
Branch: `phase0/P0-E-profile-validation-and-resolver`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-E — Profile Validation and Resolver Contract
Task prompt source: `P0-E-profile-validation-and-resolver.md` + coding-window prompt (filled, archived)

### Objective

Make profile selection **safe at `init` time** and **complete the resolver
contract** to the LOCKED shape — with community behaviour byte-identical and **no
community-plus feature work**. Two pieces: (1) `init` sources `profile.sh`,
validates the `.profile` file exists, and enforces governance flags **before
persisting** `actools.env`; (2) `resolve_feature_handler` becomes 3-tier
path-resolution (alignment §4.1) and a LOCKED-named `resolve_profile_check`
umbrella (alignment §4.2) is added, both as internal primitives still **uncalled
on the live path** (their callers are P0-H).

### Scope note (P0-D handoff superseded by the P0-E spec §1)

The P0-D handoff named the next task as "replace the hardcoded
`source community.profile` in `main()` with `ACTOOLS_PROFILE`-driven selection."
The P0-E spec (and its operationalized prompt §1) explicitly **corrects** that:
`actools.sh` is **not** in P0-E's allowed files and must not be touched; wiring
the install path to the selected profile is **P0-H**. P0-E therefore changes **no
runtime install behaviour** — the only live behavioural change is in the `init`
command. `actools.sh` is byte-identical (`git diff HEAD -- actools.sh` empty).

### Files changed

- `installer/init.sh` — sources `installer/profile.sh` for the chosen profile;
  **validates the `.profile` file exists and fails before persisting**
  `actools.env` (exit 3 when absent); enforces `PROFILE_REQUIRES_ACTOR` /
  `PROFILE_REQUIRES_CHANGE_TICKET` via the existing `profile_requires_actor`
  (`profile.sh:38`) / `profile_requires_change_ticket` (`profile.sh:39`); consumes
  `PROFILE_INIT_FIELDS` via `profile_init_fields` (`profile.sh:40`). Adds
  `--actor-id` / `--change-ticket` (and `=` forms), **validated but not
  persisted** (governance identity recording is P0-H). `ACTOOLS_PROFILE` is
  declared **local** in `run_init` so init never leaks profile identity. All four
  accessors already existed — this is **wiring, not authoring**.
- `installer/dispatch.sh` —
  - `actools::dispatch::resolve_feature_handler` rewritten to **3-tier PATH
    resolution** (alignment §4.1): Tier 1 `profiles.d/${ACTOOLS_PROFILE}/commands/${feature}.sh`
    → Tier 2 `modules/${module}/${feature}.sh` (module the active profile lists
    via the internal `PROFILE_FEATURE_MODULES`, read `+x`-guarded for `set -u`
    safety) → Tier 3 `cli/commands/${feature}.sh`. First existing path wins, else
    empty. **community short-circuits to empty before the search** (byte-identical,
    non-negotiable). Unknown profile → WARN + empty (preserved fail-soft).
  - **new** `actools::dispatch::resolve_profile_check <surface> <check_id>`
    (alignment §4.2) — umbrella delegating to `resolve_preflight_check` /
    `resolve_doctor_check` / `resolve_handoff_section`; unknown surface → WARN +
    empty. The per-surface resolvers are **kept as the internals**.
  - File header updated to document the **return-shape asymmetry** (feature →
    path; preflight/doctor/handoff → token; install-stage → function name;
    profile-check → delegated token).
- `tests/installer/init_profile_test.bats` — **new**, 10 tests (init-time
  validation, governance fire, non-persistence, community preserved).
- `tests/test_d0_dispatch.bats` — **+15 tests** (33 → 48): 3-tier order (Block 9),
  `resolve_profile_check` delegation (Block 10), side-effect-free loading +
  negative control (Block 11). The single community-plus `resolve_feature_handler`
  test was updated from the `plus_doctor_deep` token to the resolved tier-3 path.
- `tests/fixtures/profiles/fake-actor.profile`, `…/fake-ticket.profile` —
  **new test-only fixtures** (never shipped; staged as `profiles/test.profile`).
- `tests/installer/init_test.bats` — setup now stages `dispatch.sh`, `profile.sh`,
  and `community.profile` into the sandbox so the 11 existing tests exercise the
  real (profile-sourcing) init flow under `set -u`.
- `docs/architecture/runtime-authority-map.md` — Init, Profile-loading, and
  Resolver-layer rows updated; test-surface count 88 → 113; Review question
  answered for P0-E.
- `docs/CHANGELOG.md`, `docs/releases/P0-E-profile-validation-and-resolver.md`,
  `docs/tests/P0-E-profile-validation-and-resolver.md`,
  `docs/runbooks/HANDOFF-P0-E.md`, and this ledger entry (Entry 010).

### Files intentionally not changed

- `actools.sh` — **forbidden this phase**; byte-identical (no install-path wiring;
  that is P0-H).
- `profiles/community.profile` — read via the loader; **not modified** (governance
  flags already `false`, `PROFILE_INIT_FIELDS=(domain email site-name)`).
- All generator heredocs, `cli/*`, `modules/*`, `core/*`, `.github/workflows/*`.
- `installer/profile.sh` — **in the allowed set but not edited**: all four
  accessors already existed and were sufficient (wiring only).
- `tests/helpers/capture_golden_outputs.sh` — untouched; golden harness guard not
  widened/disabled.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Init (`installer/init.sh`) | validated profile **list membership** only; never sourced `profile.sh`; `--actor-id`/`--change-ticket` unhandled; wrote `actools.env` for any allowed *name* (incl. `community-plus`, whose file is absent) | sources `profile.sh`; validates **file existence** and **fails before persisting**; enforces actor/ticket via accessors; consumes `PROFILE_INIT_FIELDS`. Community unchanged |
| Resolver — `resolve_feature_handler` | returned a **token** (`community`→`""`; `community-plus`→`plus_<f>`; `test`→`test_<f>`) | returns a **PATH** via 3-tier resolution (override → module → default), first existing wins, else empty; `community`→`""` short-circuit preserved. **No live call sites** → no runtime behaviour change |
| Resolver — `resolve_profile_check` | **absent (0 hits)** | **present** — LOCKED-named umbrella delegating to the per-surface internals |
| Resolver — preflight/doctor/handoff | token-based | **unchanged** (token-based; surfaces wired in P0-H) |
| Install path / `actools.sh` | dispatcher-driven (P0-D) | **unchanged** (P0-E does not touch `actools.sh`) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | no generator edited; golden drift 6/6 |
| Caddyfile | Not touched | no generator edited; golden drift 6/6 |
| my.cnf | Not touched | no generator edited; golden drift 6/6 |
| Dockerfiles | Not touched | no generator edited; golden drift 6/6 |
| CLI | Not touched | `setup_cli` heredoc + `cli/actools` unedited; golden drift 6/6 |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean HEAD, P0-E WIP stashed):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 88/88

# Syntax:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6 (byte-identical)
bats tests/installer/init_profile_test.bats                                 # 10/10 (new)
bats tests/test_d0_dispatch.bats                                            # 48/48 (33 + 15)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113
```

### Test result

PASS — golden drift **6/6** before and after (generated output byte-identical);
**113/113** regression+new; **119/119** overall. `actools.sh` byte-identical.

### Documentation updated

- [x] Runtime authority map — Init / Profile-loading / Resolver-layer rows; test count 88→113; Review question
- [ ] Generated-file contract — no generated-file change
- [ ] CLI authority contract — no CLI-authority change (init is CLI-adjacent but the change is validation, not authority)
- [ ] Operator target docs — none this phase
- [x] Test plan / report — `docs/tests/P0-E-profile-validation-and-resolver.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → P0-E section)
- [x] Release note added — `docs/releases/P0-E-profile-validation-and-resolver.md` (incl. Rollback)
- [x] Test report added — `docs/tests/P0-E-profile-validation-and-resolver.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **Token→path contract change (`resolve_feature_handler`).** This changes the
  resolver's return shape for non-community profiles. It is safe **only** because
  the function has **zero live call sites** (verified — its callers are wired in
  P0-H). When P0-H wires it in, callers must consume a **path** (source/execute),
  not a token. Documented in the CHANGELOG, release note, and authority map.
- **Resolver asymmetry.** `resolve_feature_handler` is path-based while
  preflight/doctor/handoff stay token-based; `resolve_profile_check` therefore
  returns tokens today (it delegates to the token resolvers). Intentional and
  documented; reconciled when the surfaces are wired (P0-H).
- **`PROFILE_FEATURE_MODULES` is an internal resolver convention.** It is not part
  of the public profile contract in `profiles/README.md` and is not set by
  `community.profile`; only profiles shipping feature modules define it. Read
  `+x`-guarded so its absence (the common case) is a no-op under `set -u`.
- **`init` now sources `profile.sh`.** For community this is inert (flags false,
  base fields). A profile that declares `PROFILE_INIT_FIELDS` beyond
  domain/email/site-name has those "extra" fields collected but **not yet
  validated/collected** at init — that surface wiring is P0-H (community declares
  no extras, so this is a no-op today).
- **Governance identity not persisted.** `--actor-id`/`--change-ticket` are
  validated but not written to `actools.env` (P0-H concern). Tests assert
  non-persistence.

### Blockers

None.

### Review Gate decision

Pending — a **separate session (ideally a different model)** renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) golden 6/6 unchanged
and `actools.sh` byte-identical; (2) only allowed files touched; (3)
`resolve_feature_handler` 3-tier order is correct **and community short-circuits
to empty even with a staged override**; (4) `init` fails **before** persisting for
`community-plus`/absent profiles and community is unchanged; (5) the token→path
asymmetry is acceptable for now (reconciled at P0-H).

### Next safe task

**P0-H — Surface wiring.** Wire the completed resolvers into the live surfaces:
route preflight extras via `resolve_profile_check "preflight" …` (fail unknown for
non-default), replace doctor's hard `source doctor_deep.sh` with
`resolve_feature_handler`, replace handoff's silent `*)` with
`resolve_handoff_section`, and wire the install path to the **selected** profile
(the `ACTOOLS_PROFILE`-driven selection the P0-D handoff anticipated, now safe
because `init` validates the profile file). Golden 6/6 must remain green. (The
Review Gate owns final sequencing.)

### Forbidden next scope

No community-plus modules; no deep audit/doctor features; no governance gates
beyond validation scaffolding; no generated-file byte change; no widening or
disabling the golden harness range guard.

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. P0-E adds the init-time safety and the
resolver primitives but wires nothing into the live install path.

---

## Entry 009 — P0-D · Install-Stage Dispatcher Skeleton

Date: 2026-06-08
Branch: `phase0/P0-D-install-stage-dispatcher`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Opus)
Phase: P0-D — Install-Stage Dispatcher Skeleton
Task prompt source: `P0-D-install-stage-dispatcher.md` + coding-window prompt (filled, archived)

### Objective

Introduce an install-stage dispatcher (`actools::dispatch::resolve_install_stage`
+ `actools::dispatch::run_install_stage`) and route the default `fresh` install
through it by iterating `PROFILE_INSTALL_STAGES`, with **byte-identical generated
output and byte-identical behaviour**. This is the seam that makes install order
profile-driven and append-only (it is what makes LOCKED Decision 3 —
community-plus *appends* `plus_*` — enforceable). No module extraction (P0-G);
no community-plus stages; no CLI-authority change (P0-F).

### Stage → handler mapping decision (the §5 design decision)

The flat community stage list `(host stack db drupal worker)` does not yet map
one-to-one onto the two coarse monoliths (`setup_stack` builds host + stack +
worker; `install_env` does db + Drupal per environment inside a parallel/RAM
loop). Full per-stage decomposition is **P0-G**. For P0-D the minimal
behaviour-preserving wiring is:

| Stage  | Handler                          | Behaviour |
|---|---|---|
| host   | `actools::install::stage_host`   | no-op — folded inside `setup_stack` until P0-G |
| stack  | `actools::install::stage_stack`  | calls `setup_stack` **unchanged** (host + stack + worker) |
| db     | `actools::install::stage_db`     | no-op — folded inside the per-env `install_env` loop until P0-G |
| drupal | `actools::install::stage_drupal` | runs the full per-env `install_env` loop **verbatim** (ENVIRONMENTS split + RAM probe + low-RAM downgrade + parallel/sequential branch) |
| worker | `actools::install::stage_worker` | no-op — worker container built inside `setup_stack` until P0-G |

Iterating host→stack→db→drupal→worker therefore executes
`(no-op)→setup_stack→(no-op)→install_env loop→(no-op)`, byte-for-byte the legacy
sequence. **Judgment call (flagged):** the DB work is anchored under the `drupal`
handler (the `db` handler is a documented no-op) because `install_env` performs
DB creation and Drupal install together; this is trivially flippable and both
arrangements keep the golden net and the stage-order test green.

**Resolver asymmetry (documented):** the existing feature/preflight/doctor/handoff
resolvers echo `""` for community (callers treat empty as "run default inline"),
but an install stage MUST resolve to a concrete, runnable function because
`run_install_stage` calls it. So `resolve_install_stage` returns
`actools::install::stage_<stage>` for community (and as the unknown-profile
fail-soft fallback, after a WARN), never empty. `community-plus`→`plus_<stage>`
and `test`→`test_<stage>` mirror the sibling resolvers as forward-looking
scaffolding (only community runs in P0-D).

### Files changed

- `installer/dispatch.sh` — **append-only** (behind the existing module guard;
  no edits above line 191). Adds `actools::dispatch::resolve_install_stage`,
  `actools::dispatch::run_install_stage`, and the five community base handlers
  `actools::install::stage_{host,stack,db,drupal,worker}`. The `drupal` handler
  contains the per-env install loop copied verbatim from `main()`.
- `actools.sh` — **`main()` only** (fresh mode). Replaced the hardcoded
  `setup_stack` + per-env `install_env` block (old lines 1606–1623) with:
  `source "${INSTALL_DIR}/profiles/community.profile"` then
  `for stage in "${PROFILE_INSTALL_STAGES[@]}"; do actools::dispatch::run_install_stage "$stage"; done`.
  The trailing post-stage steps `setup_backup_cron` / `setup_cli` / `tls_check`
  are unchanged. No function above `main()` was touched, so the harness line
  ranges for `setup_stack` (569–1028) and `setup_cli` (1247–1528) are preserved.
- `tests/installer/dispatch_stages_test.bats` — **new**, 12 BATS tests (stage
  order; real-handler behaviour preservation incl. low-RAM downgrade;
  append-only stage guard; resolver correctness + fail-loud-on-undefined-handler).
- `docs/architecture/runtime-authority-map.md` — dispatcher now wired (see below).
- `docs/CHANGELOG.md`, `docs/releases/P0-D-install-stage-dispatcher.md`,
  `docs/tests/P0-D-install-stage-dispatcher.md`, `docs/runbooks/HANDOFF-P0-D.md`,
  and this ledger entry (Entry 009).

### Files intentionally not changed

- `profiles/community.profile` — `PROFILE_INSTALL_STAGES=(host stack db drupal worker)`
  is already canonical (line 28); the dispatcher reads it, does not redefine it.
- `setup_stack`, `install_env`, `setup_backup_cron`, `setup_cli`, `tls_check`
  bodies — untouched (behaviour provided unchanged).
- All generated-file generators (`actools.sh:595/607/624/634/663/795`, the
  `setup_cli` heredoc) — untouched.
- `tests/helpers/capture_golden_outputs.sh` — untouched; `SS_*/SC_*` ranges
  still valid (the guard was NOT widened, commented, or disabled).
- `.github/workflows/*` (CI guard is P0-I), `modules/*`, `core/*`, `cli/*`.

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| Install-stage orchestration | `main()` (fresh) ran a hardcoded `setup_stack` then a per-env `install_env` loop | `main()` iterates `PROFILE_INSTALL_STAGES` and calls `actools::dispatch::run_install_stage` per stage; handlers call the same monoliths unchanged |
| Resolver layer (`installer/dispatch.sh`) | 4 resolvers (feature, preflight, doctor, handoff); install stages had no resolver | + `resolve_install_stage` (5th resolver) and `run_install_stage` (runner) + 5 community base stage handlers |
| Profile read in `main()` | `main()` was profile-blind (0 refs to `PROFILE_INSTALL_STAGES`) | `main()` sources `community.profile` to obtain the stage list (profile **selection** by `ACTOOLS_PROFILE` remains P0-E) |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator unedited; golden drift 6/6 |
| Caddyfile | Not touched | generator unedited; golden drift 6/6 |
| my.cnf | Not touched | generator unedited; golden drift 6/6 |
| Dockerfiles | Not touched | generators unedited; golden drift 6/6 |
| CLI | Not touched | `setup_cli` heredoc + `cli/actools` unedited; golden drift 6/6 |

### Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE any change — baseline green:
bats tests/generated/golden_drift_test.bats          # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 76/76

# syntax (all shell):
bash -n actools.sh
bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n   # all OK

# AFTER changes — still green:
bats tests/generated/golden_drift_test.bats          # 6/6 (byte-identical)
bats tests/installer/dispatch_stages_test.bats       # 12/12 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats     # 88/88 (76 + 12)
# total across golden + regression + new = 94/94
```

### Test result

PASS — golden drift 6/6 before **and** after (generated bytes unchanged);
12/12 new dispatcher tests; 88/88 regression+new; 94/94 overall. Function line
ranges re-verified unchanged (`setup_stack` 569/1028, `setup_cli` 1247/1528) so
`_assert_fn_range` still holds.

### Documentation updated

- [x] Runtime authority map — install-stage orchestration + resolver rows updated
- [ ] Generated-file contract — no generated-file change
- [ ] CLI authority contract — no CLI-authority change
- [ ] Operator target docs — none this phase
- [x] Test plan / report — `docs/tests/P0-D-install-stage-dispatcher.md`

### Changelog / release notes

- [x] CHANGELOG.md updated (Unreleased → runtime change)
- [x] Release note added — `docs/releases/P0-D-install-stage-dispatcher.md` (incl. Rollback)
- [x] Test report added — `docs/tests/P0-D-install-stage-dispatcher.md`
- [ ] Review notes — pending Review Gate

### Known risks

- **db/drupal anchor (judgment call):** DB creation runs inside the `drupal`
  handler (the `db` handler is a no-op). This preserves current behaviour exactly
  but means the `db`↔`drupal` split is cosmetic until P0-G genuinely separates
  `install_env` into DB and Drupal handlers. Flipping the anchor is trivial and
  test-covered.
- **`PARALLEL_INSTALL` global mutation:** the `drupal` handler intentionally does
  NOT declare `PARALLEL_INSTALL` local, mirroring the legacy in-`main()` mutation
  during the low-RAM downgrade. `ENVS`/`TOTAL_RAM`/`env` ARE local (every other
  use site re-derives them; nothing reads them after the loop), which is
  provably behaviour-neutral.
- **Profile sourced inside `main()`:** P0-D hardcodes `source community.profile`.
  P0-E must replace this with profile-driven selection via `ACTOOLS_PROFILE`
  (using `actools::cli::resolve_profile`), at which point the hardcode is removed.
- **Line-range coupling (unchanged):** the harness still hardcodes `setup_stack`
  569–1028 and `setup_cli` 1247–1528. P0-D did not shift them; any future
  `main()`-above edit must update `SS_*/SC_*` in the same commit.

### Blockers

None.

### Review Gate decision

Pending — a **separate Sonnet window** (scope/diff review) renders
APPROVED / NEEDS REVISION / BLOCKED. Reviewer: confirm (1) golden 6/6 unchanged,
(2) only allowed files touched, (3) the stage loop reproduces the legacy
sequence exactly, (4) the db/drupal anchor judgment call is acceptable or should
be flipped.

### Next safe task

**P0-E — Profile selection wiring** — replace the hardcoded
`source community.profile` in `main()` with `ACTOOLS_PROFILE`-driven profile
resolution (via `actools::cli::resolve_profile`), so the stage loop runs the
selected profile's `PROFILE_INSTALL_STAGES`. Golden 6/6 must remain green; the
dispatcher seam from P0-D is the foundation. (Final sequencing is the Review
Gate's call.)

### Forbidden next scope

No module extraction / host-stack decomposition (P0-G); no community-plus stage
implementations; no generated-file byte change; no CLI-authority consolidation
(P0-F); no widening/disabling the golden harness range guard.

---

## Entry 008 — P0-C · Golden Behavior Capture

Date: 2026-06-08
Branch: `phase0/P0-C-golden-behavior-capture`
Commit SHA: (recorded by operator at apply time)
Actor / Claude session (model): Coding Window (Sonnet)
Phase: P0-C — Golden Behavior Capture
Task prompt source: `P0-C-coding-window-prompt.md` (filled, archived)

### Objective

Capture byte-exact golden fixtures of all generated files across the 5-variant
environment matrix, plus a drift-detecting BATS test suite that FAILS on any
unexplained change.  This is the safety net that must remain green before any
later phase (P0-D / P0-G) touches generation logic.  Zero generator or runtime
byte changes.

### Files changed

New (golden fixtures — 5 variants × 7 files + 1 manifest each = 40 files):

- `tests/fixtures/golden/default/` — my.cnf, Dockerfile.caddy, Dockerfile.php,
  Dockerfile.worker, Caddyfile, docker-compose.yml, actools-cli, SHA256SUMS
- `tests/fixtures/golden/redis-off/` — same 8 files
- `tests/fixtures/golden/s3-on/` — same 8 files (S3 creds populated)
- `tests/fixtures/golden/cadvisor-on/` — same 8 files (cadvisor service added)
- `tests/fixtures/golden/all-in-one/` — same 8 files (dev/stg services + vhosts)

New (test infrastructure):

- `tests/helpers/capture_golden_outputs.sh` — capture helper; extracts
  `setup_stack()` and `setup_cli()` from the live `actools.sh` via
  `sed -n 'X,Yp'` + `eval`, never copies heredoc text; runs each function
  in an isolated subshell with no-op bash function shims for `docker`,
  `chown`, `section`, `log`, `warn`, `error`, `setup_backup_db_user`
- `tests/generated/golden_drift_test.bats` — 6 BATS tests (5 variant drift
  tests + 1 meta test); re-renders each variant and compares sha256 against
  stored fixtures; fails with diff output on mismatch
- `docs/tests/P0-C-golden-behavior-capture.md` — this test report; contains
  the (currently empty) intentional-difference table
- `docs/runbooks/PHASE0_LEDGER.md` — this entry (Entry 008)

### Files intentionally not changed

- `actools.sh` — untouched; zero runtime/generator change
- `installer/*`, `cli/*`, `modules/*`, `profiles/*`, `core/*` — untouched
- `.github/workflows/*` — untouched (CI shellcheck for actools.sh is P0-I)
- `docs/target/phase0/operator/*` — not promoted (remains target-only)
- All other runtime files — untouched

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (all) | as recorded in `docs/architecture/runtime-authority-map.md` | **unchanged** — P0-C is capture-only; no `current` authority moved |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator `actools.sh:795` unedited; golden fixture only captures output |
| Caddyfile | Not touched | generator `actools.sh:663` unedited |
| my.cnf | Not touched | generator `actools.sh:595` unedited |
| Dockerfiles | Not touched | generators `actools.sh:607/624/634` unedited |
| CLI | Not touched | `setup_cli` heredoc `actools.sh:1251-1520` and `cli/actools` unedited |

### Tests run

```bash
# 1. Syntax check
bash -n tests/helpers/capture_golden_outputs.sh       # parses

# 2. Capture all variants
bash tests/helpers/capture_golden_outputs.sh all
# → 5 variants × 7 files = 35 files + 5 SHA256SUMS; all captured

# 3. Determinism check (run capture again; sums must be identical)
bash tests/helpers/capture_golden_outputs.sh default /tmp/golden_verify
diff tests/fixtures/golden/default/SHA256SUMS /tmp/golden_verify/default/SHA256SUMS
# → no diff (deterministic)

# 4. Run drift test suite (all 6 tests must pass)
bats tests/generated/golden_drift_test.bats
# → 6/6 ok

# 5. Verify drift test FAILS on injected change
#    (echo "# DRIFT" >> fixture; bats sees mismatch; restore fixture; bats green)

# 6. Confirm no runtime change
git diff --stat -- ':!docs' ':!tests'
# → empty

# 7. Confirm actools.sh untouched
git diff actools.sh cli/actools installer/ core/ modules/ profiles/
# → empty
```

### Test result

PASS (6/6 bats tests; determinism confirmed; drift detection confirmed)

### Documentation updated

- [x] `docs/tests/P0-C-golden-behavior-capture.md` — test report with captured
  matrix, limitations, and intentional-difference table (currently empty)
- [x] `docs/runbooks/PHASE0_LEDGER.md` — this entry (Entry 008)
- [ ] Runtime authority map — no authority changes this phase
- [ ] Operator target docs — no new docs this phase

### Changelog / release notes

- [ ] CHANGELOG.md — no user-visible change (capture infrastructure only)
- [ ] Release note — n/a
- [x] Test report — `docs/tests/P0-C-golden-behavior-capture.md`
- [ ] Review notes — pending

### Known risks

- **Line-number coupling:** the capture helper uses `sed -n '569,1028p'` and
  `sed -n '1247,1528p'` to extract function bodies.  If `actools.sh` is
  edited in a future phase and the function start lines shift, the helper
  will detect the mismatch via `_assert_fn_range()` and fail loudly before
  producing a wrong capture.  Update `SS_START`/`SS_END`/`SC_START`/`SC_END`
  in the helper at the same time as the actools.sh edit.

- **redis-off depends_on quirk:** With `ENABLE_REDIS=false`, `docker-compose.yml`
  still includes `depends_on: redis: condition: service_started` for php_prod
  and worker_prod (hardcoded in the compose heredoc), even though the redis
  service itself is absent.  This is the current generator behavior; the
  fixture captures it as-is.  P0-G will correct the generator; when it does,
  the `redis-off` fixture must be updated with an intentional-difference entry.

- **Dockerfile.php vs repo copy:** The `Dockerfile.php` fixture captures the
  fallback heredoc generator at actools.sh:624.  In real installs, the repo's
  tracked `Dockerfile.php` is used instead (the heredoc is skipped because the
  file already exists at INSTALL_DIR).  The fixture tests the generator code
  path, not the production path.

### Blockers

None.

### Review Gate decision

Pending — a **separate Opus window** renders APPROVED / NEEDS REVISION / BLOCKED.
Reviewer: confirm the captured variant matrix is complete (both OFF and ON
branches for every toggle appear in the matrix).

### Next safe task

**P0-D — Stage Dispatcher Scaffold** — wire `main()` in `actools.sh` to iterate
`PROFILE_INSTALL_STAGES` via a `run_install_stage`/`resolve_install_stage` loop
(append-only guard, behavior-preserving).  The golden fixtures from P0-C must
remain green after P0-D; any accidental generator change will be caught by
`bats tests/generated/golden_drift_test.bats`.

### Forbidden next scope

No generator/runtime change before Review Gate approval; no promotion of
`docs/target/phase0/operator/`; no CI shellcheck edits (P0-I); no CLI
consolidation (P0-F).

---

## Entry 007 — P0-B · Target Operator Documentation + Documentation Reconciliation

Date: 2026-06-08
Branch: `phase0/P0-B-target-operator-docs`
Commit SHA: (recorded by operator at apply time — see `APPLY-P0-B.md` §4)
Actor / Claude session (model): Coding Window (Sonnet)
Phase: P0-B — Target Operator Documentation
Task prompt source: system prompt P0-B (inline) + `docs/runbooks/HANDOFF-P0-A.md`

### Objective

Write the six operator-facing **target** docs under `docs/target/phase0/operator/`, each
carrying the required `"Phase 0 target contract — not yet released"` status banner. As
documentation reconciliation, correct the stale/false claims recorded by the authority
map in `docs/architecture.md` and `docs/CHANGELOG.md`. Zero runtime change.

### Files changed

New (target operator docs — unreleased behaviour only):

- `docs/target/phase0/operator/README.md` — directory index, promotion gate, cross-links
- `docs/target/phase0/operator/install-community.md` — default `community` install journey
  (5 stages: init → preflight → install → handoff → doctor) with D.0-gap annotations
- `docs/target/phase0/operator/profiles.md` — profile lifecycle, error behaviour, allowed
  profiles, non-bypass rule, community-plus reserved status
- `docs/target/phase0/operator/commands.md` — full command surface as a target contract
  (installer + CLI commands, global flags, profile resolution, out-of-surface list)
- `docs/target/phase0/operator/generated-files.md` — all 6 operator-visible generated
  files with current/target authority, safety rules, golden fixture strategy
- `docs/target/phase0/operator/troubleshooting.md` — symptom-first troubleshooting for
  init, preflight, install, CLI, generated-file, and profile problems

Corrected (documentation reconciliation — no restructure, in-place only):

- `docs/architecture.md` —
  (1) `:3` `v11.2.0+` → `v14.0+` (actual `ACTOOLS_VERSION` per `actools.sh:46`);
  (2) `:9` false "never contains business logic" claim deleted; replaced with accurate
      description: monolithic `actools.sh` is the live spine, `cli/commands/` are the
      operator CLI handlers;
  (3) `:49` `21 bats tests` → `76` (verified: dispatch 33 + init 11 + preflight 6 +
      doctor 5 + validate 11 + secrets 10);
  (4) `:84-89` false `phases_complete` state-machine block replaced with actual
      `init_state()` structure (`{"envs":{}, "db_passes":{}, "backup_user_pass":…}`);
  (5) `:119` `/usr/local/bin/actools-real` example reference corrected to `cli/actools`
      (the canonical CLI source per `docs/architecture/cli-authority-contract.md`)
- `docs/CHANGELOG.md` —
  (1) `:113` false "All Dockerfiles moved to template variables" claim corrected; replaced
      with accurate statement citing live authority `actools.sh:607/624/634` and P0-G
      extraction scope; phrase fully removed (grep gate confirmed clean);
  (2) Added `[Unreleased] / Documentation` section at top recording target docs added
      and architecture reconciliation

Also updated:
- `docs/runbooks/PHASE0_LEDGER.md` — this entry (Entry 007)

### Files intentionally not changed

- `actools.sh` — untouched (zero runtime change)
- `installer/*`, `cli/*`, `modules/*`, `profiles/*`, `core/*` — untouched
- `.github/workflows/*` — untouched
- `docs/architecture/runtime-authority-map.md` — not modified (no authority changes this
  phase; forbidden per P0-B scope)
- `docs/target/phase0/operator/.gitkeep` — remains (directory anchor; not removed)

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (all) | as recorded in `docs/architecture/runtime-authority-map.md` | **unchanged** — P0-B is documentation-only; no `current` authority moved |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator `actools.sh:795` unedited |
| Caddyfile | Not touched | generator `actools.sh:663` unedited |
| my.cnf | Not touched | generator `actools.sh:595` unedited |
| Dockerfiles | Not touched | generators `actools.sh:607/624/634` unedited |
| CLI | Not touched | `setup_cli` heredoc `actools.sh:1251-1520` and `cli/actools` unedited |

### Tests run

```bash
# P0-B is doc-only; checks prove no runtime file was altered and docs are well-formed.
git status --porcelain
    # only docs/ paths appear; actools.sh, installer, core, cli, modules, profiles, tests untouched
grep -rL "Phase 0 target contract" docs/target/phase0/operator/
    # returns only .gitkeep — all authored docs carry the banner
grep -nE '21 bats|never contains business logic|"version": "11\.2|phases_complete' docs/architecture.md
    # empty — no surviving false assertion
grep -n 'moved to template variables' docs/CHANGELOG.md
    # empty
bash -n actools.sh      # parses (untouched)
bash -n cli/actools     # parses (untouched)
```

### Test result

PASS (self-validation): all four grep gates pass. No runtime file changed.

### Documentation updated

- [x] Operator target docs (6 files created under `docs/target/phase0/operator/`)
- [x] `docs/architecture.md` (5 false claims corrected)
- [x] `docs/CHANGELOG.md` (false Dockerfile claim corrected + Unreleased section added)
- [ ] Runtime authority map (not modified — no authority changes this phase)
- [ ] Generated-file contract (not modified — no changes)
- [ ] CLI authority contract (not modified — no changes)
- [ ] Test plan (deferred to P0-C/P0-I)

### Changelog / release notes

- [x] `docs/CHANGELOG.md` — `[Unreleased] / Documentation` section added
- [ ] Release note (n/a — doc-only phase)

### Known risks

- Every target doc is explicitly labelled `unreleased-target`. No doc asserts that
  community-plus is implemented or that target behaviour is currently released.
- The D.0 gap annotations in `install-community.md` and `profiles.md` (P0-E / P0-H scope)
  were written from the authority map's verified evidence; they do not introduce any new
  runtime obligation.
- `docs/architecture.md` was corrected in-place only — no restructuring or expansion.
  The false-claim removal shrinks `:9` but does not alter section order.

### Blockers

None.

### Review Gate decision

Pending — a **separate Sonnet window** renders APPROVED / NEEDS REVISION / BLOCKED.
P0-B is low-risk doc-only; Sonnet is the correct reviewer.

### Next safe task

**P0-C — Golden Fixture Capture** (`06_implementation_phases/P0-C-golden-behavior-capture.md`).
Coding model: **Sonnet**. Render and capture byte-exact golden fixtures for every generated
file across the env matrix (all-in-one, Redis, cAdvisor, S3 on/off). Add `actools.sh` to
CI shellcheck. No generator is touched until the golden net is green.

### Forbidden next scope

- No runtime code change (P0-C is capture-only, not extraction).
- No promotion of `docs/target/phase0/operator/` to `docs/operator/`.
- No community-plus feature work; no `plus_*` module.
- No dispatcher/resolver wiring (that is P0-D/P0-E).
- No generated-file byte change (P0-C captures current bytes; it does not change them).

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. Build-trigger #1 not yet met.

---

## Entry 006 — P0-A · Adopt synthesis + materialize canon and runtime authority map

Date: 2026-06-08  
Branch: `phase0/P0-A-finalise-authority-map`  
Commit SHA: (recorded by operator at apply time — see APPLY-P0-A.md §4)  
Actor / Claude session (model): Phase Conductor (Mode 1), Opus  
Phase: P0-A — Finalise Authority Map  
Task prompt source: `07_prompts/phase-conductor-prompt.md` + `06_implementation_phases/P0-A-finalise-authority-map.md`

> Numbering note: the P0-A phase file's "Done means" predates the planning passes and says
> "ledger has Entry 002"; entries 002–005 were consumed by package-alignment passes, so this
> first *execution* entry is **006**. The intent — "P0-A adds a ledger entry; community-plus
> stays blocked" — is satisfied.

### Objective

Execute **P0-A (doc-only)** together with the **HOW_TO_RUN Step-0 materialization** in one branch/PR:
adopt the verified synthesis (`00_reference/actools-phase0-implementation-plan.md`) **without re-deriving it**;
stand up the in-repo documentation home so every later window's documented read-paths resolve;
record the runtime authority map with **path:line evidence spot-verified read-only** against the repo;
create the **design-canon home** (LOCKED §11 build-trigger #2); and **fold the alignment's five Section-4
tightenings** into the phase prompts they name. No runtime shell/profile/CLI/generated-file change.

### Files changed

New (created on the devbox via quoted heredocs — see APPLY-P0-A.md §2):

- `design/Actools_Drupal_Community_Plus_LOCKED.md` — canon (verbatim) — *build-trigger #2*
- `design/actools-phase0-implementation-plan.md` — adopted synthesis (verbatim) — *build-trigger #2*
- `design/actools-phase0-locked-alignment.md` — alignment errata (verbatim) — *build-trigger #2*
- `design/README.md` — canon-home index; tracker reference note
- `docs/architecture/runtime-authority-map.md` — **filled with verified path:line evidence** (this phase's core artifact)
- `docs/architecture/phase0-seam-contract.md` — materialized (verbatim)
- `docs/architecture/generated-file-contract.md` — materialized (verbatim)
- `docs/architecture/cli-authority-contract.md` — materialized (verbatim)
- `docs/runbooks/PHASE0_LEDGER.md` — **this file**, with Entry 006
- `docs/runbooks/HANDOFF_TEMPLATE.md` — materialized (verbatim)
- `docs/runbooks/HANDOFF-P0-A.md` — the P0-A handoff (next allowed task = P0-B)
- `docs/runbooks/CHANGE_CONTROL.md` — materialized (verbatim)
- `docs/runbooks/DRIFT_PREVENTION_RULES.md` — materialized (verbatim)
- `docs/runbooks/AI_WINDOW_PROTOCOL.md` — materialized (verbatim)
- `docs/runbooks/CLAUDE_EXECUTION_MODEL.md` — materialized (verbatim)
- `docs/target/phase0/README.md` — unreleased-target banner (placeholder; **content authored by P0-B**)
- `docs/target/phase0/operator/.gitkeep` — directory anchor for P0-B
- `docs/reviews/P0-A-pr-body.md` — PR body for this phase

Edited **in the workflow package only** (process docs — not runtime, not in the repo): the alignment
tightenings folded into `06_implementation_phases/P0-D`, `P0-E`, `P0-H`, `P0-I`; this ledger; and
`03_architecture_contracts/runtime-authority-map.md`. Repacked as `actools_phase0_workflow_package_P0A.zip`.

### Files intentionally not changed

- `actools.sh` — untouched (no byte change; remains the live, profile-blind spine)
- `installer/*` (`init.sh`, `preflight.sh`, `handoff.sh`, `dispatch.sh`, `profile.sh`, `output.sh`) — untouched
- `cli/actools`, `cli/commands/*` — untouched (the false `cli/actools:12-15` comment is **left for P0-F**)
- `profiles/*` — untouched (no `profiles/test.profile` added here; that is P0-E/P0-I per S6)
- `modules/*`, `core/*` — untouched
- `.github/workflows/*` — untouched (the "`actools.sh` → shellcheck" edit is **P0-I**, per S2)
- `docs/architecture.md`, `docs/CHANGELOG.md` — the stale/false claims are **left for P0-B/P0-J** (not corrected here)

### Runtime authority changes

| Concern | Before | After |
|---|---|---|
| (all) | as recorded in `docs/architecture/runtime-authority-map.md` | **unchanged** — P0-A moved no `current` authority; it only *recorded* the map |

### Generated-file impact

| File | Unchanged / Changed intentionally / Not touched | Evidence |
|---|---|---|
| docker-compose.yml | Not touched | generator `actools.sh:795` unedited |
| Caddyfile | Not touched | generator `actools.sh:663` unedited |
| my.cnf | Not touched | generator `actools.sh:595` unedited |
| Dockerfiles | Not touched | generators `actools.sh:607/624/634` unedited |
| CLI | Not touched | `setup_cli` heredoc `actools.sh:1251-1520` and `cli/actools` unedited |

### Tests run

````bash
# P0-A is doc-only; the self-checks prove no runtime file was altered and the new docs are well-formed.
# (Conductor self-validated in-sandbox; operator re-runs on the devbox — APPLY-P0-A.md §3.)
bash -n actools.sh                       # still parses (untouched)
bash -n cli/actools                      # still parses (untouched)
git diff --stat -- ':!docs' ':!design'   # MUST be empty: no non-doc change
# markdown link/structure spot-check on the new docs (see APPLY-P0-A.md §3)
````

### Test result

PASS (sandbox self-validation): no runtime/`*.sh`/workflow file changed; new markdown parses and cross-links resolve.

### Documentation updated

- [x] Runtime authority map (filled with verified path:line evidence)
- [ ] Generated-file contract (materialized verbatim; no content change)
- [ ] CLI authority contract (materialized verbatim; no content change)
- [ ] Operator target docs (deferred to P0-B — only the directory + banner placeholder created)
- [ ] Test plan (deferred to P0-C/P0-I)

### Changelog / release notes

- [ ] CHANGELOG.md updated (no — repo `docs/CHANGELOG.md` corrections are P0-B/P0-J scope)
- [ ] Release note added (n/a this phase)
- [ ] Test report added (n/a this phase)
- [x] Review notes prepared (`review/review-gate-P0-A.md` — filled for a separate Sonnet window)

### Known risks

- **Scope-bleed risk:** P0-A bundles HOW_TO_RUN Step-0 materialization with the authority-map record. This is intentional and bounded: every materialized contract/runbook/canon file is a **verbatim** copy of an existing package file (no new authoring); only `runtime-authority-map.md`, this ledger entry, the handoff, and the PR body are authored. The reviewer should confirm no runtime byte moved.
- **Base SHA:** the export carried no `.git`; the operator records the real `main` HEAD at apply time. P0-A is heredoc-only (no `git apply` patch), so it is not base-sensitive.

### Blockers

None.

### Review Gate decision

Pending — a **separate Sonnet window** renders APPROVED / NEEDS REVISION / BLOCKED using `review/review-gate-P0-A.md`. The Conductor prepares the prompt and never renders the verdict.

### Next safe task

**P0-B — Target Operator Documentation** (`06_implementation_phases/P0-B-target-operator-docs.md`). Coding model: **Sonnet**; review: Opus or human. Write the operator-facing target docs under `docs/target/phase0/operator/` (status-banner every file), cross-linking the now-materialized `docs/architecture/*` contracts; correct the false `docs/architecture.md`/`docs/CHANGELOG.md` claims as target-doc reconciliation.

### Forbidden next scope

No runtime code; no tests (beyond doc references); **no promotion to `docs/operator/`**; no `plus_*` / community-plus feature work; no generated-file change; no dispatcher/resolver edits (those begin at P0-D/P0-E).

### Community-plus status

Still **BLOCKED**. Phase 0 not closed. Build-trigger #1 (merged Phase-0 PRs + green CI + fake-profile e2e) not yet met; build-trigger #2 (design-canon home) is **satisfied by this phase** once merged.

---

## Entry 005 — Phase Conductor (Mode 1) + per-phase devbox apply sheet

Date: 2026-06-07  
Phase: Planning  
Actor / Claude session (model): alignment pass

### Objective

Confirmed **Mode 1** (Conductor = sandbox Opus chat window; operator applies on the devbox `~/actoolsDrupal`; no Claude Code; no `nano`). Added `07_prompts/phase-conductor-prompt.md` (the per-phase meta-prompt), `04_runbooks/PHASE_CONDUCTOR_PROTOCOL.md` (four lanes + apply contract + per-phase op map + resolved S1–S8), and `08_changelog_release_templates/DEVBOX_APPLY_SHEET_TEMPLATE.md` (the `APPLY-P0-{X}.md` operator file the Conductor ships at the top of every output.zip: heredoc creates, `git apply --3way` patches, full `git add/commit/push` with an authored commit message, PR command, and the "only you/CI/review can do" + rollback sections). Updated `HOW_TO_RUN.md`/`README.md` to Mode 1; recorded the GitHub remote (`https://github.com/actools-pl/actoolsDrupal`) and devbox path (`/home/veritas/actoolsDrupal`).

### Runtime authority changes

None. Documentation/process only.

### Community-plus status

Still blocked.

---

## Entry 003 — Added operator run-sheet (HOW_TO_RUN.md)

Date: 2026-06-06  
Phase: Planning  
Actor / Claude session (model): alignment pass

### Objective

Added top-level `HOW_TO_RUN.md`: the one-page operating rhythm — Step 0 setup (check out the repo branch; materialize contracts→`docs/architecture/`, runbooks+ledger→`docs/runbooks/`, canon→`design/` which satisfies LOCKED §11 build-trigger #2), the per-phase Claude loop (assign one phase → code → ledger → cross-model Review Gate → approve → next), the phase/model/session map with the P0-C-before-P0-D/P0-G dependency, and closure. Referenced it from `README.md` and `MANIFEST.md`.

### Runtime authority changes

None. Documentation/process only.

### Community-plus status

Still blocked.

---

## Entry 002 — Aligned to Claude execution; reference report swapped

Date: 2026-06-06  
Phase: Planning  
Actor / Claude session (model): alignment pass

### Objective

(1) Align the package to the fact that the whole Phase 0 implementation is executed by **Claude (Opus / Sonnet)**: added `04_runbooks/CLAUDE_EXECUTION_MODEL.md`, specialised `AI_WINDOW_PROTOCOL.md` and the prompts to Claude sessions, and added per-phase model + coding-session assignments to the phase master and each `P0-*` file. (2) Replaced `00_reference/actools_phase0_modularization_deep_review.md` with the verified synthesis `00_reference/actools-phase0-implementation-plan.md` (banner adds the WP-*↔P0-* crosswalk). (3) Added the design-canon-home criterion (LOCKED §11 trigger #2) to the acceptance criteria.

### Runtime authority changes

None. Documentation/process only.

### Community-plus status

Still blocked.

---

## Entry 001 — Package created

Date: 2026-06-06  
Phase: Planning

### Objective

Create a complete workflow package for Phase 0 finalisation, target docs, implementation phases, ledger, prompts, and closure gates.

### Runtime authority changes

None.

### Community-plus status

Still blocked.

