# Test report — P0-O · Orphan Disposition + Doc-Authority Lock

Phase: P0-O · Date: 2026-06-13 · Result: **PASS** (P0-O-relevant suites green at every commit; the tightened guard proven non-vacuous — a permanent repo-wide rogue-fixture arm plus a captured live inject-and-revert demo that bites **both** oracles; `cli/actools` byte-identical; drift 6/6 + cron 3/3 unchanged; no new e2e gate — dead-code removal, not a behavior change). Full recursive suite **230 → 231** (the intended delta: −1 dead-twin arm, +2 repo-wide arms). Review-sandbox caveat: 12 pre-existing jq-environmental `tests/core/` failures, identical at baseline and HEAD — see §10.

## 1. Suite summary

| Suite | Tests | Result |
|---|---|---|
| `tests/guards/cli_db_authority_guard_test.bats` (tightened) | 8 | PASS — incl. the new repo-wide main arm + its rogue-fixture non-vacuity arm |
| `tests/guards/` (whole directory) | 21 | PASS (13 sibling guards + 8 tightened cli_db_authority) |
| `tests/cli/doctor_db_authority_test.bats` | 7 | PASS — the P0-N focused test is unaffected (doctor still resolves `core.sh`) |
| `tests/db/db_contract_test.bats` | 13 | PASS — P0-M contracts unaffected |
| `tests/generated/` (compose drift + cron drift) | 9 | PASS — **no fixture modified** (drift 6/6 + cron 3/3) |
| Full recursive suite `bats -r tests/` | **231** | 219 ok + 12 jq-environmental not-ok (§10); CI (jq-provisioned) is 231/231 |

## 2. Deadness proof — the eight files were unreachable

The user-facing commands are **inline in `cli/actools`**; the eight files were
never sourced and their functions never called:

```
$ ls cli/commands/
doctor.sh
doctor_deep.sh

$ for f in backup ci_generate cost_optimize health restore storage update worker; do
    grep -rIn "cli/commands/$f\.sh\|/$f\.sh" . --include='*.sh' --include='*.yml' --include='*.bats' | grep -v '\.git/'
  done
(no output — empty; no live reference to any deleted twin)
```

`cli/actools`'s own dispatch carries every command inline — `worker-logs:103`,
`storage-test:117`, `update:163`, `backup:197`, `health:199`, `restore:241` —
and sources **only** `cli/commands/doctor.sh` (at `:90`, via the resolver),
never the eight twins. The one surviving textual reference is the dead glob at
`modules/ai/assistant.sh:30` (`"${INSTALL_DIR}"/cli/commands/*.sh`); `modules/ai`
is dead and out of scope (a future pass), and the glob now resolves to the two
live handlers.

## 3. The deletion (the 8-file `git rm`)

```
$ git diff 4e2f620 --stat -- cli/commands/
 cli/commands/backup.sh        |   8 ---
 cli/commands/ci_generate.sh   |  84 --------------------------
 cli/commands/cost_optimize.sh | 134 ------------------------------------------
 cli/commands/health.sh        |  36 ------------
 cli/commands/restore.sh       |  52 ----------------
 cli/commands/storage.sh       |  35 -----------
 cli/commands/update.sh        |  43 --------------
 cli/commands/worker.sh        |  33 -----------
 8 files changed, 425 deletions(-)
```

