# Handoff — P0-N · CLI DB-Layer Convergence (live `doctor.sh`)

## Repository state

Branch: `phase0/P0-N-cli-db-convergence` (sandbox; operator applies onto `main` @ `cd0d0d9`)
Commit SHA: three implementation commits + one docs commit (sandbox sequence: `7b88539` swap → `e7ba619` live-CLI-path guard → `8d33573` focused authority test → docs). Sandbox baseline `94d9ba8` = the import of `main` @ `cd0d0d9` (P0-M merged, PR #47); substitute `cd0d0d9` when reproducing against the real repo.
Working tree clean? yes (each commit left the full suite green: 230/230 at commits 1–3 — commit 1 is 216 existing tests green; the new suites enter at 2 and 3)
Zip/package name if applicable: n/a (work done in-tree on the imported zip)

## Task completed

P0-N per `P0-N-cli-db-convergence.md`: the live `doctor` command's local
`db_exec_root` copy (`cli/commands/doctor.sh:27` — byte-identical to
`modules/db/core.sh:45`, re-verified including the `:24-26` comment ≡
`core.sh:42-44`) is **deleted**, replaced **in place, 6-for-6 lines**, by a
pointer comment + a source of the P0-M authority. The DB layer now has
exactly one authority across both runtimes; the single call site is
byte-untouched and still literally at `:160`. A live-CLI-path guard
(`tests/guards/cli_db_authority_guard_test.bats`, 7) makes any future
redefinition on the live CLI path fail CI; a focused authority test
(`tests/cli/doctor_db_authority_test.bats`, 7, + loader) pins the
resolution side (source-time definition, `declare -f` byte-equal to
`core.sh`, mock-docker oracle). Verbatim-equivalent swap — **no behavior
change**, no new e2e gate.

### ⚠ One flagged deviation (decision needed at review)

The spec's snippet showed a **bare** `source "${INSTALL_DIR}/modules/db/core.sh"`.
The landed line is **best-effort**:

```sh
source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true
```

Why: a bare top-level source broke **9 existing tests**
(`tests/installer/doctor_test.bats` 4, `tests/test_p0h_dispatch.bats` 2,
`tests/test_p0i_fake_profile_e2e.bats` 3). Those suites stage **minimal
sandbox** `INSTALL_DIR`s (only `installer/output.sh` + the two doctor
files — no `modules/`), and `doctor.sh:37-39` documents exactly that
contract for its other sources ("best-effort: when the env file or
dispatch.sh is absent (e.g. a minimal sandbox)…"). The alternative —
staging `core.sh` into the sandboxes of 5 existing test files — is outside
the spec's allowed-files list. The risk a silent `|| true` could mask (a
mis-pathed module never loading) is pinned **red** by the focused test:
with `INSTALL_DIR` at the repo, `db_exec_root` must come out defined and
byte-equal to `core.sh` (test 4), and the no-module twin (test 6) proves
the definition travels the module path — a typo'd path was demonstrated to
be caught (test report §6). On the live path the module is always present
(the installer itself sources it). The other placement the spec offered
(inside `run_doctor`) was rejected because it changes the definition
timing and makes the spec's own focused-test assertion ("after sourcing,
`type db_exec_root` is defined") unimplementable by plain sourcing; the
in-place top-level spot preserves the old timing exactly, and the spec's
gate for it — `INSTALL_DIR` provably set at `doctor.sh` source time — is
proven (sole consumer `cli/actools:90`; `INSTALL_DIR` resolved at `:7`).

## Files changed

- `cli/commands/doctor.sh` — the 6-for-6 in-place swap (`:24-29`); only hunk in the file; `cli/actools` byte-unchanged
- `tests/guards/cli_db_authority_guard_test.bats` — new (7)
- `tests/cli/doctor_db_authority_test.bats`, `tests/cli/doctor_loader.bash` — new (7 + loader)
- `docs/runbooks/PHASE0_LEDGER.md` — Entry 019 (decision **Pending**) + Entry 018 ratified (merge SHA `cd0d0d9`/#47 stamped; e2e-pending risk resolved; the Entry-017 `wait_db:510` risk flipped to **CLOSED — e2e-confirmed**, run #75 `MariaDB ready.`)
- `docs/architecture/runtime-authority-map.md` — Doctor row + DB-layer row (single authority across both runtimes; Entry-018 e2e confirmation), P0-N test-surface addendum (216 → 230), P0-N answer paragraph; **one doc-truth fix outside the strict ask**: the DB-provisioning row's stale "`install_env` extraction is P0-N+" pointer rewritten for the post-closure renumbering (P0-N became this CLI convergence) — flagged for the Review Gate, mirror of the P0-L `ROADMAP.md` precedent
- `docs/CHANGELOG.md` — P0-N Unreleased section (+ Entry-018 ratification note)
- `docs/releases/P0-N-cli-db-convergence.md`, `docs/tests/P0-N-cli-db-convergence.md`, this handoff

## Files not changed but relevant

- **The eight dead twins** — untouched (P0-O): `backup.sh`, `ci_generate.sh`, `cost_optimize.sh`, `health.sh`, `restore.sh`, `storage.sh`, `update.sh`, `worker.sh`. Their DB-fn copies remain on disk (`cost_optimize.sh:10`, `restore.sh:9,:15`, `update.sh:10`) and are outside the live CLI path — the guard's dead-twin arm pins the exclusion.
- `modules/db/core.sh` — the authority; **no edits** (P0-M contracts 13/13 and both P0-M guards green, untouched)
- `actools.sh`, `main()`, `installer/`, `profiles/`, `.github/workflows/` (recursive bats auto-discovers the new suites), golden fixtures (none modified)

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | none |
| Install stages | none |
| CLI | `doctor`'s DB layer resolves from `modules/db/core.sh` (single authority across installer + CLI); `cli/actools` byte-unchanged; behavior identical |
| Generated files | none |
| Preflight | none |
| Doctor | definition source converged (local copy → module); output unchanged |
| Handoff | none |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | not touched (drift 6/6 at every commit) |
| Caddyfile | not touched (drift 6/6) |
| my.cnf | not touched (drift 6/6) |
| Dockerfiles | not touched (drift 6/6) |
| CLI | not touched (`cli/actools` byte-unchanged; `cli_authority_test.bats` green) |
| /etc/cron.daily/actools-backup | not touched (cron drift 3/3) |

## Tests run

```bash
$ bash -n cli/commands/doctor.sh && bash -n cli/actools && echo SYNTAX_OK
SYNTAX_OK

$ shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 cli/commands/doctor.sh ; echo rc=$?

In cli/commands/doctor.sh line 200:
  latest_backup=$(ls -t "${backups_dir}"/prod_db_*.sql.gz 2>/dev/null | head -1)
                  ^-- SC2012 (info): Use find instead of ls to better handle non-alphanumeric filenames.

For more information:
  https://www.shellcheck.net/wiki/SC2012 -- Use find instead of ls to better ...
rc=1
# ^ pre-existing: the BASELINE file produces the identical finding + rc
#   (git show <baseline>:cli/commands/doctor.sh | shellcheck <same flags> -  → baseline_rc=1)
#   zero new findings from the swap.

$ bats tests/guards/
1..20        # 13 existing + 7 new cli_db_authority — all ok (full listing: test report §4)

$ bats tests/cli/
1..7         # all ok (full listing: test report §4)

$ bats tests/db/
1..13        # all ok — P0-M contracts unaffected

$ bats tests/generated/
1..9         # all ok — drift 6/6 + cron 3/3, no fixture modified

$ bats -r tests/
1..230       # all ok (216 → 230)

$ grep -nE '^db_exec_root\(\)' cli/commands/doctor.sh ; echo rc=$?
rc=1         # EMPTY — the local def is gone

$ grep -nE 'source.*modules/db/core\.sh' cli/commands/doctor.sh
29:source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true

$ for f in db_exec_root db_exec_root_stdin db_dump_container setup_backup_db_user wait_db check_db_creds; do
    grep -nE "^${f}\(\)" cli/actools cli/commands/doctor.sh ; done
(no output — all six greps empty)
```

Full per-test listings, the byte-identity re-verification, the guard-bites
demo, the typo-catch demo, and the minimal-sandbox check are pasted
verbatim in `docs/tests/P0-N-cli-db-convergence.md`.

## Test result

PASS — full suite 230/230; drift 6/6 + cron 3/3 unchanged at every commit;
both new suites non-vacuous (permanent in-CI arms + captured live demos).

## Docs updated

Ledger (Entry 019 + Entry 018 ratification), runtime-authority-map (Doctor
+ DB rows, test-surface addendum, P0-N answer, one flagged doc-truth fix),
CHANGELOG, release note, test report, this handoff.

## Changelog / release notes updated

Yes — `docs/CHANGELOG.md` (P0-N Unreleased), `docs/releases/P0-N-cli-db-convergence.md`.

## Ledger entry

Entry number: **019** (decision: Pending — the Review Gate's call, not marked Approved here). Entry **018** ratified per the spec (SHA stamp + risk flips only; original texts preserved inline for the record).

## Known risks

1. **The `|| true` deviation** (see above — explicit Review Gate confirmation requested). Residual exposure: an install missing `modules/db/core.sh` would show "Database unreachable" in doctor instead of a load error; such an install is already broken (the installer sources `core.sh`), and the e2e doctor-smoke covers the real-install resolution.
2. The guard's live-CLI-set derivation is static (`sed` over `cli/actools`, one level, per the spec). A dynamically-computed source of a command file would evade derivation — a new wiring pattern that phase's review must extend the builder for; the missing-target arm fails loudly on half-wired states.
3. The authority-map DB-provisioning-row rewording (renumbering doc-truth fix) is outside the strict allowed-edit ask for that file — confirm or revert (P0-L `ROADMAP.md` precedent).

## Blockers

None.

## Exact next allowed task

**P0-O** — delete the eight dead twins (deadness proven: `cmd_*` called 0×
in `cli/actools`) + the doc-authority lock.

## Explicitly forbidden scope for next task

No wiring of any dead twin; no edits to `modules/db/core.sh` or the P0-M
contracts/guards without an explicit release note; no generated-file
change; `main()`'s profile source stays until P0-P.

## Review Gate notes

In the order the spec lists — verify offline:

1. **`doctor.sh` sources the module and the local def is gone.**
   `grep -nE '^db_exec_root\(\)' cli/commands/doctor.sh` → empty;
   `grep -n 'source.*modules/db/core\.sh' cli/commands/doctor.sh` → `:29`.
   The whole-file diff vs `cd0d0d9` is one 6-for-6 hunk at `:24-29`.
2. **The resolved `db_exec_root` is byte-identical to `core.sh`.**
   Two proofs: (a) static — the deleted def (baseline `:27-29`) `diff`s
   clean against `core.sh:45-47` (comment `:24-26` ≡ `:42-44` too);
   (b) dynamic — `tests/cli/doctor_db_authority_test.bats` test 4: source
   `doctor.sh` with `INSTALL_DIR` at the repo, `declare -f db_exec_root`
   byte-equal to the module-sourced one; test 7 pins the issued container
   command under the P0-M mock docker.
3. **The live-CLI-path guard bites.** Reproduce the demo: append a
   `db_exec_root() { …; }` definition to `cli/commands/doctor.sh` →
   `bats tests/guards/cli_db_authority_guard_test.bats` fails the main arm
   naming the file and line; revert (sha-verified in the test report §5b).
   The three permanent fixture arms (tests 4–6) bite on every CI run.
4. **Drift 6/6 + cron 3/3** — `bats tests/generated/` → 9/9, no fixture
   modified (`git diff cd0d0d9 -- tests/fixtures/` empty).
5. **The eight dead twins untouched** —
   `git diff cd0d0d9 --stat -- cli/commands/` shows only `doctor.sh`.
6. **The doctor-smoke passes** — branch `e2e.yml` dispatch recommended
   (not gating; P0-N adds no new e2e gate): `actools doctor` header +
   `--deep` in-development gate, unchanged. Not run in the sandbox (no
   docker daemon / cloud token) — flagged, not guessed.

Plus the flagged items: the `|| true` deviation (Known risk 1) and the
authority-map doc-truth fix (Known risk 3). The patch reproduces the tree
from `cd0d0d9` + the four commits. **APPROVE on green** per the spec.
