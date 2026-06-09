# Changelog

## [Unreleased] — P0-G Extract Host and Stack Logic

### Changed — runtime authority (host + stack logic relocated into modules; output byte-identical)
- `actools.sh::setup_stack()` is no longer a monolith. Its live **host
  provisioning** moved into `modules/host/*` (`packages`, `age`, `kernel`, `swap`,
  `firewall`, `docker`, `logrotate`), now invoked by the install-stage
  dispatcher's `stage_host` handler in the exact monolith order. The inline host
  block was **deleted** from `actools.sh`.
- The four **stack generators** moved into `modules/stack/*`:
  `mycnf.sh::generate_mycnf`, `images.sh::build_caddy_image`/`build_php_image`/
  `build_worker_image`, `caddyfile.sh::generate_caddyfile`, and
  `compose.sh::generate_compose`. `setup_stack` is now a **thin orchestrator**
  (~53 lines) that sources those modules, calls the generators in order, then runs
  `docker compose pull/down/up` and `setup_backup_db_user`.
- **This is an authority move, not an output change.** The six generated stack
  files (`my.cnf`, `Dockerfile.caddy`, `Dockerfile.php`, `Dockerfile.worker`,
  `Caddyfile`, `docker-compose.yml`) are **byte-identical** — golden drift 6/6,
  with **no golden fixture modified**. `actools.sh` shrank from 1416 to 871 lines.
  Each module body is a byte-for-byte extraction of its monolith block (the one
  exception is a documented `# shellcheck disable=SC2034` in `compose.sh`, no
  output impact). The previously orphaned, stale `modules/host/*` and
  `modules/stack/*` were overwritten with the monolith's current exact bytes and
  are now the live authority. Edit host/stack logic in the modules, not in
  `actools.sh`.

### Changed — host steps are now fresh-install-only (deliberate, bounded)
- Because host provisioning runs on the dispatcher's `host` stage, it executes
  **only** on a confirmed fresh install: `--dry-run` no longer mutates the host
  (bug fix), declining the interactive confirm aborts before any host change, and
  `update`/`env` no longer re-run host provisioning (the steps were already
  idempotent). The fresh-install happy path (`host → stack → db → drupal →
  worker`) is byte-identical. See `docs/releases/P0-G-extract-host-stack.md`.

### Changed — tests
- The golden-capture harness (`tests/helpers/capture_golden_outputs.sh`) now
  renders fixtures by sourcing `modules/stack/*` and **calling the generators
  directly**, instead of sed-extracting and `eval`-ing `setup_stack`. The
  `SS_*` line range was removed; a new `_assert_fn_defined()` guard checks each
  module defines its generator; the `setup_cli` range pin is kept as a drift
  canary.
- `tests/installer/dispatch_stages_test.bats` gains two tests (133 → **135**
  overall): `stage_host` drives the host modules in canonical order, and
  `setup_stack` delegates to the six generators in canonical order.

## [Unreleased] — P0-F CLI Authority Consolidation

### Changed — runtime (CLI authority consolidated to a single source; **Option A**)
- There is now **one** canonical operator CLI: `cli/actools`. The installer
  (`actools.sh` → `setup_cli`) installs it by copying that file **verbatim**
  (`install -m 0755 "${INSTALL_DIR}/cli/actools" /usr/local/bin/actools`). The
  duplicate `cat > /usr/local/bin/actools <<HELPER` generator that re-emitted a
  second, divergent CLI has been **removed**. Edit the CLI in `cli/actools` and
  nowhere else.
- `cli/actools` resolves its install directory at runtime as
  `INSTALL_DIR="${ACTOOLS_HOME:-$(self-locate)}"` so the verbatim copy works at
  `/usr/local/bin/actools` (where bare self-location would wrongly yield
  `/usr/local`). `setup_cli` continues to persist `ACTOOLS_HOME` to
  `/etc/environment`; the self-location fallback covers in-repo execution.
- **The CLI is the one generated file Changed intentionally this phase.** The six
  non-CLI generated files (`my.cnf`, `Dockerfile.caddy`, `Dockerfile.php`,
  `Dockerfile.worker`, `Caddyfile`, `docker-compose.yml`) are **byte-identical**
  (golden drift 6/6); `setup_stack` was not touched. See
  `docs/releases/P0-F-cli-authority.md` for the per-command parity matrix and
  justification.

