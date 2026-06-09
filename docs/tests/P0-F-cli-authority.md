# P0-F CLI Authority Consolidation — Test Report

> **Status:** Passing — one canonical CLI (`cli/actools`), installed by verbatim
> copy; the duplicate heredoc generator removed; secrets uniformly safe; the six
> non-CLI generated files byte-identical (golden 6/6).
> Phase: P0-F — CLI Authority Consolidation
> Produced by: Coding Window (Opus)
> Date: 2026-06-09

---

## Summary

P0-F collapses the two divergent operator CLIs into a single canonical source
(`cli/actools`, **Option A**) and removes the `actools.sh::setup_cli` heredoc that
generated a second CLI. This report records the new test suite and the regression
+ golden evidence that the **six non-CLI generated files are byte-identical** and
that the CLI consolidation holds the invariants below.

Defining properties this phase must hold (all verified below):

- **One CLI source.** `setup_cli` installs the CLI by copying `cli/actools`
  verbatim; the installed file is **byte-for-byte identical** to `cli/actools`.
- **No duplicate generator.** `setup_cli` contains no `cat > /usr/local/bin/actools`
  heredoc and no `HELPER` delimiter; the only install action is the copy.
- **Secrets never in argv.** No `-p"$…"` / `--password=` pattern exists in
  `cli/actools`; the snapshot uses `--defaults-extra-file` (umask 077 + trap) and
  root ops use `MYSQL_PWD` from the db container's environment.
- **Behavior parity preserved.** Backup cron, restore confirm+checksum,
  restore-test checksum + `.restore-test-last` marker (and its `doctor.sh`
  consumer), and a working 2-tier help with the ported `audit` command.
- **Runtime resolution.** `setup_cli` persists `ACTOOLS_HOME`, and `cli/actools`
  resolves `INSTALL_DIR="${ACTOOLS_HOME:-<self-locate>}"`.
- **Golden drift 6/6** — six non-CLI files byte-identical; the CLI is no longer a
  generated fixture (manifests reduced 7 → 6).

---

## Test surface (before → after)

| Suite | Before | After | Δ |
|---|---:|---:|---:|
| `tests/core/validate_test.bats` | 11 | 11 | — |
| `tests/core/secrets_test.bats` | 10 | 10 | — |
| `tests/installer/init_test.bats` | 11 | 11 | — |
| `tests/installer/init_profile_test.bats` | 10 | 10 | — |
| `tests/installer/preflight_test.bats` | 6 | 6 | — |
| `tests/installer/doctor_test.bats` | 5 | 5 | — |
| `tests/installer/dispatch_stages_test.bats` | 12 | 12 | — |
| `tests/installer/cli_authority_test.bats` | 0 | **14** | **+14 (new)** |
| `tests/test_d0_dispatch.bats` | 48 | 48 | — |
| **Regression total** | **113** | **127** | **+14** |
| `tests/generated/golden_drift_test.bats` | 6 | 6 | — (manifests 7→6 entries) |
| **Grand total** | **119** | **133** | **+14** |

---

## Tests added — `tests/installer/cli_authority_test.bats` (14)

All run rootless; none execute docker/systemctl or any privileged command. The
byte-identity test extracts `setup_cli` from the live `actools.sh`, redirects its
two root-only host writes (`/usr/local/bin/actools`, `/etc/environment`) to temp
paths, runs it, and diffs the result against `cli/actools`.

1. **`cli/actools parses (bash -n)`** — canonical CLI is valid bash.
2. **`installed CLI is a byte-for-byte copy of canonical cli/actools`** — the core
   single-source guarantee: empty `diff` between the installed file and
   `cli/actools`.
3. **`setup_cli persists ACTOOLS_HOME for the installed CLI`** — the redirected
   `/etc/environment` receives `ACTOOLS_HOME=<INSTALL_DIR>`.
