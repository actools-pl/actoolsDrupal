# Test report — P0-N · CLI DB-Layer Convergence (live `doctor.sh`)

Phase: P0-N · Date: 2026-06-12 · Result: **PASS** (full suite 230/230 at every commit; drift 6/6 + cron 3/3 unchanged; the live-CLI-path guard and the focused authority test both proven non-vacuous — permanent in-CI arms plus captured live demos; no new e2e gate — not a behavior change)

## 1. Suite summary

| Suite | Tests | Result |
|---|---|---|
| `tests/guards/cli_db_authority_guard_test.bats` (new) | 7 | PASS — incl. three permanent non-vacuity arms |
| `tests/cli/doctor_db_authority_test.bats` (new) | 7 | PASS — incl. the no-module non-vacuity twin + mock-docker oracle |
| `tests/guards/` (whole directory) | 20 | PASS (13 existing + 7 new) |
| `tests/db/db_contract_test.bats` | 13 | PASS — P0-M contracts unaffected |
| `tests/generated/` (compose drift + cron drift) | 9 | PASS at every commit — **no fixture modified** (drift 6/6 + cron 3/3) |
| Full recursive suite `bats -r tests/` | **230** | PASS (216 → 230: +7 guard, +7 cli) |

## 2. Byte-identity re-verification (the deleted local def ≡ the authority)

