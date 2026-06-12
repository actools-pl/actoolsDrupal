# P0-L Test Report — Backup-Cron Extraction + Orphan Purge

**Result: PASS** — full suite **199/199** (192 → 199: +3 cron drift, +4 security-shape
guard); golden drift **6/6 at every commit** (no compose fixture modified); the new
cron fixture **byte-identical across the extraction**; the security-shape guard
proven **non-vacuous** twice over (a permanent in-CI arm + the live injection demo
below); `bash -n` and ShellCheck clean; the orphan grep-proof empty.

## Commands run (at every implementation commit)

```bash
bash -n actools.sh
bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n
bats tests/generated/                          # 9/9: backup_cron_drift (3) + golden_drift (6)
bats tests/guards/                             # 9/9: cron_security_shape (4) + P0-K guards (5)
bats -r tests/                                 # 199/199
shellcheck --exclude=SC2034,SC2015,SC2164,SC1091 actools.sh
shellcheck --exclude=SC2034,SC2015,SC2164 modules/backup/cron.sh
shellcheck --exclude=SC2034,SC2015,SC2164 cron/*.sh        # cron/stats.sh — the CI glob stays valid
grep -rn "cron/backup.sh" . --include='*.sh' --include='*.yml' --include='*.bats'
# → no output (no references) after the deletion commit
```

## Test-surface delta

| Suite | Before | After | Added |
|---|---|---|---|
| `tests/generated/backup_cron_drift_test.bats` | — | 3 | byte-compare re-render; SHA256SUMS self-consistency; no-secret pin |
| `tests/guards/cron_security_shape_guard_test.bats` | — | 4 | defaults-extra-file required; full argv-password ban; permanent non-vacuity arm; generator-source check |
| Whole tree (`bats -r tests/`) | 192 | **199** | |

Both new suites are CI-gated by the existing recursive bats job (`lint.yml`:
`bats --print-output-on-failure -r tests/`) — no workflow edit.

## Byte-identity proofs (the phase's hard rule)

1. **Fixture captured pre-extraction, matched post-extraction.** The fixture
   `tests/fixtures/golden/backup-cron/actools-backup` was rendered from the
   **inline** generator at commit 1
   (`sha256 bdfaa0c6cb1f8f0a0ddf1540c52d7e7d4d095d62b9331f4d85164d5eaf76f249`).
   After the extraction commit, the renderer reports
   `Generator : modules/backup/cron.sh` and re-renders the **same sha**. The
   same renderer spanning the move is the faithfulness proof.
2. **Per-function byte-identity.** `diff` of `extract_inline_fn setup_backup_cron`
   from the pre-extraction `actools.sh` (commit `2e33f66`) against the same
   extraction from `modules/backup/cron.sh` — clean. (The brace-counting
   primitive was first verified heredoc-safe: its output is byte-identical to
   the raw `sed -n '584,661p'` line range.)
3. **Render determinism.** Re-render under a hostile ambient environment
   (`ENABLE_S3_STORAGE=false BACKUP_RETENTION_DAYS=30 RCLONE_REMOTE=junk
   ENVIRONMENTS=dev,stg` exported around the helper) → identical sha; the
   helper's fixed-input subshell fully isolates the render.
4. **No-secret pin.** `grep -c TEST_BACKUP_PASS_FIXED` on the fixture → 0; the
   fixture contains the runtime `jq -r '.backup_user_pass // empty'` fetch.
   Both pinned by `backup_cron_drift_test.bats` test 3.

## Non-vacuity — the guard bites

### Permanent in-CI arm (runs on every CI pass)

`cron_security_shape_guard_test.bats` test 3 doctors a **copy** of the live
generator: the secure `printf '[mariadb-dump]' … | docker exec … sh -c '… umask
077 … mariadb-dump --defaults-extra-file="$t" …' … | gzip` pipeline is replaced
with the retired orphan's exact invocation:

```
  docker exec actools_db mariadb-dump \
    --single-transaction --quick \
    -ubackup -p"$BK" "$DB" \
    | gzip > "$DUMPFILE"
```

The doctored copy is rendered through the **same** capture pipeline
(`capture_backup_cron.sh render-from`), and the shape oracle must reject it with
the `INSECURE SHAPE` violation — the arm also self-checks that the doctoring took
(the doctored function text carries `-ubackup -p"` and has lost
`--defaults-extra-file=`), so the arm cannot itself rot into a vacuous pass.

### Live injection demo (executed once; reverted byte-identical)

The same doctoring was applied to the **real** `actools.sh` (working tree only),
the suites run, and the tree reverted. Outputs verbatim:

**Guard against the doctored live generator — arms 1/2/4 fail:**

