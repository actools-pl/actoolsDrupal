# Runtime Authority Map

> **Recorded at phase P0-A** (doc-only) by adopting the verified synthesis
> `00_reference/actools-phase0-implementation-plan.md` (= `design/actools-phase0-implementation-plan.md`).
> Every "Evidence" cell below was **spot-verified read-only** against the uploaded repo
> export `actoolsDrupal-main` during P0-A. No runtime file was modified. The synthesis
> was *adopted, not re-derived* (per the P0-A phase file, step 0).
>
> Base reference: the plan was built against git `839d3c8`; the operator must record the
> actual `main` HEAD when applying (the export carried no `.git`). P0-A changes only
> `docs/`+`design/` content, so this map is not base-sensitive.

## Purpose

This file records which source file is authoritative for each runtime concern. It prevents
future AI windows from editing orphaned or parallel code. **Every phase must update this map
if it changes which file is authoritative for any runtime behaviour.**

## Status legend

- `current` — the file that actually runs today on the live install path.
- `parallel` — a second live implementation of the same concern (a split that must be collapsed).
- `orphan` — present in the repo but sourced/called by nobody on the live path (reference only).
- `target` — where the concern is meant to live after Phase 0 (per LOCKED §2/§5/§6).
- `unknown` — not yet established.

A row may carry a compound status (e.g. `current (monolithic) → target via dispatcher; orphan twin exists`).

## Current-state map (verified)

