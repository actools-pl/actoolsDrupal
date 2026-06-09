# Handoff — P0-G · Extract Host and Stack Logic

## Repository state

Branch: `phase0/P0-G-extract-host-stack`
Commit SHA: `de64958` (G1), `47b05d8` (G2), `860d4a0` (G3), `74bc5b0` (G4), `e6af4fb` (G5), `0b220ce` (G6), `433a3c2` (G7) — code + tests; a follow-up docs commit lands the docs listed below.
Working tree clean? yes (after the docs commit)
Zip/package name if applicable: `actoolsDrupal-main`

## Task completed

Moved the live host-provisioning and stack-generation business logic out of the
monolithic `actools.sh::setup_stack()` into the canonical modules and drove them
through the install-stage dispatcher (P0-D). Host provisioning now lives in
`modules/host/*` (driven by `stage_host` in the canonical 7-step order); the four
stack generators live in `modules/stack/*` and are called by `setup_stack`, now a
~53-line thin orchestrator. This is an **authority** move with **no change to
generated output**: the six stack files are **byte-identical** (golden drift 6/6,
**no fixture modified**), and `actools.sh` shrank from 1416 → 871 lines. The
golden harness was reworked to render via the modules directly.

## Files changed

- `actools.sh` — **1416 → 871 lines**: inline host block **deleted** (now driven
  by `stage_host`); two module-sourcing loops added (host: `packages age kernel
  swap firewall docker logrotate`; stack: `mycnf images caddyfile compose`);
  `setup_stack()` (`:430-483`) reduced to a thin orchestrator (prologue →
  `generate_mycnf` → `build_caddy_image`/`build_php_image`/`build_worker_image` →
  `generate_caddyfile` → `generate_compose` → `docker compose pull/down/up` →
  `setup_backup_db_user`). `setup_cli()` (`:702-717`) untouched.
- `modules/host/{packages,age,kernel,swap,firewall,docker,logrotate}.sh` — **now
  live authority**; byte-identical to the monolith host steps. `docker.sh`'s
  `local bashrc` is the one intentional adaptation; `packages.sh` restores `age`.
- `modules/stack/mycnf.sh::generate_mycnf` — body byte-identical; env-default
  `${INNODB_BUFFER_POOL:-1G}`; dropped the orphan's stale `log "my.cnf generated."`.
- `modules/stack/images.sh::{build_caddy_image,build_php_image,build_worker_image}`
  — bodies byte-identical; caddy heredoc QUOTED; php keeps the
  `if [[ ! -f Dockerfile.php ]]` guard + verbatim multi-space `docker build`;
  worker multi-line `--build-arg`. Replaced the orphan (which lacked `build_php_image`).
- `modules/stack/caddyfile.sh::generate_caddyfile` — body byte-identical; UNQUOTED
  `CADDY` heredoc; full security headers; `/health` + `/csp-violations`; `@login
  rate_limit`; embedded all-in-one fragment. Replaced the very stale orphan.
- `modules/stack/compose.sh::generate_compose` — body byte-identical **except** one
  `# shellcheck disable=SC2034` on `local REDIS_MEM` (confirmed false positive —
  used at `:262-263` in the nested `REDIS_SVC` fragment; no output impact);
  preserves the redis-off `depends_on` quirk. Replaced the very stale orphan.
- `tests/helpers/capture_golden_outputs.sh` — **harness rework**: sources the four
  stack modules and calls the generators directly; `eval "$(sed -n SS_START,SS_END)"`
  + `setup_stack` call removed; `SS_*` deleted; `_assert_fn_range "setup_stack"`
  replaced by a new `_assert_fn_defined()` guard; `setup_cli` (`SC_*`) pin kept as
  the P0-F drift canary; header/comments/log text updated.
- `tests/installer/dispatch_stages_test.bats` — `setup()` exports `ACTOOLS_SH`;
  **+2 tests** (`stage_host` canonical-order, G2; `setup_stack` delegation order,
  G7); BLOCK 2 header notes the modular delegation.
- Docs: `docs/architecture/runtime-authority-map.md`,
  `docs/architecture/phase0-seam-contract.md`, `docs/CHANGELOG.md`,
  `docs/releases/P0-G-extract-host-stack.md`, `docs/tests/P0-G-extract-host-stack.md`,
  `docs/runbooks/PHASE0_LEDGER.md` (Entry 012), this handoff.

## Files not changed but relevant

- **No golden fixture modified** — all 30 fixtures byte-identical; drift 6/6.
- DB user/credential creation (`setup_backup_db_user`, the `install_env` DB SQL) —
  **folded, out of scope**; the `db` stage stays a documented no-op.
- Worker **runtime** (the worker compose service) — stays inside the compose
  generator; the `worker` stage stays a no-op. Only the worker **image** build
  moved (`build_worker_image`).
- `docker compose pull/down/up` — stays in `setup_stack` (orchestration).
- `modules/worker/*`, `modules/db/*` — exist but remain off the live path.
- `docker-compose.observability.yml` / `modules/observability/prometheus.sh` —
  **git-ignored**, untracked, out of scope.

## Runtime authority impact