### Changed — CLI secret handling (now uniformly safe)
- `update` takes its pre-update snapshot via a **temporary MariaDB defaults file
  created inside the db container** (`umask 077` + `trap` cleanup), fed the backup
  password over stdin — the password never appears in any process argument list.
  Replaces the previous `mariadb-dump … -p"$BACKUP_PASS"`.
- `restore` and `restore-test` perform root DB operations via
  `docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"'`,
  taking the password from the db container's own environment variable rather than
  `-p"$DB_ROOT_PASS"` on the command line. The now-dead `DB_ROOT_PASS` guards
  (the value was never exported to the host) were removed.

### Changed — CLI command parity (per the matrix)
- `update` / `health` now iterate `ENVIRONMENTS` (`for env in $(echo "${ENVIRONMENTS:-prod}" | tr ',' ' ')`);
  identical to before for the community default (`prod`), correct for all-in-one.
- `storage-info` reads `${INSTALL_DIR}/actools.env` instead of a hardcoded
  `/home/actools/actools.env`.
- `migrate` prints the live `${XELATEX_MODE:-local}` instead of a hardcoded
  `local`.
- `update` retains strict failure handling (abort with `exit 1` + retained-snapshot
  rollback hint) and `docker compose pull db redis php_prod`.

### Added — runtime
- `actools audit` is now available in the canonical CLI (it previously existed only
  in the generated CLI). It dispatches to the shipping `modules/audit/audit.sh`
  (`--deep` remains edition-gated). Added to both help tiers.

### Removed — runtime
- `restore-test` no longer chains an implicit S3 reachability check
  (`actools storage-test`). Run `actools storage-test` explicitly if needed. This
  removes noise on non-S3 installs and avoids a cross-command dependency.

### Changed — tests and fixtures
- The CLI is no longer a *generated* artifact, so it has **no golden fixture**.
  The `actools-cli` fixture was removed from all five variants and each
  `SHA256SUMS` reduced from 7 to 6 entries (the six stack-file checksums are
  preserved verbatim, so the drift gate still proves they are unchanged).
- `tests/helpers/capture_golden_outputs.sh` no longer renders a CLI; the
  `setup_cli` range guard (`_assert_fn_range`) is kept and updated
  (`SC_END` 1528 → 1262).
- `tests/generated/golden_drift_test.bats` meta-test now expects 6 manifest
  entries.

### Added — tests
- `tests/installer/cli_authority_test.bats` — 14 tests: `bash -n`; **installed CLI
  is byte-for-byte identical to `cli/actools`**; `setup_cli` persists
  `ACTOOLS_HOME`; no CLI-emitting heredoc remains; **no DB password in argv**;
  safe mechanisms present (`--defaults-extra-file`, `MYSQL_PWD`, `umask 077`);
  preserved behaviors (backup cron, restore confirm+checksum, restore-test
  checksum + `.restore-test-last` marker, doctor.sh consumer intact); help smoke
  (basic + advanced, including the ported `audit`).

### Test status — P0-F
- Golden drift **6/6** (six non-CLI files byte-identical). Unit/integration
  **127/127** (113 prior + 14 new), **133/133** overall. All `bash -n` clean.

## [Unreleased] — P0-E Profile Validation and Resolver Contract

### Changed — runtime (community-preserving; the only live behaviour change is in `init`)
- `installer/init.sh` now makes profile selection **safe at init time**. Before
  persisting `actools.env` it (a) sources `installer/profile.sh` for the chosen
  profile and **validates the `.profile` file exists**, failing *before* any
  write if it does not; (b) enforces `PROFILE_REQUIRES_ACTOR` /
  `PROFILE_REQUIRES_CHANGE_TICKET` via the existing `profile_requires_actor` /
  `profile_requires_change_ticket` accessors; (c) consumes `PROFILE_INIT_FIELDS`
  via `profile_init_fields`. This closes the latent `--profile community-plus`
  break: `community-plus` is an allowed *name* but its profile file is a Phase-1
  product that does not ship here, so `init` previously wrote an `actools.env`
  the next run could not load. New flags `--actor-id` / `--change-ticket` are
  **validated** when a profile requires them but are **not persisted** (recording
  governance identity is a community-plus concern, deferred to P0-H).