> **SHA mapping for reproduction:** `94d9ba8` is the sandbox import commit of
> `main` @ `cd0d0d9` (P0-M merged, PR #47) — the tree is identical. On the
> real repository substitute `cd0d0d9` in every command below.

Re-verified against the baseline tree (pre-swap `doctor.sh` from git history) — both the function and its comment:

```
$ diff <(git show 94d9ba8:cli/commands/doctor.sh | sed -n 27,29p) <(sed -n 45,47p modules/db/core.sh) && echo DEF_BYTE_IDENTICAL
DEF_BYTE_IDENTICAL
$ diff <(git show 94d9ba8:cli/commands/doctor.sh | sed -n 24,26p) <(sed -n 42,44p modules/db/core.sh) && echo COMMENT_BYTE_IDENTICAL
COMMENT_BYTE_IDENTICAL
```

The swap itself is the only hunk in `doctor.sh` — 6 lines deleted, 6 inserted at the same spot, so the single call site is still literally at `:160` and byte-untouched:

```
$ git diff 94d9ba8 -- cli/commands/doctor.sh | grep -cE '^[+-][^+-]'
12
$ grep -n 'if db_exec_root' cli/commands/doctor.sh
160:  if db_exec_root \
```

## 3. Syntax + shellcheck (no delta vs baseline)

```
$ bash -n cli/commands/doctor.sh && bash -n cli/actools && echo SYNTAX_OK
SYNTAX_OK

$ shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 cli/commands/doctor.sh ; echo rc=$?

In cli/commands/doctor.sh line 200:
  latest_backup=$(ls -t "${backups_dir}"/prod_db_*.sql.gz 2>/dev/null | head -1)
                  ^-- SC2012 (info): Use find instead of ls to better handle non-alphanumeric filenames.

For more information:
  https://www.shellcheck.net/wiki/SC2012 -- Use find instead of ls to better ...
rc=1
$ git show 94d9ba8:cli/commands/doctor.sh | shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 - ; echo baseline_rc=$?   # baseline (pre-swap) doctor.sh, same command

In - line 200:
  latest_backup=$(ls -t "${backups_dir}"/prod_db_*.sql.gz 2>/dev/null | head -1)
                  ^-- SC2012 (info): Use find instead of ls to better handle non-alphanumeric filenames.

For more information:
  https://www.shellcheck.net/wiki/SC2012 -- Use find instead of ls to better ...
baseline_rc=1
```

The single finding (info-level SC2012 at `:200`) pre-exists the phase — identical on the baseline file; rc parity 1 == 1, zero new findings.

## 4. Spec test matrix (verbatim)

```
$ bats tests/guards/
1..20
ok 1 live-CLI-set sanity: cli/actools plus its sourced command files (doctor.sh today)
ok 2 authority sanity: modules/db/core.sh defines all six canonical DB functions
ok 3 no DB-layer function is defined on the live CLI path (authority: modules/db/core.sh)
ok 4 non-vacuous: an injected db_exec_root definition on a live command file FAILS the check
ok 5 non-vacuous: an injected definition on cli/actools itself FAILS the check
ok 6 non-vacuous: a missing live source target FAILS the check (wrong wiring is loud)
ok 7 the eight dead twins are excluded by construction (guard green pre-P0-O)
ok 8 generated backup cron uses mariadb-dump --defaults-extra-file= (secure shape)
ok 9 generated backup cron passes no DB password on argv (full shape check)
ok 10 non-vacuous: an argv-password cron FAILS the shape check
ok 11 live setup_backup_cron source carries the secure heredoc and no argv-password text
ok 12 each risky core function is defined exactly once on the live install path
ok 13 no risky core function is defined in both actools.sh and a sourced core module
ok 14 twin ban: no risky core function is defined in both actools.sh and any core module
ok 15 closure sanity: the builder resolves the known live install path
ok 16 every file declaring LIVE AUTHORITY is sourced on the live install path
ok 17 wait_db source uses the umask-077 --defaults-extra-file probe (secure shape)
ok 18 wait_db source passes no DB password on argv (full shape check)
ok 19 non-vacuous: an argv-password wait_db FAILS the shape check
ok 20 behavioral: live wait_db keeps the root password off every argv (stdin-only) and still issues the write-check

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

$ bats -r tests/ | tail -3   # (full output: 230 lines, all ok)
ok 228 community routes through NONE of the P0-I markers
ok 229 profiles/test.profile is pure data (no executable side effects) when sourced via the loader
ok 230 guard: actools.sh is executable (exec-bit standing guard — the P0-G regression)

$ bats -r tests/ 2>&1 | grep -cE "^ok"
230

$ grep -nE '^db_exec_root\(\)' cli/commands/doctor.sh ; echo rc=$?                    # EMPTY
rc=1

$ grep -nE 'source.*modules/db/core\.sh' cli/commands/doctor.sh                 # present
29:source "${INSTALL_DIR}/modules/db/core.sh" 2>/dev/null || true

$ for f in db_exec_root db_exec_root_stdin db_dump_container setup_backup_db_user wait_db check_db_creds; do grep -nE "^${f}\(\)" cli/actools cli/commands/doctor.sh ; done ; echo overall_empty_rc_per_grep=1   # EMPTY
(no output — all six greps empty)
```

## 5. Live-CLI-path guard — non-vacuity

### 5a. Permanent in-CI arms

Three fixture arms run on every CI pass (tests 4–6 above): an injected `db_exec_root` on a simulated live command file, an injected `wait_db` on a simulated `cli/actools`, and a deleted live source target — each must fail the **same oracle** the main arm uses, and each self-checks that its doctoring took.

### 5b. Live injection demo (captured; reverted sha-verified)

Doctoring: the old `db_exec_root` definition appended to the real `cli/commands/doctor.sh`. Output verbatim:

```
=== guard run on the DOCTORED LIVE TREE (expected: main arm fails) ===
1..7
ok 1 live-CLI-set sanity: cli/actools plus its sourced command files (doctor.sh today)
ok 2 authority sanity: modules/db/core.sh defines all six canonical DB functions
not ok 3 no DB-layer function is defined on the live CLI path (authority: modules/db/core.sh)
# (from function `_assert_cli_db_authority' in file tests/guards/cli_db_authority_guard_test.bats, line 112,
#  in test file tests/guards/cli_db_authority_guard_test.bats, line 157)
#   `_assert_cli_db_authority "$REPO"' failed
# DB-layer function DEFINED on the live CLI path:
#   cli/commands/doctor.sh:257: db_exec_root() defined
#
# The six DB functions have exactly ONE authority: modules/db/core.sh
# (P0-M). A live CLI file must source the module, never redefine —
# a local copy is the dual-truth P0-N removed from doctor.sh: a fix
# to the module would silently not reach the copy.
ok 4 non-vacuous: an injected db_exec_root definition on a live command file FAILS the check
ok 5 non-vacuous: an injected definition on cli/actools itself FAILS the check
ok 6 non-vacuous: a missing live source target FAILS the check (wrong wiring is loud)
ok 7 the eight dead twins are excluded by construction (guard green pre-P0-O)
=== revert ===
reverted byte-identical: sha256 ac5eda8c55e43b17f34ffc1e5bc4db0830bce2c9134439756ab3c6377b4119fe
1..7
guard green again
```

## 6. Focused authority test — the best-effort source is typo-proof

The landed source line is best-effort (`2>/dev/null || true`; see the release note's flagged-deviation section). Its non-vacuity: in a sandbox **without** the module, sourcing `doctor.sh` defines **no** `db_exec_root` (test 6 above), so the definition provably arrives via `${INSTALL_DIR}/modules/db/core.sh` — and a mis-pathed source therefore fails the resolution arm (test 4). Demonstrated live on a doctored copy with the path typo'd to `module/db/core.sh` (modules/ present on disk):

```
=== doctored copy: source path typo'd to module/db/core.sh (modules/ present) ===
29:source "${INSTALL_DIR}/module/db/core.sh" 2>/dev/null || true
db_exec_root NOT defined -> the focused test resolution arm (test 4) would FAIL on this tree: typo CAUGHT
```

## 7. Minimal-sandbox contract (why the deviation exists)

A bare top-level `source` (the spec snippet) broke 9 existing tests — `tests/installer/doctor_test.bats` (4), `tests/test_p0h_dispatch.bats` (2), `tests/test_p0i_fake_profile_e2e.bats` (3) — because the deep-gate suites stage minimal `INSTALL_DIR`s (only `installer/output.sh` + the two doctor files; no `modules/`), the very contract `doctor.sh:37-39` documents for its other sources. With the best-effort form, the contract holds:

```
SOURCABLE_IN_MINIMAL_SANDBOX
deep_rc=2
```

(sourcing succeeds; `run_doctor --deep` still exits 2 with the in-development gate — community behavior byte-identical).

## 8. No-behavior-change argument

1. The deleted local `db_exec_root` ≡ `modules/db/core.sh::db_exec_root` byte-for-byte (§2) — the `:160` call resolves to the **same bytes**.
2. Definition timing preserved: the source sits at the exact top-level spot the def occupied, so `db_exec_root` is defined when `cli/actools` sources `doctor.sh`, before `run_doctor` runs — as before (focused test: defined at source time; `declare -f` byte-equal).
3. Sourcing the module is inert (pure function defs; verified under `set -u` in an empty env) and conflict-free: nothing `doctor.sh` sources (`dispatch.sh`, `output.sh`, `doctor_deep.sh`) defines any of the six names; the five extra functions have no call sites in `doctor.sh`.
4. Nothing else in the file changed (`git diff`: one 6-for-6 hunk); `cli/actools` byte-unchanged; nothing generated changed (drift 6/6 + cron 3/3).
5. Integration backstop: the existing e2e doctor-smoke (`actools doctor` + `--deep` on a real install). Not run in the sandbox (no docker daemon / cloud token); recommended branch dispatch, not gating — P0-N introduces no new e2e gate.

## 9. Dead twins untouched (P0-O preserved)

```
$ git diff 94d9ba8 --stat -- cli/commands/
 cli/commands/doctor.sh | 12 ++++++------
 1 file changed, 6 insertions(+), 6 deletions(-)
$ grep -rnE '^(db_exec_root|db_exec_root_stdin|db_dump_container|setup_backup_db_user|wait_db|check_db_creds)\(\)' cli/
cli/commands/cost_optimize.sh:10:db_exec_root() {
cli/commands/restore.sh:15:db_exec_root_stdin() {
cli/commands/restore.sh:9:db_exec_root() {
cli/commands/update.sh:10:db_dump_container() {
```

The remaining defs all live on **dead** twins (`cmd_*` called 0× in `cli/actools`) — outside the live CLI path, the guard's dead-twin arm pins the exclusion, and their deletion is P0-O.
