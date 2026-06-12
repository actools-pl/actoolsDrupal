# Test report — P0-M · Stateful DB Layer Extraction (tests-first) + `wait_db` Hardening

Phase: P0-M · Date: 2026-06-12 · Result: **PASS** (full suite 216/216; golden drift 6/6 + cron fixture at every commit; both new guards proven non-vacuous; the `wait_db` e2e gate pending CI — see §6)

## 1. Suite summary

| Suite | Tests | Result |
|---|---|---|
| `tests/db/db_contract_test.bats` (new) | 13 | PASS — green against the INLINE layer (commit 1) and unchanged against the MODULE (commit 3): the faithfulness proof |
| `tests/guards/duplicate_function_guard_test.bats` (extended) | 3 | PASS — sixteen names (ten core + six DB) |
| `tests/guards/wait_db_security_guard_test.bats` (new) | 4 | PASS — incl. the permanent non-vacuity arm |
| `tests/generated/` (compose drift + cron drift) | 9 | PASS at every commit — **no fixture modified** |
| Full recursive suite `bats -r tests/` | **216** | PASS (199 → 216: +13 contracts, +4 security) |

Also clean at every commit: `bash -n actools.sh && bash -n cli/actools`; `find installer core modules cli -name '*.sh' | xargs -n1 bash -n`; `shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh`; `shellcheck --exclude=SC2034,SC2015,SC2164 modules/db/core.sh`; the CI glob `shellcheck --exclude=SC2034,SC2015,SC2164,SC2119,SC2120 modules/db/*.sh` (still non-empty post-retirement).

## 2. Extraction byte-identity (commit 3)

Each function's text was extracted with the P0-K brace-counting primitive (`tests/core/extract_inline.bash::extract_inline_fn`, verified heredoc-safe for these bodies) from `actools.sh` BEFORE the move and from `modules/db/core.sh` AFTER; `diff` per function:

```
BYTE-IDENTICAL: db_exec_root
BYTE-IDENTICAL: db_exec_root_stdin
BYTE-IDENTICAL: db_dump_container
BYTE-IDENTICAL: setup_backup_db_user
BYTE-IDENTICAL: wait_db
BYTE-IDENTICAL: check_db_creds
```

