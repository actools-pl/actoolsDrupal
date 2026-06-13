# Release note — P0-O · Orphan Disposition + Doc-Authority Lock

Phase: P0-O (post-closure track) · Date: 2026-06-13 · `ACTOOLS_VERSION` unchanged at `14.0`

## What shipped

1. **The eight dead twin command files under `cli/commands/` are deleted.**
   `cli/commands/{backup,ci_generate,cost_optimize,health,restore,storage,update,worker}.sh`
   (425 lines) were the original per-file CLI design that `cli/actools`
   superseded by **inlining** every user-facing command — `worker-logs`
   (`:103`), `storage-test` (`:117`), `update` (`:163`), `backup` (`:197`),
   `health` (`:199`), `restore` (`:241`). Their `cmd_*`/`run_*` functions were
   called **0×** in `cli/actools`; the profile resolver only ever resolves
   `doctor_deep`; and three of them carried **inert byte-identical copies** of
   the P0-M DB functions (`cost_optimize.sh:10` `db_exec_root`; `restore.sh:9`
   `db_exec_root` + `:15` `db_exec_root_stdin`; `update.sh:10`
   `db_dump_container`) — copies that never ran because the files were never
   sourced. Deleting the files removes that orphan dual-truth **at the root**.
   `cli/commands/` now holds only the two live handler files, `doctor.sh` +
   `doctor_deep.sh`. The one surviving textual reference is the **dead glob**
   `"${INSTALL_DIR}"/cli/commands/*.sh` at `modules/ai/assistant.sh:30`
   (`modules/ai` is itself dead — no `ai` branch in `cli/actools`, nothing live
   sources it — and is **out of scope**, a future pass); the glob now resolves
   to only the two live handlers. The per-file grep proof is otherwise empty
   across `*.sh`/`*.yml`/`*.bats`.

2. **The P0-N CLI DB-authority guard is tightened to a repo-wide-CLI
   invariant** (`tests/guards/cli_db_authority_guard_test.bats`). With the only
   DB-fn-copy violators now gone, the guard no longer needs an allow/deny list:
   the `DEAD_TWINS` array and the "excluded by construction" arm are removed and
   replaced by a stronger, **list-free** oracle, `_assert_repo_wide_cli_db_authority`,
   which scans **every** regular file in `cli/commands/` (`find -maxdepth 1
   -type f`) and fails on any `^name()` definition of the six canonical DB
   names — caught the moment it lands, before anything wires it in. The full
   P0-N **live-CLI machinery is retained** (the `build_live_cli_set` derivation,
   the `_assert_cli_db_authority` oracle, the live-CLI-set + authority sanity
   arms, the main live arm, and all three live non-vacuity arms), because the
   live arm covers `cli/actools` itself, which the `cli/commands`-only repo-wide
   arm does not see. Net **−1 arm, +2 arms** (7 → 8 in this file): the main
   repo-wide arm (green — only `doctor.sh` + `doctor_deep.sh` remain, neither
   defines a DB name) and a permanent repo-wide non-vacuity arm (a rogue
   `cli/commands/` fixture the live path would never source → the oracle bites,
   naming the file). Non-vacuity was additionally demonstrated live: re-adding a
   `db_exec_root` definition to `cli/commands/doctor.sh` fails **both** the
   live-CLI arm and the repo-wide arm at the exact line (`:258`); reverted
   byte-identical (sha `ac5eda8c…`).

3. **The narrow operator/architecture doc surface is reconciled** so nothing
   points at a deleted file. `docs/advanced.md`'s CI/CD section no longer
   presents the deleted `cli/commands/ci_generate.sh` as where "the code lives"
   — it is restated as a planned/experimental design reference with **no
   implementation behind it**, noting the placeholder was removed in P0-O and
   the feature stays planned; `ci` and `cost-optimize` stay marked "not a
   registered command" (the P0-J disposition is preserved). In
   `docs/architecture/runtime-authority-map.md` the **Worker-provisioning** row
   repoints the worker CLI authority from the deleted `cli/commands/worker.sh`
   to the inline `cli/actools` command (`worker-logs` `:103`), recording the
   P0-O deletion, and **one** command-authority blockquote is added before the
   "Verified secondary facts" header: the authoritative command list is
   `cli/actools`'s dispatch (all inline), and `cli/commands/` is not a command
   registry. Historical phase records (the P0-N narrative lines, `HANDOFF-P0-L`,
   older `LEDGER` entries, `tests/P0-N`/`tests/P0-L`) are left **verbatim**.

## Operator impact

None. Every user-facing command (`backup`, `storage`, `worker`, `health`,
`update`, `restore`) is implemented **inline in `cli/actools`** and is
untouched — only the dead duplicate *files* were deleted. `cli/actools` is
**byte-identical** to baseline (SHA-256 `d2c64c9…`); nothing generated changed
(drift 6/6 + cron 3/3, no fixture modified); the two live handlers (`doctor.sh`,
`doctor_deep.sh`) are untouched and `doctor` still resolves its DB layer from
`modules/db/core.sh` (the P0-N convergence holds — `tests/cli/` 7/7).

## Gate status

**No new e2e gate** — P0-O is dead-code removal, not a behavior change. Because
the eight files are provably unreachable (`cmd_*` called 0× in `cli/actools`;
empty grep proof; never sourced), their deletion cannot alter runtime behavior.
The recommended backstop is the existing post-merge e2e (install reaches
`MariaDB ready.` + `actools doctor` works on a real install) — recommended on
the branch, **not required for approval**. P0-N's Entry 019 was ratified in this
phase: merge SHA `6a6671c` (#48) stamped; the live-CLI-path guard confirmed
biting and the `|| true` deviation reviewed and accepted (see the ledger).

## Test-suite note (review-sandbox honesty)

The full recursive suite is **231** at HEAD (up from the 230 baseline — the
intended net delta: −1 dead-twin arm, +2 repo-wide arms). In a jq-provisioned
environment (CI) the suite is **231/231 green**. This review sandbox could not
install `jq` (apt 404 + the GitHub-releases CDN 403), so **12 jq-dependent
`tests/core/` tests** (state/secrets JSON round-trips) report `not ok` — and a
git-worktree A/B confirmed those same 12 fail **identically** at the P0-O
baseline (`4e2f620`: 230 plan / 218 ok / 12 not-ok) and at HEAD (`231` plan /
`219` ok / 12 not-ok). They are pre-existing and **outside P0-O scope**; P0-O
adds exactly **+1 passing test**. See the test report and `HANDOFF-P0-O.md`.