- **Community is unchanged:** `community.profile` sets both governance flags
  `false` and `PROFILE_INIT_FIELDS=(domain email site-name)`, so
  `init --domain … --email …` behaves exactly as before and writes
  `ACTOOLS_PROFILE=community`.

### Changed — resolver contract (`installer/dispatch.sh`)
- `actools::dispatch::resolve_feature_handler` now implements the LOCKED **3-tier
  path resolution** (alignment §4.1) and returns a **file PATH**, not a token:
  Tier 1 `profiles.d/${ACTOOLS_PROFILE}/commands/${feature}.sh` (active-profile
  override) → Tier 2 `modules/${module}/${feature}.sh` (a module the active
  profile lists, via the internal `PROFILE_FEATURE_MODULES`) → Tier 3
  `cli/commands/${feature}.sh` (default / gate). The **first existing path wins**;
  if none exist, output is empty. **Community short-circuits to empty before the
  search** — byte-identical, non-negotiable. This is a deliberate token→path
  contract change, safe because `resolve_feature_handler` has **zero live call
  sites** (its callers are wired in P0-H).
- **Documented asymmetry:** only `resolve_feature_handler` goes path-based.
  `resolve_preflight_check` / `resolve_doctor_check` / `resolve_handoff_section`
  remain **token-based** until their live surfaces are wired (P0-H), so their
  existing tests stay green.

### Added — resolver (`installer/dispatch.sh`)
- `actools::dispatch::resolve_profile_check <surface> <check_id>` — the
  LOCKED-named umbrella (alignment §4.2) that **delegates** to the existing
  per-surface resolvers (`preflight`→`resolve_preflight_check`,
  `doctor`→`resolve_doctor_check`, `handoff`→`resolve_handoff_section`; unknown
  surface → WARN + empty). The per-surface resolvers are kept as the internals.

### Added — tests and fixtures
- `tests/installer/init_profile_test.bats` — 10 tests: unknown profile fails
  cleanly; `community-plus` fails **before persisting** (`actools.env` not
  written); fake actor/ticket profiles prove the governance requirements fire
  and that the identity values are **not** persisted; community requires neither.
- `tests/test_d0_dispatch.bats` — +15 tests (33 → 48): 3-tier resolver order
  (override > module > default > empty, plus the community short-circuit guard),
  `resolve_profile_check` delegation, and side-effect-free profile loading
  (with a negative control proving the harness bites). The single pre-existing
  `resolve_feature_handler` community-plus test was updated from the old
  `plus_doctor_deep` token to the new resolved tier-3 path.
- `tests/fixtures/profiles/fake-actor.profile`, `…/fake-ticket.profile` —
  **test-only** fixtures (never shipped), staged as `profiles/test.profile`.
- `tests/installer/init_test.bats` — setup now stages `dispatch.sh`,
  `profile.sh`, and `community.profile` into the sandbox so the 11 existing init
  tests exercise the real (now profile-sourcing) init flow under `set -u`.

### Behaviour / generated files
- **No runtime install-path change:** the resolvers (`resolve_feature_handler`,
  `resolve_profile_check`) remain uncalled on the live path (their callers are
  P0-H). `actools.sh` is untouched. The only live behaviour change is the `init`
  command's new pre-persist validation, which is a no-op for community.
- **No generated-file change:** golden drift stays **6/6** (byte-identical).

### Not changed
- `actools.sh` (forbidden this phase), all generator heredocs, `cli/*`,
  `modules/*`, `core/*`, `.github/workflows/*`.
- `profiles/community.profile` — read via the loader, not modified.
- No community-plus modules, no surface wiring (P0-H), no deep audit/doctor
  features, no governance gates beyond validation scaffolding.

---

## [Unreleased] — P0-D Install-Stage Dispatcher Skeleton

### Changed — runtime (behaviour-preserving)
- `actools.sh` `main()` (fresh install) now routes through an install-stage
  dispatcher instead of a hardcoded call sequence: it sources
  `profiles/community.profile` and iterates `PROFILE_INSTALL_STAGES` via
  `actools::dispatch::run_install_stage`. The trailing post-stage steps
  (`setup_backup_cron`, `setup_cli`, `tls_check`) are unchanged.