| Runtime concern | Current authority (verified) | Parallel / orphan copy (verified) | Target authority (LOCKED) | Status |
|---|---|---|---|---|
| **Bootstrap variables** | `actools.sh` — `INSTALL_DIR` is `BASH_SOURCE`-relative (`actools.sh:94`), `ENV_FILE="$INSTALL_DIR/actools.env"` (`actools.sh:98`); `set -euo pipefail` (`:38`), `IFS=$'\n\t'` (`:39`), `ERR` trap (`:41`) | `core/bootstrap.sh` — **orphan v9.2** (`:4` "Extracted from actools.sh v9.2…", `:7` `ACTOOLS_VERSION="9.2"`); **different path semantics**: `INSTALL_DIR="$REAL_HOME"` (`:18`), `ENV_FILE="$REAL_HOME/actools.env"` (`:13`). No live `source .*core/` exists (0 hits from `actools.sh`/`installer/`/`cli/`) | One bootstrap, one path semantics, one version string (`BASH_SOURCE`-relative) — LOCKED-§6 item via WP-0(c)/P0-F + WP-7/P0-B·J | **current** in `actools.sh`; `core/bootstrap.sh` = **orphan** (path-divergent). Decision (P0-F): kill the `$REAL_HOME` variant. |
| **Init** | `installer/init.sh` (invoked by `actools.sh`) — parses `--profile`/`--profile=*` (`init.sh:40-41`), validates **list membership** only (`:62-63`, fallback list `community community-plus test`), persists `ACTOOLS_PROFILE` (`:117-121`) | `core/secrets.sh` is **named only in a comment** (`init.sh:12`), **not sourced**; `init.sh` does **not** source `installer/profile.sh` (0 hits) | `installer/init.sh` — profile-aware: source `profile.sh`, validate **file existence**, enforce actor/ticket, consume `PROFILE_INIT_FIELDS` (LOCKED §6 #2-3) | **partial** — `--profile` present; **gaps**: validates list not file existence; no `profile.sh` source; `--actor-id`/`--change-ticket` unhandled. → P0-E + P0-H (alignment §4.3) |
| **Profile loading** | `installer/profile.sh` — loads `profiles/${ACTOOLS_PROFILE}.profile` (`:21`), `exit 1` on missing file (`:28`); accessors **already exist**: `profile_requires_actor` (`:38`), `profile_requires_change_ticket` (`:39`), `profile_init_fields` (`:40`) | `profiles/README.md` narrative; `profiles/test.profile` and `profiles/community-plus.profile` are **absent** (only `profiles/community.profile` exists) | `installer/profile.sh` + the resolver layer (LOCKED §2 Decision 1) | **partial** — loader + accessors present and sound; not yet consumed by `init`; loadable `test.profile` to be added (S6 → P0-E/P0-I) |
| **Install-stage orchestration** | `actools.sh::main()` — **hardcoded** sequence: `setup_stack` (`:1606`), `install_env` loop (`:1618/:1622`), `setup_backup_cron` (`:1625`), `setup_cli` (`:1626`), `tls_check` (`:1627`). `run_install_stage`/`resolve_install_stage` = **0 hits repo-wide** | `profiles/community.profile:28` defines `PROFILE_INSTALL_STAGES=(host stack db drupal worker)` — **looped by nothing** | A stage dispatcher: `main()` iterates `PROFILE_INSTALL_STAGES` via `run_install_stage`/`resolve_install_stage` (LOCKED §6 #5, Decision 3 append-only) | **absent** — the dispatcher mechanism does not exist. → P0-D (append-only guard, alignment §4.5) |
| **Host setup** | `actools.sh::setup_stack()` host block (within `:569-1036`) — inline | `modules/host/*` — **orphan v9.2** (`docker.sh`, `firewall.sh`, `kernel.sh`, `logrotate.sh`, `packages.sh`, `swap.sh`); no live `source` from outside its own tree | `modules/host/*` reached **through the dispatcher** (LOCKED §5/§6) | **current** inline in `setup_stack`; `modules/host/*` = **orphan**, not migrated. → P0-G (after P0-C golden net) |
| **Stack setup** | `actools.sh::setup_stack()` (`:569-1036`, **468 lines, 10 heredocs**) — generates `my.cnf` (`:595`), `Dockerfile.caddy` (`:607`), `Dockerfile.php` (`:624`), `Dockerfile.worker` (`:634`), `Caddyfile` (`:663`), `docker-compose.yml` (`:795`) + all-in-one/redis/cadvisor fragments (`:715/:891/:974/:992`) | `modules/stack/*` — **orphan v9.2** (`caddyfile.sh`, `compose.sh`, `images.sh`, `mycnf.sh`); no live `source` from outside its own tree | `modules/stack/*` (or per-stage modules) **through the dispatcher**, with golden fixtures (LOCKED §5/§6) | **current (monolithic)** in `setup_stack`; `modules/stack/*` = **orphan**, not migrated. The single hardest extraction. → P0-G |
| **DB provisioning** | `actools.sh::install_env()` (`:1116`) — inline `db_exec_root` SQL creating DB/user/grants; `db_exec_root` defined at `actools.sh:1037` | `modules/db/*` exists (shellchecked in CI `lint.yml:27`); live DB SQL is inline in `install_env` | `modules/db/*` (or `db` stage handler) via dispatcher | **current (monolithic)** in `install_env`. → P0-D maps the `db` stage to the existing function unchanged; extraction is P0-G scope |
| **Drupal provisioning** | `modules/drupal/provision.sh` — **sourced LIVE** at `actools.sh:183`; `drupal_provision "$env"` called from `install_env` (`:~1152`) | none known | `modules/drupal/provision.sh` via dispatcher | **live (module)** — the *one* module sourced on the live path; the cleanest precedent for the extraction pattern |
| **Worker provisioning** | `actools.sh::setup_stack()` worker image (`Dockerfile.worker` `:634`) + worker service in the compose heredoc; CLI `cli/commands/worker.sh` | `modules/worker/*` exists (shellchecked `lint.yml:41`); live worker wiring is inside `setup_stack`/compose | `modules/worker/*` (or `worker` stage handler) via dispatcher | **current (monolithic)** within `setup_stack`. → P0-G |
| **CLI install** | `actools.sh::setup_cli()` (`:1247`) — **heredoc-generated** CLI: `cat > /usr/local/bin/actools <<HELPER` (`:1251`), unquoted `HELPER` ends `:1520` (so `$`/`$( )` expand at install time) | `cli/actools` (v14.0, profile-aware static CLI) + `cli/commands/*.sh`; installed only via DR (`modules/dr/resurrect.sh:153` `cp /home/actools/cli/actools /usr/local/bin/actools-real`). `cli/actools:12-15` **falsely** claims "There is no setup_cli.sh heredoc generator in this codebase" | **One** canonical source — deploy `cli/actools` to `/usr/local/bin/actools`; delete the `HELPER` heredoc (LOCKED §5; ROADMAP `ROADMAP.md:105-120` names `cli/actools` as canonical) | **parallel** (two divergent CLIs). → P0-F (CLI authority); false comment removed in P0-F; orphan/heredoc deletion in P0-J |
| **Preflight** | `installer/preflight.sh` — loads profile extras but only `print_skip`s them (`:154`); resolvers **available, not called** ("not called in D.0", `:148`, `:178`) | profile `PROFILE_PREFLIGHT_EXTRA` arrays (defined, not dispatched) | resolver-backed `preflight`: route extras via `resolve_preflight_check`; **fail unknown for non-default** (LOCKED §6 #4) | **partial** — loads, skips, never fails. → P0-H |
| **Doctor** | `cli/commands/doctor.sh` — **hard-sources** `cli/commands/doctor_deep.sh` (`:34`) then `run_doctor_deep` (`:35`); sources `dispatch.sh \|\| true` (`:58`) but does not use it for the deep handler; prints active profile (`:63`) | the generated-CLI `doctor` path (inside the `HELPER` heredoc); `PROFILE_DOCTOR_EXTRA` absent | resolver-backed `doctor`: replace the hard `source doctor_deep.sh` with `resolve_feature_handler`; consume `PROFILE_DOCTOR_EXTRA` (LOCKED §2 Decision 1 — its own example; §6 #6) | **split** (static + generated) & hard-sourced. → P0-F (unify) then P0-H (resolve) |
| **Handoff** | `installer/handoff.sh` — built-in sections `(site admin commands log)` (`:30`); reads profile sections via `profile_handoff_sections` (`:38`) but unknown names hit a **silent `*)`** (`:77-78`); "not called in D.0" (`:35`) | the generated-CLI `handoff` path (inside the `HELPER` heredoc) | resolver-backed `handoff`: `resolve_handoff_section` instead of the silent `*)` (LOCKED §6 #7) | **partial** — silent skip. → P0-H |
| **Resolver layer (the seam)** | `installer/dispatch.sh` — **sourced but uncalled on the live path** ("D.0 establishes the seam only", `:19-20`); guard `_ACTOOLS_DISPATCH_SOURCED` (`:27-28`). `resolve_feature_handler` (`:60`) returns a **token** not a path: `community`→`""` (`:64`), `community-plus`→`"plus_${feature}"` (`:67`), `test`→`"test_${feature}"` (`:70`). Split resolvers exist: `resolve_preflight_check` (`:84`), `resolve_doctor_check` (`:108`), `resolve_handoff_section` (`:132`). The LOCKED-named generic `resolve_profile_check` = **0 hits** | the bats fixture `tests/fixtures/profiles/test/*` (`manifest.sh`, `plus_*` stubs) exercises resolvers **in isolation**, not through any surface | `resolve_feature_handler` implementing the **3-tier path order** (profiles.d override → profile module → default/gate); a `resolve_profile_check <surface> <check_id>` umbrella delegating to the per-surface internals (LOCKED §2 Decision 1; §6 #1) | **partial** — primitives exist, return tokens, uncalled live. → P0-E (3-tier order + `resolve_profile_check` name; alignment §4.1/§4.2) then P0-H (wire surfaces) |
| **Generated compose** | `actools.sh` heredoc `docker-compose.yml` (`:795`) + service fragments (`:891/:974/:992`) | `modules/stack/compose.sh` (**orphan**) | module + **golden fixtures** (LOCKED §6; generated-file contract) | **monolithic** + orphan twin. Golden capture is P0-C; extraction P0-G |
| **Generated Caddyfile** | `actools.sh` heredoc `Caddyfile` (`:663`) | `modules/stack/caddyfile.sh` (**orphan**) | module + golden fixtures | **monolithic** + orphan twin. → P0-C / P0-G |
| **Generated my.cnf** | `actools.sh` heredoc `my.cnf` (`:595`) | `modules/stack/mycnf.sh` (**orphan**) | module + golden fixtures | **monolithic** + orphan twin. → P0-C / P0-G |
| **Generated Dockerfiles** | `actools.sh` heredocs `Dockerfile.caddy` (`:607`), `Dockerfile.php` (`:624`), `Dockerfile.worker` (`:634`) | `modules/stack/images.sh` (**orphan**); `docs/CHANGELOG.md:113` **falsely** claims "All Dockerfiles moved to template variables — no more bash heredoc embedding" | module + golden fixtures | **monolithic** + orphan twin; doc claim false. → P0-C / P0-G; CHANGELOG fixed in P0-B/P0-J |
| **Generated CLI** | `actools.sh::setup_cli()` `HELPER` heredoc (`:1251-1520`) | `cli/actools` (static, canonical-elect) | one source (`cli/actools`), with golden/parity tests | **parallel** (see "CLI install"). → P0-F |

## Verified secondary facts (carried into later phases)

- **Profile-/resolver-blindness of the live spine.** In `actools.sh`: `ACTOOLS_PROFILE` = 0 refs, `PROFILE_INSTALL_STAGES` = 0, `resolve_` = 0, `dispatch::` = 0. The seam is entirely outside the file that actually installs.
- **Secret-ordering hazard (encode as a guard in P0-G).** `gen_if_empty DB_ROOT_PASS` precedes `MARIADB_ROOT_PASSWORD: "${DB_ROOT_PASS}"` rendered in the compose heredoc (`:795+`); the file carries `[fix4]/[fix7]` scars. Any stage that renders before secret-gen reintroduces an empty root password.
- **Test surface = 76 bats tests** (`tests/test_d0_dispatch.bats` 33, `tests/installer/init_test.bats` 11, `tests/installer/preflight_test.bats` 6, `tests/installer/doctor_test.bats` 5, `tests/core/validate_test.bats` 11, `tests/core/secrets_test.bats` 10). `docs/architecture.md:49` ("21 bats tests") is stale.
- **Resolver-bypass guard already exists** at `tests/test_d0_dispatch.bats:226` ("sibling-scope audit: every `ACTOOLS_PROFILE` reader sources `dispatch.sh` or is `DISPATCH_EXEMPT`", grep at `:249`). Preserve and extend it (alignment §4.4 → P0-I).
- **CI gaps.** `.github/workflows/lint.yml` shellchecks the orphans (`core/*.sh` `:25`, `modules/host/*.sh` `:26`, `modules/stack/*.sh` `:39`, `cli/actools` `:30`, `installer/*.sh` `:32`) **but not `actools.sh`** (the largest live file). `.github/workflows/e2e.yml:84` runs `./actools.sh install` with **no** `--profile`, **no** `ACTOOLS_PROFILE`, **no** fixture profile. Adding `actools.sh` to shellcheck and the fake-profile e2e is owned by **P0-I** (S2).
- **Doc contradictions (P0-B/P0-J).** `docs/architecture.md`: "v11.2.0+" (`:3`), "the CLI … never contains business logic" (`:9`), "21 bats tests" (`:49`), `"version":"11.2.0"` + `phases_complete` state machine (`:84-87`), `actools-real` (`:119`) — all false vs code. `docs/CHANGELOG.md:113` Dockerfile claim false. `cli/actools:12-15` false self-comment.
- **Design-canon home (build-trigger #2)** was **absent** before P0-A (`design/` did not exist; LOCKED/brief/arch not committed under `docs/` or `design/`). P0-A creates `design/` with the three canon files.

## Update rule

Every phase must update this map if it changes authority.

## Review question

Before merge, ask:

> Did this phase change which file is authoritative for any runtime behavior?

P0-A answer: **No.** P0-A added `docs/`+`design/` content only; no `current` authority moved. The first authority move is **P0-D** (install-stage orchestration: `actools.sh::main()` hardcoded sequence → stage loop, behaviour-preserving). Update this map and the ledger at that phase.