The three inert DB-fn copies that went with them (proof they were never on a
live path — the P0-M guard's live arm was green before deletion too):
`cost_optimize.sh:10` `db_exec_root`; `restore.sh:9` `db_exec_root` + `:15`
`db_exec_root_stdin`; `update.sh:10` `db_dump_container`.

## 4. `cli/actools` byte-identity (the inline commands are untouched)

```
$ sha256sum cli/actools
d2c64c94526b2347da93a390baa293ee4abd4fe5e987b16900744c19355a3ebf  cli/actools
# ^ identical to the recorded baseline SHA — only the dead duplicate FILES were deleted
```

## 5. Syntax

```
$ bash -n cli/actools && echo SYNTAX_OK
SYNTAX_OK
```

## 6. Spec test matrix (verbatim)

```
$ bats tests/guards/
1..21
ok 1 live-CLI-set sanity: cli/actools plus its sourced command files (doctor.sh today)
ok 2 authority sanity: modules/db/core.sh defines all six canonical DB functions
ok 3 no DB-layer function is defined on the live CLI path (authority: modules/db/core.sh)
ok 4 non-vacuous: an injected db_exec_root definition on a live command file FAILS the check
ok 5 non-vacuous: an injected definition on cli/actools itself FAILS the check
ok 6 non-vacuous: a missing live source target FAILS the check (wrong wiring is loud)
ok 7 no DB-layer function is defined on ANY cli/commands file (repo-wide CLI, authority: modules/db/core.sh)
ok 8 non-vacuous: an injected db_exec_root definition on a rogue cli/commands file FAILS the repo-wide check
ok 9 generated backup cron uses mariadb-dump --defaults-extra-file= (secure shape)
ok 10 generated backup cron passes no DB password on argv (full shape check)
ok 11 non-vacuous: an argv-password cron FAILS the shape check
ok 12 live setup_backup_cron source carries the secure heredoc and no argv-password text
ok 13 each risky core function is defined exactly once on the live install path
ok 14 no risky core function is defined in both actools.sh and a sourced core module
ok 15 twin ban: no risky core function is defined in both actools.sh and any core module
ok 16 closure sanity: the builder resolves the known live install path
ok 17 every file declaring LIVE AUTHORITY is sourced on the live install path
ok 18 wait_db source uses the umask-077 --defaults-extra-file probe (secure shape)
ok 19 wait_db source passes no DB password on argv (full shape check)
ok 20 non-vacuous: an argv-password wait_db FAILS the shape check
ok 21 behavioral: live wait_db keeps the root password off every argv (stdin-only) and still issues the write-check

$ bats tests/cli/
1..7
ok 1 doctor.sh carries no local db_exec_root definition (the P0-N deletion holds)
ok 2 doctor.sh sources the P0-M authority (modules/db/core.sh)
ok 3 sourcing doctor.sh is inert — rc 0, no output (pure defs + inert module source)
ok 4 after sourcing doctor.sh, db_exec_root is defined and its body matches core.sh (byte-equal declare -f)
ok 5 all six DB-layer functions arrive from the module (five inert extras included)
ok 6 non-vacuous: without the module on disk, sourcing doctor.sh defines NO db_exec_root (the definition provably comes from ${INSTALL_DIR}/modules/db/core.sh)
ok 7 oracle: the resolved db_exec_root issues the canonical command under the P0-M mock docker

$ bats tests/db/
1..13
ok 1 loader: the six DB functions load from exactly one live origin
ok 2 db_exec_root: invokes docker exec -i actools_db sh -c mariadb as root with the query
ok 3 db_exec_root: no password material on the host argv (container env only)
ok 4 db_exec_root: stdin (heredoc SQL) reaches the container client
ok 5 db_exec_root_stdin: pipes stdin into root mariadb against the positional database
ok 6 db_dump_container: runs the dump via a umask-077 --defaults-extra-file inside the container
ok 7 db_dump_container: backup password travels on stdin, never on argv
ok 8 setup_backup_db_user: waits for the DB, then issues the exact backup-user SQL
ok 9 setup_backup_db_user: end-to-end through db_exec_root — SQL on the container client stdin, password never on argv
ok 10 wait_db: polls the write-check until the DB answers, then returns 0
ok 11 wait_db: gives up via error() after 50 failed probes (bounded)
ok 12 check_db_creds: probes root auth with SELECT 1 through db_exec_root
ok 13 check_db_creds: fails via error() when root auth is rejected

$ bats tests/generated/
1..9
ok 1 backup cron: re-render matches golden fixture byte-for-byte (no drift)
ok 2 backup cron: stored SHA256SUMS manifest is self-consistent
ok 3 backup cron: fixture bakes no secret (password is read from state at runtime)
ok 4 variant 'default' matches golden fixture (no drift)
ok 5 variant 'redis-off' matches golden fixture (no drift)
ok 6 variant 's3-on' matches golden fixture (no drift)
ok 7 variant 'cadvisor-on' matches golden fixture (no drift)
ok 8 variant 'all-in-one' matches golden fixture (no drift)
ok 9 fixture directory contains all 5 expected variants

$ bats -r tests/ | grep -E '^1\.\.' | head -1
1..231

$ bats -r tests/ 2>&1 | grep -cE "^ok"
219
$ bats -r tests/ 2>&1 | grep -cE "^not ok"
12     # all in tests/core/ — jq-environmental, see §10
```

## 7. Guard tightening — what changed in the arms

```
$ git diff 4e2f620 HEAD --stat -- tests/guards/cli_db_authority_guard_test.bats
 tests/guards/cli_db_authority_guard_test.bats | 167 +++++++++++++++++---------
 1 file changed, 112 insertions(+), 55 deletions(-)
```

- **Removed:** the `DEAD_TWINS` array and the `7  the eight dead twins are
  excluded by construction (guard green pre-P0-O)` arm — no twins remain to
  exclude.
- **Added:** `_assert_repo_wide_cli_db_authority <repo>` (iterates `find "$dir"
  -maxdepth 1 -type f` over `cli/commands/`, fails on any `^name()` DB-fn
  definition, printing `cli/commands/<basename>:N: name() defined`) and two
  arms — the main repo-wide arm (arm 7 above) and the rogue-fixture non-vacuity
  arm (arm 8 above).
- **Retained (P0-N live-CLI machinery):** `build_live_cli_set`,
  `_assert_cli_db_authority`, the live-CLI-set + authority sanity arms (1, 2),
  the main live arm (3), the three live non-vacuity arms (4, 5, 6). The live
  arm covers `cli/actools`, which the `cli/commands`-only repo-wide arm does not
  see — both oracles are kept on purpose.

## 8. Live guard non-vacuity — inject-and-revert demo (captured; reverted sha-verified)

Doctoring: a `db_exec_root` definition appended to the real
`cli/commands/doctor.sh` (line 258). Both the main **live-CLI** arm (3) and the
main **repo-wide** arm (7) must fail at the same file:line. Output verbatim:

```
=== pre-inject: doctor.sh sha ===
ac5eda8c55e43b17f34ffc1e5bc4db0830bce2c9134439756ab3c6377b4119fe  cli/commands/doctor.sh

=== guard run on the DOCTORED tree (expected: arms 3 + 7 fail at :258) ===
1..8
ok 1 live-CLI-set sanity: cli/actools plus its sourced command files (doctor.sh today)
ok 2 authority sanity: modules/db/core.sh defines all six canonical DB functions
not ok 3 no DB-layer function is defined on the live CLI path (authority: modules/db/core.sh)
# (from function `_assert_cli_db_authority' in file tests/guards/cli_db_authority_guard_test.bats, line 115,
#  in test file tests/guards/cli_db_authority_guard_test.bats, line 196)
#   `_assert_cli_db_authority "$REPO"' failed
# DB-layer function DEFINED on the live CLI path:
#   cli/commands/doctor.sh:258: db_exec_root() defined
#
# The six DB functions have exactly ONE authority: modules/db/core.sh
# (P0-M). A live CLI file must source the module, never redefine —
# a local copy is the dual-truth P0-N removed from doctor.sh: a fix
# to the module would silently not reach the copy.
ok 4 non-vacuous: an injected db_exec_root definition on a live command file FAILS the check
ok 5 non-vacuous: an injected definition on cli/actools itself FAILS the check
ok 6 non-vacuous: a missing live source target FAILS the check (wrong wiring is loud)
not ok 7 no DB-layer function is defined on ANY cli/commands file (repo-wide CLI, authority: modules/db/core.sh)
# (from function `_assert_repo_wide_cli_db_authority' in file tests/guards/cli_db_authority_guard_test.bats, line 151,
#  in test file tests/guards/cli_db_authority_guard_test.bats, line 276)
#   `_assert_repo_wide_cli_db_authority "$REPO"' failed
# DB-layer function DEFINED on a cli/commands file (repo-wide CLI scan):
#   cli/commands/doctor.sh:258: db_exec_root() defined
#
# The six DB functions have exactly ONE authority: modules/db/core.sh
# (P0-M). No cli/commands file may define them — P0-O deleted the dead
# twins that once did; a CLI command must source the module, never copy.
ok 8 non-vacuous: an injected db_exec_root definition on a rogue cli/commands file FAILS the repo-wide check
guard_exit=1

=== revert (git checkout) ===
reverted byte-identical: sha256 ac5eda8c55e43b17f34ffc1e5bc4db0830bce2c9134439756ab3c6377b4119fe
line count back to 256
=== guard green again ===
ok 7 no DB-layer function is defined on ANY cli/commands file (repo-wide CLI, authority: modules/db/core.sh)
ok 8 non-vacuous: an injected db_exec_root definition on a rogue cli/commands file FAILS the repo-wide check
guard_exit=0; tree clean
```

The tightening's value over the P0-N exclusion arm: a DB-fn copy reintroduced on
**any** `cli/commands/` file is now caught the moment it lands — before anything
wires it onto the live path — rather than relying on a maintained allow-list.

## 9. Doc reconciliation (minimal; no history rewritten)

```
$ git diff 4e2f620 HEAD -- docs/advanced.md
@@ -103,7 +103,7 @@ ## CI/CD generation
-> **Experimental — not wired.** `actools ci …` is **not** a registered command. The code lives in `cli/commands/ci_generate.sh` (unsourced). Design reference only.
+> **Experimental — not wired.** `actools ci …` is **not** a registered command — design reference only, with no implementation behind it. (The unsourced `cli/commands/ci_generate.sh` placeholder was removed in P0-O; the feature stays planned.)

$ git diff 4e2f620 HEAD -- docs/architecture/runtime-authority-map.md
# Worker-provisioning row: worker CLI authority repointed from the deleted
#   cli/commands/worker.sh twin to the inline cli/actools command (worker-logs :103),
#   noting "deleted in P0-O".
# + one Command-authority blockquote added just before "## Verified secondary facts":
#   the authoritative command list is cli/actools's dispatch (all inline);
#   cli/commands/ is not a command registry — after P0-O it holds only doctor.sh +
#   doctor_deep.sh; the eight named twins were deleted (cmd_* called 0×).
# Historical phase records (P0-N narrative, HANDOFF-P0-L, older LEDGER, tests/P0-*) left verbatim.
```

## 10. Review-sandbox jq caveat (not a regression — proven by an A/B at the baseline)

`jq` could not be installed in this review sandbox (apt 404; the GitHub-releases
CDN returns 403; `node-jq`'s postinstall download is 403 too). `jq` is used only
by `tests/core/` (state/secrets JSON round-trips) — **outside P0-O scope**. The
12 `not ok` are therefore environmental. A git-worktree A/B in the **same**
jq-less environment confirms they pre-exist P0-O exactly:

```
=== BASELINE 4e2f620 (import of main @ 6a6671c) ===
plan:   1..230
ok:     218
not ok: 12      # tests 27-32 (secrets), 37-45 (state) — jq-dependent

=== HEAD (P0-O) ===
plan:   1..231
ok:     219
not ok: 12      # the SAME 12 tests, identical list
```

Net effect of P0-O: **+1 passing test** (218 → 219 ok; 230 → 231 total) and the
12 jq failures unchanged. The 12 not-ok by name (identical at both trees):

```
not ok 27 get_db_pass generates and persists a 22-char password for a fresh env
not ok 28 get_db_pass is stable — the second call returns the persisted password
not ok 29 get_db_pass returns a pre-existing stored password verbatim
not ok 30 get_db_pass keeps per-env passwords independent
not ok 31 get_backup_pass generates and persists a 22-char password when unset
not ok 32 get_backup_pass is stable across calls
not ok 37 init_state creates the empty state skeleton
not ok 38 init_state is idempotent — it never clobbers an existing state file
not ok 39 set_state and get_state round-trip a value through jq
not ok 40 set_state writes atomically and leaves valid JSON
not ok 44 mark_installed flips is_installed to true and persists envs.<env>=true
not ok 45 mark_installed for one env does not mark another
```

On CI (jq provisioned) the full suite is **231/231 green**.

## 11. No-behavior-change argument

1. The eight files were **dead**: `cmd_*`/`run_*` called **0×** in `cli/actools`
   (§2); never sourced (the dispatch sources only `doctor.sh` at `:90`); the
   resolver only ever resolves `doctor_deep`. Deleting unreachable files cannot
   change runtime behavior.
2. Every **user-facing** command (`backup`, `storage`, `worker`, `health`,
   `update`, `restore`) is **inline** in `cli/actools`, which is **byte-identical**
   to baseline (§4) — the commands themselves are untouched.
3. The three inert DB-fn copies on the deleted twins never ran (the files were
   never sourced; the P0-M live duplicate-function guard was green before
   deletion — `tests/guards/` arm 13 "exactly once on the live install path").
4. The two live handlers (`doctor.sh`, `doctor_deep.sh`) are untouched; `doctor`
   still resolves its DB layer from `modules/db/core.sh` (P0-N holds —
   `tests/cli/` 7/7).
5. Nothing generated changed: drift 6/6 + cron 3/3, **no fixture modified**
   (`git diff 4e2f620 -- tests/fixtures/` empty).
6. The guard change is test-only (a CI invariant); the doc changes are
   prose-only. Neither touches a runtime path.
7. Integration backstop: the existing post-merge e2e (install reaches `MariaDB
   ready.` + `actools doctor` on a real install). Not run in the sandbox (no
   docker daemon / cloud token) — recommended branch dispatch, **not gating**;
   P0-O introduces no new e2e gate.