### Added — runtime
- `installer/dispatch.sh` — install-stage dispatcher (append-only, behind the
  existing module guard): `actools::dispatch::resolve_install_stage`,
  `actools::dispatch::run_install_stage`, and the community base handlers
  `actools::install::stage_{host,stack,db,drupal,worker}`. Stage→handler
  mapping for this phase: `stack`→`setup_stack` (unchanged); `drupal`→the
  per-environment `install_env` loop (verbatim, incl. parallel/sequential +
  low-RAM downgrade); `host`/`db`/`worker`→documented no-ops folded into the
  existing monoliths until P0-G.
- `tests/installer/dispatch_stages_test.bats` — 12 tests (stage order,
  real-handler behaviour preservation, append-only stage guard, resolver
  correctness).

### Behaviour / generated files
- **No behaviour change** on the default community install: same operations,
  same order, same parallel/sequential + low-RAM logic, same trailing steps.
- **No generated-file change**: the golden drift suite stays **6/6**
  (byte-identical) before and after. No generator heredoc was touched.

### Not changed
- `profiles/community.profile` — `PROFILE_INSTALL_STAGES` was already canonical;
  read, not redefined.
- `setup_stack` / `install_env` / `setup_backup_cron` / `setup_cli` / `tls_check`
  bodies — untouched (the dispatcher calls them unchanged).
- No CLI-authority change (P0-F), no module extraction (P0-G), no community-plus
  stage implementation, no change to the golden harness range guard.

---

## [Unreleased] / Documentation — P0-B Target Operator Docs + Architecture Reconciliation

### Added — target operator documentation (unreleased; Phase 0 target behaviour only)
- `docs/target/phase0/operator/README.md` — index of target docs and promotion gate
- `docs/target/phase0/operator/install-community.md` — default `community` install journey
  (init → preflight → install → handoff → doctor) with Phase 0 target vs D.0 gap notes
- `docs/target/phase0/operator/profiles.md` — profile lifecycle, error behaviour, and
  the profile contract; community-plus reserved-but-not-implemented status
- `docs/target/phase0/operator/commands.md` — full command surface as a target contract;
  installer commands + CLI commands + profile resolution at runtime
- `docs/target/phase0/operator/generated-files.md` — all operator-visible generated files,
  their current heredoc authority, Phase 0 target authority, and safety rules
- `docs/target/phase0/operator/troubleshooting.md` — symptom-first troubleshooting for
  init, preflight, install, CLI, and generated-file problems

Every target doc carries the required status banner: "Phase 0 target contract — not yet
released." None asserts current-released behaviour. None claims community-plus is
implemented.

### Changed — documentation reconciliation (corrected false claims in place)
- `docs/architecture.md` — corrected `v11.2.0+` → `v14.0+` (actual version per
  `actools.sh:46`); removed false claim that the CLI "never contains business logic"
  (`actools.sh` is the monolithic live spine); corrected `21 bats tests` → `76`; replaced
  the false `phases_complete` state-machine block with the actual `init_state()` structure
  (`{"envs":{}, "db_passes":{}, "backup_user_pass":…}`); corrected `actools-real` example
  reference to `cli/actools` (the canonical CLI source)
- `docs/CHANGELOG.md` — corrected false `v10.0.0` Architecture claim that Dockerfiles had
  been extracted from bash heredocs; Dockerfiles are still generated by `actools.sh`
  heredocs at `:607`, `:624`, `:634`; corrected entry now cites the live authority and the
  P0-G extraction scope

### Not changed
- No runtime code (`actools.sh`, `installer/*`, `cli/*`, `modules/*`, `profiles/*`,
  `core/*`, tests) was modified. This is a documentation-only ledger entry.
- `docs/architecture/runtime-authority-map.md` — not modified (no authority changes this
  phase per P0-B forbidden scope).

---

## D.0 — Community Seam Hardening (Resolver Dispatch Foundation)

**New files:**
- `installer/dispatch.sh` — resolver function family (`resolve_feature_handler`, `resolve_preflight_check`, `resolve_doctor_check`, `resolve_handoff_section`, `profile_is_valid`, `actools::cli::resolve_profile`). Single dispatch surface for all profile-aware operations.
- `tests/fixtures/profiles/test/` — test fixture profile (4 files). Exercises resolver dispatch against a non-production profile without requiring D.1+ modules to exist.
- `tests/test_d0_dispatch.bats` — 33 bats tests covering all resolver paths, CLI profile resolution, fixture activation, sibling-scope audit, and community-install regression.