4. **`setup_cli installs by copy, with no CLI-emitting heredoc`** — fails if a
   `cat > /usr/local/bin/actools` or `<<HELPER` reappears; asserts the
   `install … "${INSTALL_DIR}/cli/actools" … /usr/local/bin/actools` command is
   present.
5. **`cli/actools never passes a DB password on the command line`** — greps for
   `-p"?$` / `--password=` and fails if any match.
6. **`cli/actools uses safe secret mechanisms (defaults-file + MYSQL_PWD)`** —
   asserts both `--defaults-extra-file` and `MYSQL_PWD="$MARIADB_ROOT_PASSWORD"`
   are present.
7. **`cli/actools snapshot writes its defaults file with a tight umask`** —
   asserts `umask 077` precedes the `mktemp … .cnf` in the snapshot path.
8. **`backup command still delegates to the daily cron script`** — `backup) /etc/cron.daily/actools-backup`.
9. **`restore keeps its confirmation prompt and checksum verification`** —
   `OVERWRITE actools_` prompt and `sha256sum -c "$BACKUP_FILE.sha256"` retained.
10. **`restore-test keeps checksum gate and writes the .restore-test-last marker`**
    — `sha256sum -c "$LATEST.sha256"` and the `backups/.restore-test-last` write.
11. **`doctor.sh still consumes the .restore-test-last marker (consumer intact)`**
    — guards against the latent bug the generated CLI had (marker not written).
12. **`help (basic) runs and lists common commands`** — exit 0; contains
    "Actools Drupal Community" and "doctor" (ACTOOLS_HOME pinned for determinism).
13. **`help advanced runs and includes the ported 'audit' command`** — exit 0;
    contains "audit" and "tunnel".
14. **`audit command is wired to the audit module`** — `audit)` case present and
    references `modules/audit/audit.sh`.

---

## Golden drift — six non-CLI files byte-identical

The `actools-cli` fixture was removed from all five variants and each
`SHA256SUMS` reduced from 7 to 6 entries **by deleting only the `actools-cli`
line** — the six stack-file checksums are preserved verbatim. The drift test
re-renders each variant with the updated harness and compares against those
preserved sums; a pass therefore proves the six files
(`my.cnf`, `Dockerfile.caddy`, `Dockerfile.php`, `Dockerfile.worker`, `Caddyfile`,
`docker-compose.yml`) are unchanged. The harness still pins `setup_cli`'s location
via `_assert_fn_range "setup_cli" 1247 1262` (drift guard kept; the range is no
longer sed-extracted to render a CLI). The meta-test now asserts 6 manifest
entries.

---

## Commands run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline @ aa881de):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113

# Syntax:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6 (six non-CLI files byte-identical)
bats tests/installer/cli_authority_test.bats                                # 14/14 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# Secret-safety static check:
grep -nE '(-p"?\$|--password=)' cli/actools                                 # no matches
```

---

## Result

PASS — golden drift **6/6** before and after (six non-CLI generated files
byte-identical; the CLI is intentionally no longer a generated fixture).
Unit/integration **127/127** (113 prior + 14 new), **133/133** overall. All
`bash -n` clean. No password-in-argv pattern remains in `cli/actools`.

---

## Limitations / notes

- The CLI is **Changed intentionally** (not byte-identical) — the one such change
  in Phase 0. It is bounded by the parity matrix in
  `docs/architecture/cli-authority-contract.md` and justified in
  `docs/releases/P0-F-cli-authority.md`. A reviewer should read the matrix, not
  only the drift result.
- The tests are static/structural plus rootless execution of `setup_cli` and the
  CLI's `help`. They do **not** exercise live `docker`/`mariadb` paths (no daemon
  in the test environment); the secret-safety guarantee is enforced by static
  analysis of the exact command strings plus the safe-mechanism presence checks.
- The dropped `restore-test` S3 reachability chain is an accepted consequence
  (documented); there is no test asserting its absence beyond the parity record.
