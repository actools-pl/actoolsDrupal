# Handoff — P0-F · CLI Authority Consolidation

## Repository state

Branch: `phase0/P0-F-cli-authority`
Commit SHA: `9f8e94e` (code + tests); a follow-up docs commit lands the docs listed below.
Working tree clean? yes (after the docs commit)
Zip/package name if applicable: `actoolsDrupal-main`

## Task completed

Consolidated the two divergent operator CLIs into **one canonical source**
(`cli/actools`, **Option A**). `actools.sh::setup_cli` now installs the CLI by
copying that file verbatim (`install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools`);
the `cat > /usr/local/bin/actools <<HELPER` generator is deleted. Secret handling
is uniformly safe (no DB password in argv). Every command's behavior is retained
per the parity matrix (`docs/architecture/cli-authority-contract.md`). The CLI is
declared **Changed intentionally**; the six non-CLI generated files are
byte-identical (golden 6/6). New invariant test suite added.

## Files changed

- `cli/actools` — canonical CLI: `INSTALL_DIR="${ACTOOLS_HOME:-<self-locate>}"` (`:7`);
  stale comment rewritten; `update` safe `--defaults-extra-file` snapshot (umask
  077 + trap, reuse `BACKUP_PASS`, keep guard/strict-error/`php_prod`) + env-driven
  `drush updb` loop; `restore`/`restore-test` root ops via `MYSQL_PWD` in-container,
  dead `DB_ROOT_PASS` guards removed, `.restore-test-last` kept, S3 chain dropped;
  `storage-info` path fix; `migrate` mode fix; `health` env-driven loop; `audit`
  command + help entries added.
- `actools.sh` — `setup_cli()` (`:1247-1262`): heredoc + dead `local backup_pass`
  removed; replaced with the `install` copy; `chmod`/`log`/`ACTOOLS_HOME` tail kept.
  `setup_stack` (`:569-1028`) untouched. `get_backup_pass` retained (used elsewhere).
- `tests/helpers/capture_golden_outputs.sh` — `SC_END` 1528 → 1262; PHASE-2 CLI
  render + PHASE-3 `actools-cli` copy + PHASE-4 sha entry removed; orphaned
  `FIXED_CLI_INSTALL_DIR` removed; `_assert_fn_range "setup_cli"` guard kept/updated.
- `tests/fixtures/golden/{default,redis-off,s3-on,cadvisor-on,all-in-one}/` —
  `actools-cli` deleted; `SHA256SUMS` 7 → 6 entries (six stack sums preserved verbatim).
- `tests/generated/golden_drift_test.bats` — meta-test manifest-entry 7 → 6.
- `tests/installer/cli_authority_test.bats` — **new, 14 tests**.
- Docs: `docs/architecture/cli-authority-contract.md`,
  `docs/architecture/runtime-authority-map.md`, `docs/CHANGELOG.md`,
  `docs/releases/P0-F-cli-authority.md`, `docs/tests/P0-F-cli-authority.md`,
  `docs/runbooks/PHASE0_LEDGER.md` (Entry 011), this handoff.

## Files not changed but relevant

- `actools.sh::setup_stack()` and the six non-CLI generators — not touched (golden 6/6).
- `modules/audit/*` — `audit` was wired, not authored; ships as-is (`--deep` edition-gated).
- `cli/commands/doctor.sh` — unchanged; its `.restore-test-last` consumer (`:194`)
  verified intact by a test.
- `modules/dr/resurrect.sh` — its independent `actools-real` copy is out of scope (P0-J).

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | none |
| Install stages | none (`setup_cli` is a trailing step; install-by-copy replaces heredoc-generate) |
| CLI | **consolidated** — one canonical source (`cli/actools`); installer copies it verbatim; duplicate heredoc deleted; secrets uniformly safe; `INSTALL_DIR` via `ACTOOLS_HOME` |
| Generated files | CLI **Changed intentionally** (no longer a generated artifact; fixture retired); six non-CLI files **unchanged** |
| Preflight | none |
| Doctor | the former generated-CLI `doctor` path is gone; only static `doctor.sh` remains (resolver wiring still P0-H) |
| Handoff | none (handoff is an installer concept; the stale heredoc reference removed from the map) |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | not touched (byte-identical; golden 6/6) |
| Caddyfile | not touched (byte-identical; golden 6/6) |
| my.cnf | not touched (byte-identical; golden 6/6) |
| Dockerfiles | not touched (byte-identical; golden 6/6) |
| CLI | **changed intentionally** (authority consolidated to `cli/actools`; no longer generated; installed==source proven by test) |

## Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline @ aa881de):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 113/113

# AFTER:
bats tests/generated/golden_drift_test.bats                                 # 6/6 (six non-CLI files byte-identical)
bats tests/installer/cli_authority_test.bats                                # 14/14 (new)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# Syntax + secret-safety:
bash -n actools.sh; bash -n cli/actools
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
grep -nE '(-p"?\$|--password=)' cli/actools                                 # no matches
```

## Test result

PASS — golden drift **6/6** (six non-CLI files byte-identical); unit/integration
**127/127** (113 prior + 14 new); **133/133** overall; all `bash -n` clean; no
password-in-argv pattern in `cli/actools`.

## Docs updated

CLI authority contract (Option A + 12-row matrix + Status: satisfied); runtime
authority map (CLI-install / Generated-CLI / Doctor / Handoff rows; test count
119→133); CHANGELOG (P0-F section); release note (with Rollback +
Changed-intentionally justification); test report; ledger Entry 011.

## Changelog / release notes updated

Yes — `docs/CHANGELOG.md` (Unreleased → P0-F), `docs/releases/P0-F-cli-authority.md`
(incl. `## Rollback`), `docs/tests/P0-F-cli-authority.md`.

## Ledger entry

Entry number: **011**

## Known risks

- CLI is **Changed intentionally** (first such in Phase 0) — bounded by the parity
  matrix; six non-CLI files byte-identical. Read the matrix, not just drift.
- `INSTALL_DIR` now trusts `ACTOOLS_HOME`; if `/etc/environment` is wiped, the
  self-location fallback resolves to `/usr/local` from `/usr/local/bin`. Mitigated:
  `setup_cli` always (re)writes `ACTOOLS_HOME`. Tests pin it for determinism.
- Dropped `restore-test` S3 reachability chain — run `actools storage-test`
  explicitly. Documented.
- Installed CLI gains `tunnel`, 2-tier `help`, and `audit` (additive). `worker-run`
  keeps the static `drush queue:run …` (generated's `xelatex --version` dropped).

## Blockers

None.

## Exact next allowed task

**P0-G — Host/stack extraction** *or* **P0-H — Surface wiring** (the Review Gate
owns sequencing). With the CLI consolidated, extracting `setup_stack`'s host/stack
heredocs into `modules/*` behind the dispatcher (with golden fixtures) can proceed
independently; alternatively, wire the completed resolvers (P0-E) into the live
preflight/doctor/handoff surfaces and the `ACTOOLS_PROFILE`-driven install path.

## Explicitly forbidden scope for next task

No host/stack extraction *in P0-F* (that is P0-G); no community-plus feature
commands beyond existing stubs/gates; no broad rewrite of command behavior beyond
the documented parity matrix; no touching `setup_stack` or the six non-CLI
generators; no widening or disabling the golden harness range guard.

## Review Gate notes

A separate session (ideally a different model) renders APPROVED / NEEDS REVISION /
BLOCKED. Reviewer checklist: (1) six non-CLI generated files byte-identical
(drift 6/6) and the CLI's "Changed intentionally" status matches the parity matrix;
(2) only allowed files touched; (3) `setup_cli` installs by verbatim copy with no
heredoc and the installed CLI equals `cli/actools`; (4) **no** DB password in any
argv (snapshot uses a defaults file; root ops use `MYSQL_PWD` in-container) and the
temp cnf uses `umask 077` + trap; (5) the harness range guard is updated
(`SC_END=1262`) and green, not widened/disabled.