**Modified files:**
- `installer/init.sh` — added `--profile` flag; validates against allowed list; writes `ACTOOLS_PROFILE` to `actools.env`.
- `installer/preflight.sh` — sources `dispatch.sh` after `profile.sh` sets `ACTOOLS_PROFILE`.
- `installer/handoff.sh` — sources `dispatch.sh` after `profile.sh` sets `ACTOOLS_PROFILE`.
- `cli/commands/doctor.sh` — sources `dispatch.sh`; adds "Active profile" line to output.
- `cli/actools` — global `--profile` flag parsing; fail-closed profile conflict detection; exports `ACTOOLS_PROFILE`.
- `actools.sh` — sources `dispatch.sh` after `INSTALL_DIR` is set.
- `README.md` — added deployment profiles section.

**Baseline test count after D.0:** 43 existing + 33 new = 76 total.

**D.0 defining property:** Community installs see zero behaviour change. Adding `--profile community-plus` does nothing observable (no `plus_*` modules exist yet).


All notable changes to Actools are documented here.

---

## [v14.1.0] — 2026-05-24 — Staged Operator Journey

### Added — staged installer modes
- `actools.sh init` — guided actools.env creation from CLI flags (`--domain`, `--email`, `--site-name`, `--force`). Refuses to overwrite without `--force`. `SITE_NAME` is quoted on write so values with spaces source cleanly.
- `actools.sh preflight` — eight readiness checks (OS, env, RAM, disk, ports, DNS, install state) with `OK / WARN / FAIL` rendering and a `Fix:` line on anything actionable. Exit codes `0` ready, `1` failures, `2` warnings only.
- `actools.sh install` — friendly alias for `fresh`. `fresh` still works and prints a soft deprecation hint to stderr.
- `actools.sh handoff` — clean four-block post-install summary (site / admin / commands / log). Replaces the verbose terminal banner. Can be re-printed anytime.
- `actools.sh help` / `--version` — run without sudo, env file, or lock.
- `actools doctor` — daily one-page health check with nine surface-level checks (site, TLS, containers, DB, Redis, disk, backups, restore-test recency, Drupal bootstrap). Exit codes `0/1/2`.
- `actools doctor --deep` — gate stub for deep mode (in development), parity with `actools audit --deep`. Exit code `2` on the gate.

### Added — profile contract (the hinge)
- `installer/output.sh` — shared `print_ok`, `print_warn`, `print_fail`, `print_skip`, `print_fix`, `print_next`, `print_summary` helpers used by all staged-journey scripts. Plain-text fallback on non-TTY or `ACTOOLS_PLAIN=1`.
- `installer/profile.sh` — profile loader. Active profile read from `ACTOOLS_PROFILE` (default `community`).
- `profiles/community.profile` — the default and only profile shipping in the community installer.
- `profiles/README.md` — the profile contract. Profiles for hardened or institutional deployments live in separate products and inherit via this contract.

### Added — tests
- `tests/installer/init_test.bats` — 11 tests covering input validation, env-file writing, overwrite protection, and SITE_NAME quoting.
- `tests/installer/preflight_test.bats` — 6 tests covering control-flow paths and missing/invalid env vars.
- `tests/installer/doctor_test.bats` — 5 tests covering the gate, exit code, and gate output.

### Added — documentation
- `README.md` — rewritten per Doc 1 §11. Honest, narrow, operator-focused. No "enterprise-grade" claim as the lede.
- `docs/quick-start.md` — full staged-journey walkthrough.
- `docs/operator-handbook.md` — the five commands you actually use day-to-day.
- `docs/command-reference.md` — every command, grouped by frequency of use.
- `docs/troubleshooting.md` — symptom-first problem fixes.
- `docs/advanced.md` — disclosure layer for PITR, DNA, GDPR, AI, previews, tunnels, audit, observability, storage.