After the hardening commit, the five non-`wait_db` functions were re-diffed against the pre-extraction texts — still byte-identical. The only `actools.sh` hunk in the whole phase is `:450-530` → the banner + `source` block (763 → 690 lines); the `setup_cli` canary moved 594-609 → 521-536 (the capture helper's documented maintenance step; capture logic untouched, no fixture modified).

## 3. Duplicate-function guard extension — non-vacuity (captured live)

### 3a. Commit-2 state: wiring the stale twin bites

Doctoring: `source "${INSTALL_DIR}/modules/db/wait.sh"` added to `actools.sh` (line 182) while the inline `wait_db` existed. Output verbatim:

```
1..3
not ok 1 each risky core function is defined exactly once on the live install path
# (in test file tests/guards/duplicate_function_guard_test.bats, line 94)
#   `return 1' failed
# Risky core functions must be defined exactly once on the live install path:
#   wait_db: defined 2x on the live path [actools.sh(x1) modules/db/wait.sh(x1)]
#
# Count >1 = a wired twin (wrong wiring) or an inline copy that was not
# deleted on extraction. Count 0 = the function fell off the live path.
not ok 2 no risky core function is defined in both actools.sh and a sourced core module
# (in test file tests/guards/duplicate_function_guard_test.bats, line 121)
#   `return 1' failed
# Inline + sourced-core dual definition detected (wrong wiring):
#   wait_db: inline in actools.sh AND in sourced modules/db/wait.sh
ok 3 twin ban: no risky core function is defined in both actools.sh and any core module
```

Reverted byte-identical (sha256-verified); guard green again.

### 3b. End-state: the unconditional modules/db twin ban bites

Doctoring: `wait_db() { :; }` appended to `actools.sh` while `modules/db/core.sh` defines it. All three arms fail, including the twin ban. Output verbatim:

```
1..3
not ok 1 each risky core function is defined exactly once on the live install path
# (in test file tests/guards/duplicate_function_guard_test.bats, line 94)
#   `return 1' failed
# Risky core functions must be defined exactly once on the live install path:
#   wait_db: defined 2x on the live path [actools.sh(x1) modules/db/core.sh(x1)]
#
# Count >1 = a wired twin (wrong wiring) or an inline copy that was not
# deleted on extraction. Count 0 = the function fell off the live path.
not ok 2 no risky core function is defined in both actools.sh and a sourced core module
# (in test file tests/guards/duplicate_function_guard_test.bats, line 121)
#   `return 1' failed
# Inline + sourced-core dual definition detected (wrong wiring):
#   wait_db: inline in actools.sh AND in sourced modules/db/core.sh
not ok 3 twin ban: no risky core function is defined in both actools.sh and any core module
# (in test file tests/guards/duplicate_function_guard_test.bats, line 153)
#   `return 1' failed
# Twin definition detected (inline copy not deleted, or orphan twin reintroduced):
#   wait_db: inline in actools.sh AND in modules/db/core.sh
```

Reverted byte-identical (sha256-verified); guards 13/13 green again.

## 4. `wait_db` security test — non-vacuity (permanent arm + captured live injection)

The permanent in-CI arm doctors a copy of the live `wait_db` back to the retired `-p"${_wp}"` probe and the shape oracle must fail it (it self-checks the doctoring took) — green in every run. Additionally, the retired argv probe was injected into the LIVE `modules/db/core.sh` and the suites re-run. Output verbatim (security guard, then the contract oracle):

```
1..4
not ok 1 wait_db source uses the umask-077 --defaults-extra-file probe (secure shape)
# (in test file tests/guards/wait_db_security_guard_test.bats, line 100)
#   `grep -qF -- '--defaults-extra-file=' "$BATS_TEST_TMPDIR/wait_db.code"' failed
not ok 2 wait_db source passes no DB password on argv (full shape check)
# (from function `_assert_wait_db_secure_shape' in file tests/guards/wait_db_security_guard_test.bats, line 74,
#  in test file tests/guards/wait_db_security_guard_test.bats, line 105)
#   `_assert_wait_db_secure_shape "$WAIT_DB_TEXT"' failed
# INSECURE SHAPE: '--defaults-extra-file=' missing from wait_db.
# The secure form (umask-077 temp defaults file inside the container,
# fed over stdin by the printf builtin) is authoritative — see the
# backup-cron pattern (modules/backup/cron.sh).
ok 3 non-vacuous: an argv-password wait_db FAILS the shape check
not ok 4 behavioral: live wait_db keeps the root password off every argv (stdin-only) and still issues the write-check
# (in test file tests/guards/wait_db_security_guard_test.bats, line 164)
#   `[[ "$a" != *GUARD_ROOT_SENTINEL* ]]' failed
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
not ok 10 wait_db: polls the write-check until the DB answers, then returns 0
# (from function `_assert_wait_db_probe_shape' in file tests/db/db_contract_test.bats, line 248,
#  in test file tests/db/db_contract_test.bats, line 281)
#   `_assert_wait_db_probe_shape "$n"' failed
ok 11 wait_db: gives up via error() after 50 failed probes (bounded)
ok 12 check_db_creds: probes root auth with SELECT 1 through db_exec_root
ok 13 check_db_creds: fails via error() when root auth is rejected
```

Reverted byte-identical to the hardening commit (sha256-verified); 26/26 (`tests/db/` + `tests/guards/`) green again. Note arm 3 stays green on the doctored tree by construction: it doctors whatever live text it finds and the result (already argv-form) still fails the oracle — consistent.

## 5. `wait_db` old-vs-new outcome equivalence (mock) + container-side mechanics

### 5a. Outcome equivalence

The pre-hardening and hardened `wait_db` were run against IDENTICAL mock-docker scenarios (stubbed `sleep`; attempts counted by the stub). Output verbatim:

```
scenario=immediate-success
  old: rc=0 attempts=1 sleeps=0 log=[LOG: Waiting for MariaDB (write-check)...|LOG: MariaDB ready.|]
  new: rc=0 attempts=1 sleeps=0 log=[LOG: Waiting for MariaDB (write-check)...|LOG: MariaDB ready.|]
  OUTCOME: IDENTICAL
scenario=fail-3-then-succeed
  old: rc=0 attempts=4 sleeps=3 log=[LOG: Waiting for MariaDB (write-check)...|LOG: MariaDB ready.|]
  new: rc=0 attempts=4 sleeps=3 log=[LOG: Waiting for MariaDB (write-check)...|LOG: MariaDB ready.|]
  OUTCOME: IDENTICAL
scenario=always-fail-bounded
  old: rc=1 attempts=50 sleeps=49 log=[LOG: Waiting for MariaDB (write-check)...|ERROR: MariaDB did not become ready within 150s.|]
  new: rc=1 attempts=50 sleeps=49 log=[LOG: Waiting for MariaDB (write-check)...|ERROR: MariaDB did not become ready within 150s.|]
  OUTCOME: IDENTICAL
ALL SCENARIOS: old and new wait_db produce identical outcomes (rc, attempt count, nap count, log/error lines).
```

(49 naps in the always-fail scenario on both sides: `error` fires at try 50 before the 50th nap — the pre-existing semantics, preserved.)

### 5b. Container-side mechanics (real `sh`, fake `mariadb`)

The hardened probe's `sh -c` body was executed under real `sh` with a recording `mariadb` on PATH and the probe's exact stdin/args. Output verbatim:

```
argv: --defaults-extra-file=/tmp/actools-wait.R57yxm.cnf -e CREATE TABLE IF NOT EXISTS mysql.actools_write_check (id INT); DROP TABLE IF EXISTS mysql.actools_write_check;
defaults_file_exists: yes
defaults_file_mode: 600
defaults_file_content:
[client]
user=root
password=MECH_SENTINEL
tmpfile_path_recorded: /tmp/actools-wait.R57yxm.cnf
temp defaults file REMOVED after exit (trap EXIT worked)
```

Proves: `umask 077` → the defaults file is mode **600**; the printf-fed stdin lands as the `[client]` credentials; `-e "<write-check>"` passes through `"$@"`; the temp file is cleaned up on exit. Combined with the host-side mock proof (the password appears on NO recorded docker argv, only in the stdin capture) the password is on no argv on either side of the exec boundary.

## 6. The e2e gate — PENDING CI (flagged per the spec's split rule)

The authoritative equivalence gate for the hardening is the CI fresh-install e2e (`e2e.yml` — a real Hetzner VM install reaching DB-ready). It cannot run in the coding sandbox (no docker daemon, no `HCLOUD_TOKEN`). What this report proves locally: identical polling outcomes at the mock level (§5a) and working temp-file mechanics in a real shell (§5b). What it does NOT prove: a real MariaDB accepting the `--defaults-extra-file` auth in the installed container image. The hardening is therefore the **isolated final implementation commit**; if the e2e does not reach DB-ready, the operator drops that one commit and steps 1–4 stand — the spec's "ship 1–4 and split the hardening" rule, exercised as a flag rather than a guess. The Review Gate must see the e2e green before Approve.

## 7. Orphan retirement grep-proof

```
$ grep -rn "modules/db/backup_user.sh\|modules/db/credentials.sh\|modules/db/wait.sh" . \
    --include='*.sh' --include='*.yml' --include='*.bats'
(no output — exit 1)
```

Guard/module comments describe the retirement without the literal paths (the P0-L convention), so the proof grep stays empty.