```
1..4
not ok 1 generated backup cron uses mariadb-dump --defaults-extra-file= (secure shape)
# (in test file tests/guards/cron_security_shape_guard_test.bats, line 84)
#   `grep -qF 'mariadb-dump --defaults-extra-file=' "${RENDER_TMP}/live-cron"' failed
not ok 2 generated backup cron passes no DB password on argv (full shape check)
# (from function `_assert_secure_shape' in file tests/guards/cron_security_shape_guard_test.bats, line 56,
#  in test file tests/guards/cron_security_shape_guard_test.bats, line 90)
#   `_assert_secure_shape "${RENDER_TMP}/live-cron"' failed
# INSECURE SHAPE: 'mariadb-dump --defaults-extra-file=' missing from the generated cron.
# The secure form (umask-077 temp defaults file inside the container) is authoritative.
ok 3 non-vacuous: an argv-password cron FAILS the shape check
not ok 4 live setup_backup_cron source carries the secure heredoc and no argv-password text
# (in test file tests/guards/cron_security_shape_guard_test.bats, line 175)
#   `grep -qF 'mariadb-dump --defaults-extra-file=' <<<"$fn_text"' failed
```

(Arm 3 stays green by design — it doctors its own copy regardless of the live
tree's state.)

**The cron drift gate catches the same injection as a byte change** — the diff
shows the secure pipeline replaced by the argv-password line in the rendered cron:

```
1..3
not ok 1 backup cron: re-render matches golden fixture byte-for-byte (no drift)
# (in test file tests/generated/backup_cron_drift_test.bats, line 71)
#   `return 1' failed
# DRIFT: backup-cron/actools-backup
#   Golden sha256  : bdfaa0c6cb1f8f0a0ddf1540c52d7e7d4d095d62b9331f4d85164d5eaf76f249
#   Rendered sha256: 9c6a8cd1cee80be6b16c04000995c600cbc48270f7289adec39467c4592ed9c7
#
#   Diff:
# 18,22c18
# <   printf '%s\n' '[mariadb-dump]' 'user=backup' "password=$BK"     | docker exec -i actools_db sh -c '
# <         umask 077; t=$(mktemp /tmp/actools-dump.XXXXXX.cnf); trap "rm -f \"$t\"" EXIT
# <         cat > "$t"
# <         mariadb-dump --defaults-extra-file="$t" "$@"
# <       ' _ --single-transaction --quick "$DB"     | gzip > "$DUMPFILE"
# ---
# >   docker exec actools_db mariadb-dump     --single-transaction --quick     -ubackup -p"$BK" "$DB"     | gzip > "$DUMPFILE"
ok 2 backup cron: stored SHA256SUMS manifest is self-consistent
ok 3 backup cron: fixture bakes no secret (password is read from state at runtime)
```

**After the revert** (working tree verified byte-identical to HEAD):

```
1..4
ok 1 generated backup cron uses mariadb-dump --defaults-extra-file= (secure shape)
ok 2 generated backup cron passes no DB password on argv (full shape check)
ok 3 non-vacuous: an argv-password cron FAILS the shape check
ok 4 live setup_backup_cron source carries the secure heredoc and no argv-password text
```

## Orphan purge proof

- `git rm cron/backup.sh` (the argv-password twin; unwired — verified by the
  reference sweep before deletion: nothing sourced, copied, or executed it).
- `grep -rn "cron/backup.sh" . --include='*.sh' --include='*.yml' --include='*.bats'`
  → empty (module/guard comments describe the retirement without the literal
  path, so the proof grep stays empty by construction).
- `cron/stats.sh` remains → `lint.yml`'s `shellcheck … cron/*.sh` glob still
  matches; no workflow edit.

## Backup-path argv sweep (and one pre-existing out-of-scope finding)

`grep -rnE '(^|[[:space:]])-p["'\''$]' actools.sh modules/backup/cron.sh cli/actools`
returns exactly one hit: `actools.sh:510` — the **pre-existing** v9.2-fix4 `wait_db()`
readiness probe (`mariadb -uroot -p"${_wp}"`, the DB **root** password, not the backup
password). The block is byte-identical to the baseline (P0-L's only `actools.sh` hunk is
`:584-661`); hardening it would be a behavior change outside this phase's allowed scope and
is flagged in ledger Entry 017 as a P0-M (DB-layer) candidate. On the **backup path** — the
generated cron, `modules/backup/cron.sh`, `cli/actools` backup, `cli/commands/update.sh` —
the password travels only via the umask-077 `--defaults-extra-file` shape; no argv form
exists (guard arms 2/4 + the sweep above).

## Per-commit gate record

| Commit | Change | generated/ | guards/ | full suite |
|---|---|---|---|---|
| `24f722e` | golden capture (helper + fixture + drift test) | 9/9 | 5/5 (P0-K) | 195/195 |
| `2e33f66` | cron security-shape guard | 9/9 | 9/9 | 199/199 |
| `09c5575` | extraction (module + source line + canary 594-609) | 9/9 | 9/9 | 199/199 |
| `e6aa398` | orphan deletion + grep-proof | 9/9 | 9/9 | 199/199 |

(Commit SHAs are the sandbox sequence; the operator records the applied SHAs.)

## ShellCheck notes

- `actools.sh` — clean under the established exclusions
  (`SC2034,SC2015,SC2164,SC1091`).
- `modules/backup/cron.sh` — clean under `SC2034,SC2015,SC2164` (SC2034 covers
  the verbatim function's `backup_pass` local, fetched but consumed only by the
  v14 shape — extraction does not "improve" the function).
- `tests/helpers/capture_backup_cron.sh` — clean; the render-shim functions
  carry explicit `SC2317` (indirect invocation) directives.
- `lint.yml` does not shellcheck `modules/backup/*.sh` (pre-existing: the
  directory holds unaudited P0-O orphans). The new module is shellcheck-clean
  locally and behavior-gated by three bats suites; adding the directory to CI
  shellcheck belongs to the P0-O audit.