### Changed
- `cli/actools` header: `v9.2` → `v14.0` (cosmetic alignment).
- `cli/actools help` output redesigned into common / support / advanced groupings (Doc 1 §8.3). Full surface available via `actools help advanced`.
- `actools.sh` `main()` no longer prints the multi-line banner; it now sources `installer/handoff.sh` and calls `run_handoff`. `${INSTALL_DIR}/.actools-install-complete` marker is written on success.
- `docs/cli-reference.md` replaced with a one-line redirect to `command-reference.md` so existing inbound links don't 404.
- `docs/README.md` (docs index) restructured around the new doc layout.
- `.github/workflows/lint.yml` — shellcheck now scans `installer/*.sh` with the same exclusion set as `cli/commands/*.sh`. bats job extended with the three new test files.
- `.github/workflows/e2e.yml` — uses `install` instead of `fresh` (CI exercises the new name). Adds a doctor + doctor-deep-gate smoke step after audit.

### Backward compatibility
- `actools.sh fresh` continues to work with a soft deprecation hint to stderr — existing 633+ clones and any automation calling `fresh` keep functioning.
- `actools.sh env <dev|stg|prod>`, `update`, and `dry-run` are unchanged.
- All existing `actools <command>` CLI verbs are unchanged. `actools health` is preserved as a legacy alias next to `actools doctor`.

### Rationale
The two intent documents (Community UX Architecture and DrupalFortress Community-Aligned Architecture) called for one structural move: replace the four-line copy-and-edit env onboarding with a five-stage operator journey (`init → preflight → install → handoff → doctor`), and make the underlying installer profile-ready so a future hardened-platform product can inherit the same journey without forking. The profile abstraction ships, but only the `community` profile is bundled. Profiles for hardened or institutional deployments live in separate downstream products. The `doctor --deep` gate matches the `audit --deep` gate pattern for consistency.

---

## [v10.0.2] — 2026-03-26

### Fixed
- CI: Added ShellCheck exclusions for SC2043, SC2012, SC1090 in cli/commands
- CI: Fixed bats test paths for GitHub Actions compatibility

## [v10.0.1] — 2026-03-26

### Added
- Phase 1 complete: 32 modules extracted from monolith
- 21 bats tests — all passing (core/validate, core/secrets)
- GitHub Actions CI: ShellCheck + bats on every push
- modules/preflight/: dns.sh, disk.sh, ram.sh
- tests/core/: validate_test.bats, secrets_test.bats

## [v10.0.0] — 2026-03-26 — Phase 1 Complete

### Added
- core/bootstrap.sh — variable init, logging, lock file
- core/state.sh — JSON state management
- core/secrets.sh — password generation and writeback
- core/validate.sh — env, S3, XeLaTeX, disk validation
- modules/host/ — packages, kernel, swap, firewall, docker, logrotate
- modules/stack/ — mycnf, caddyfile, images, compose
- modules/db/ — wait, credentials, backup_user
- modules/drupal/ — prepare, provision, secure (3-stage install)
- modules/storage/ — s3fs, settings_inject
- modules/worker/ — xelatex, queue
- cli/commands/ — health, backup, worker, storage, restore, update
- cron/ — backup, stats collection
- docs/phases/ — phase documentation

### Architecture
- install_env() split into 3 independent stages: prepare → provision → secure
- Each stage is idempotent and independently retryable
- Failed installs can resume from any stage without re-running earlier steps
- Dockerfiles generated by `actools.sh` heredocs (`setup_stack`); extraction to
  `modules/stack/images.sh` with golden-fixture parity is Phase 0 / P0-G scope
  *(original claim in this block was false at release time; the `v10.0.0` Architecture
  section incorrectly stated heredoc generators had been eliminated;
  corrected at P0-B — see `docs/architecture/runtime-authority-map.md`
  "Generated Dockerfiles" row)*

---

## [v9.2] — 2026-03-25 — Production Hardening

### Fixed (8 compatibility fixes)

1. **MariaDB 11.4 healthcheck** — `mysqladmin` removed in MariaDB 11.4.
   Replaced with `healthcheck.sh --connect --innodb_initialized`

2. **MariaDB 11.4 client** — `mysql` binary removed in MariaDB 11.4.
   All `mysql` calls replaced with `mariadb` throughout installer and CLI

3. **mariadb-dump** — backup cron used non-existent `mariadump` command.
   Fixed to `mariadb-dump` — nightly backups were silently failing before this fix

4. **pull_policy: never** — Docker Compose was attempting to pull locally-built
   `actools_caddy:custom` and `actools_worker:latest` from Docker Hub registry.
   Added `pull_policy: never` to both services

5. **Caddyfile log block** — Caddy 2.8 rejected inline `log { level INFO }`.
   Expanded to multi-line block format