| Area | Impact |
|---|---|
| Bootstrap | none |
| Init | none |
| Profile loading | none |
| Install stages | **`host` wired** to the seven `modules/host/*` functions (canonical order); **`stack`** runs `setup_stack`, now delegating to the four `modules/stack/*` generators; `db`/`worker` remain documented no-ops (folded) |
| CLI | none (P0-F unchanged) |
| Generated files | **generation relocated** to `modules/stack/*`; output **byte-identical** (golden drift 6/6) — an authority move, not an output change |
| Preflight | none |
| Doctor | none |
| Handoff | none |

## Generated-file impact

| File | Result |
|---|---|
| docker-compose.yml | unchanged (byte-identical; generation moved to `modules/stack/compose.sh`; golden 6/6) |
| Caddyfile | unchanged (byte-identical; moved to `modules/stack/caddyfile.sh`; golden 6/6) |
| my.cnf | unchanged (byte-identical; moved to `modules/stack/mycnf.sh`; golden 6/6) |
| Dockerfiles | unchanged (byte-identical; moved to `modules/stack/images.sh`; golden 6/6) |
| CLI | not touched (P0-F territory) |

## Tests run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline @ 37b09c8):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# AFTER (re-run at every generated-file move):
bats tests/generated/golden_drift_test.bats                                 # 6/6 (fixtures unchanged)
bats tests/installer/dispatch_stages_test.bats                              # 14/14
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 129/129

# Syntax + lint:
bash -n actools.sh
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
shellcheck modules/host/*.sh modules/stack/*.sh                             # clean
shellcheck --severity=warning tests/helpers/capture_golden_outputs.sh      # clean
```

## Test result

PASS — golden drift **6/6** (six stack files byte-identical; **fixtures
untouched**); unit/integration **129/129** (127 prior + 2 new); **135/135**
overall; all `bash -n` clean; `modules/host/*`, `modules/stack/*`, and the harness
shellcheck-clean (warning+). `actools.sh` 1416 → 871 lines.

## Docs updated

Runtime authority map (Host/Stack/Worker/Generated-file rows flipped to
modules=live; install-stage `host` no-op→wired; test count 133→135; CI-gaps note;
secret-ordering note; P0-G answer); phase0 seam contract (implementation-status
note); CHANGELOG (P0-G section); release note (with Rollback + per-file table +
host-behaviour diffs + SC2034 note); test report; ledger Entry 012.

## Changelog / release notes updated

Yes — `docs/CHANGELOG.md` (Unreleased → P0-G), `docs/releases/P0-G-extract-host-stack.md`
(incl. `## Rollback`), `docs/tests/P0-G-extract-host-stack.md`.

## Ledger entry

Entry number: **012**

## Known risks

- **`setup_stack` body coverage moved off the golden path** (the harness now calls
  generators directly). Mitigated by the new `setup_stack`-delegation test (real
  orchestrator + recorder stubs). Confirm that test, not just drift.
- **Host steps are now fresh-install-only** — four deliberate behaviour
  differences (dry-run no longer mutates the host; interactive-N aborts before host
  changes; `update`/`env` no longer re-run host provisioning). Fresh-install happy
  path byte-identical; host steps were already idempotent.
- **One `compose.sh` SC2034 suppression** — confirmed false positive; no output
  impact; drift 6/6.
- **Stale `modules/{host,stack}/*` orphans replaced** with the monolith's exact
  bytes — treat the module as the live authority.

## Blockers

None.

## Exact next allowed task

**P0-H — Surface wiring** (the Review Gate owns sequencing): wire the *selected*
profile into the install spine (`ACTOOLS_PROFILE`-driven) and route the
preflight/doctor/handoff surfaces through the resolvers completed in P0-E.
Alternatively, **P0-I** CI/shellcheck hardening (add `actools.sh` to shellcheck;
fake-profile e2e). With host/stack extracted and the CLI consolidated, the
remaining Phase-0 work is surface/resolver wiring and CI hardening.

## Explicitly forbidden scope for next task

No DB user/credential extraction or worker-runtime extraction (still folded — not
this phase); no profile-semantics changes; no community-plus feature commands; no
touching the golden fixtures or widening/disabling the harness guards; no
authoring or modifying observability (out of scope, git-ignored); no source-guard
change around `main()` in `actools.sh`.

## Review Gate notes

A separate session (ideally a different model) renders APPROVED / NEEDS REVISION /
BLOCKED. Reviewer checklist: (1) golden drift **6/6** with **fixtures unmodified**
(the relocation preserved output); (2) only allowed files touched; (3)
`modules/host/*` + `modules/stack/*` bodies byte-identical to the monolith blocks
(the one exception is the documented `compose.sh` SC2034 comment, no output
impact); (4) `stage_host` drives the seven host functions in monolith order and
`setup_stack` delegates to the six generators in canonical order (both asserted by
tests); (5) the harness renders via the modules directly (no `setup_stack` eval /
no `SS_*`), and `_assert_fn_defined` + the `setup_cli` canary are green, not
widened/disabled; (6) the redis-off `depends_on` quirk is preserved (validated by
the `redis-off` golden).