6. **DB log directory ownership** — MariaDB (UID 999) could not write slow.log.
   Pre-create `/logs/db/slow.log` with correct ownership before container starts

7. **wait_db subshell** — `DB_ROOT_PASS` was unbound under `set -u` in spawned
   bash subshell. Rewrote as a plain loop without `timeout bash -c`

8. **Secret writeback** — `DB_ROOT_PASS=  # comment` lines were not matched by
   writeback regex. Fixed with `grep -qP` to strip trailing comments

### Added
- `version: '3.9'` removed from docker-compose.yml (obsolete in Compose v2)
- Selective `docker compose pull` — skips locally-built images
- Per-run install logs in `~/logs/install/`
- `actools log-dir` CLI command

---

## [v9.1] — Prior Release

- S3FS config keys corrected to `$config['s3fs.settings']`
- Backup cron: added `cd "${INSTALL_DIR}"` before docker compose calls
- storage-info CLI: re-sources actools.env at runtime
- CDN + endpoint injected in settings.php
- Lock file: touch before exec to prevent Permission denied on re-run

## [v9.0] — Prior Release

- XeLaTeX moved inside worker container (self-contained, no host mounts)
- Multi-provider S3: aws, backblaze, wasabi, custom
- Provider auto-detection from S3_ENDPOINT_URL hostname
- S3-aware backup cron
- actools storage-test, storage-info, migrate CLI commands

---

## [v11.0.0] — 2026-03-26 — Phase 4: AI-Native Dev Environment

### Added
- Ollama 0.18.3 installed as system service
- deepseek-coder:1.3b model (776MB, CPU-optimized)
- `actools ai <question>` — ask anything with full codebase context
- `actools ai explain <file>` — explain any module file
- `actools ai review --security` — security vulnerability review
- `actools ai review --performance` — performance review
- `actools ai context` — rebuild codebase index
- modules/ai/assistant.sh — AI module with Ollama API integration
- Context builder indexes all core/, modules/, cli/ bash files
- Low temperature (0.2-0.3) for precise, factual code answers

---

## [v10.6.0] — 2026-03-26 — Phase 3 Complete

### Added
- `actools migrate --plan` — shows pending Drupal updates + table sizes
- `actools migrate --apply` — pre-backup + drush updb + health check
- `actools migrate --rollback` — one-command rollback to pre-migration snapshot
- gh-ost 1.1.8 installed — online schema changes for tables >100k rows
- modules/migrate/migrate.sh — zero-downtime migration module

## [v10.5.0] — 2026-03-26

### Added
- `actools ci --generate` — generates 3 GitHub Actions workflows
  - github-test.yml — PHP CodeSniffer, PHPStan, composer validate
  - github-deploy.yml — backup + pull + updb + health check
  - github-security.yml — weekly composer audit + Drupal advisories
- templates/ci/ — CI workflow templates with variable substitution

## [v10.4.0] — 2026-03-26

### Added
- `actools branch <name>` — create isolated preview environment
- `actools branch --list` — list active previews
- `actools branch --destroy <name>` — clean destroy (DB, container, vhost)
- `actools branch --cleanup` — auto-remove previews older than 7 days
- Preview auto-cleanup daily cron
- modules/preview/branch.sh — full preview environment lifecycle
- Requires wildcard DNS: *.yourdomain.com

## [v10.3.1] — 2026-03-26

### Added
- Quantum-safe TLS — HTTP/3 (h1 h2 h3) enabled in Caddy 2.8
- X25519Kyber768 post-quantum key exchange active
- SSL Labs rating: Forward Secrecy ROBUST

### Fixed
- Backup cron: mariadb-dump correct password, removed duplicate BACKUP_PASS

## [v10.2.0] — 2026-03-26

### Added
- Prometheus + Grafana observability stack
- 3 pre-built dashboards: Node Exporter Full, cAdvisor, Redis
- docker-compose.observability.yml — separate compose file
- Prometheus data source auto-configured via API

## [v10.1.0] — 2026-03-26

### Added
- `actools health --verbose` — full system health report
- `actools health --cost` — memory optimization report
- `actools cost-optimize` — reads real Docker stats, suggests memory changes
- modules/health/checks.sh — container, TLS, disk, MariaDB, Redis checks
- Worker container stable — loop with sleep instead of crash-restart
