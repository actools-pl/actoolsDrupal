# Release note — P0-G · Extract Host and Stack Logic

Phase: P0-G — Extract Host and Stack Logic
Branch: `phase0/P0-G-extract-host-stack`
Date: 2026-06-09
Status: pending Review Gate

## Summary

`actools.sh::setup_stack()` was a ~468-line monolith that inlined **both** live
host provisioning **and** all stack file generation as a stack of heredocs. P0-G
moves that business logic into the canonical modules that already existed as
**orphans**, and drives them through the install-stage dispatcher (P0-D):

- **Host** — the seven ordered host steps now live in `modules/host/*`
  (`packages`, `age`, `kernel`, `swap`, `firewall`, `docker`, `logrotate`) and
  are invoked by the dispatcher's `stage_host` handler. The inline host block is
  **deleted** from `actools.sh`.
- **Stack** — the four stack generators move to `modules/stack/*`
  (`mycnf.sh::generate_mycnf`, `images.sh::build_caddy_image`/`build_php_image`/
  `build_worker_image`, `caddyfile.sh::generate_caddyfile`,
  `compose.sh::generate_compose`). `setup_stack` is now a **thin orchestrator**
  (≈53 lines) that sources those modules, calls the generators in the same order,
  then runs `docker compose pull/down/up` (orchestration, not generation) and the
  out-of-scope `setup_backup_db_user`.

**This is an *authority* move, not an output change.** Unlike P0-F (which
intentionally changed the CLI), P0-G changes *which file is authoritative* for
host/stack behaviour while holding the produced artifacts **byte-identical**: the
six generated stack files match their golden fixtures across all five variants
(**golden drift 6/6**), and `actools.sh` shrinks from **1416 → 871** lines.

The golden-capture harness was reworked at the end of the phase to render fixtures
by **calling the modules directly** (no more sed-extract/eval of `setup_stack`),
so the test net now exercises the same module functions the installer runs.

## Scope — what moved, what did not

**Moved to modules (now live authority):**

- `modules/host/{packages,age,kernel,swap,firewall,docker,logrotate}.sh` — byte-identical
  to the monolith host steps. The single intentional host adaptation is
  `docker.sh`'s `local bashrc` (function-local, no behaviour change).
- `modules/stack/{mycnf,images,caddyfile,compose}.sh` — each generator body is a
  **byte-for-byte** extraction of the corresponding monolith heredoc block (see
  the per-file table). The one documented deviation is a single
  `# shellcheck disable=SC2034` comment in `compose.sh` (below).

**Intentionally NOT extracted (folded, out of P0-G scope):**

- DB user/credential creation (`setup_backup_db_user`, the `install_env` DB SQL)
  stays inline; the `db` stage remains a documented no-op handler.
- Worker **runtime** wiring (the worker compose service) stays inside the compose
  generator; the `worker` stage remains a no-op. Only the worker **image** build
  (`build_worker_image`) moved, as part of `images.sh`.
- `docker compose pull/down/up` stays in `setup_stack` as orchestration.

## Generated-file status (generated-file contract)

All six files are **Unchanged (byte-identical)**. P0-G relocates their
*generation* into `modules/stack/*`; it does not change their *content*.

| File | Status | Evidence |
|---|---|---|
| `my.cnf` | **Unchanged** (byte-identical) | generation moved to `modules/stack/mycnf.sh::generate_mycnf`; golden drift 6/6 |
| `Dockerfile.caddy` | **Unchanged** | moved to `modules/stack/images.sh::build_caddy_image`; golden drift 6/6 |
| `Dockerfile.php` | **Unchanged** | moved to `modules/stack/images.sh::build_php_image`; golden drift 6/6 |
| `Dockerfile.worker` | **Unchanged** | moved to `modules/stack/images.sh::build_worker_image`; golden drift 6/6 |
| `Caddyfile` | **Unchanged** | moved to `modules/stack/caddyfile.sh::generate_caddyfile`; golden drift 6/6 |
| `docker-compose.yml` | **Unchanged** | moved to `modules/stack/compose.sh::generate_compose`; golden drift 6/6 |
| CLI (`/usr/local/bin/actools`) | **Not touched** | P0-F territory; `setup_cli` untouched here (still pinned by the harness drift canary) |

## Per-file extraction (Unchanged / Changed)

"Changed" below means the *source line in the monolith* changed (the block moved
out); the *generated output* is unchanged in every case.

| Monolith block (old `setup_stack`) | New home | Body vs monolith | Notes |
|---|---|---|---|
| host provisioning (7 steps) | `modules/host/*` + dispatcher `stage_host` | byte-identical | `docker.sh` `local bashrc` is the one intentional adaptation |
| `my.cnf` heredoc | `modules/stack/mycnf.sh` | byte-identical | env-default `${INNODB_BUFFER_POOL:-1G}` (followed code, not the spec's stale "RAM-derived" claim); dropped the orphan's stale trailing `log "my.cnf generated."` |
| `Dockerfile.caddy` / `.php` / `.worker` heredocs + `docker build`s | `modules/stack/images.sh` | byte-identical | caddy heredoc QUOTED; php keeps the `if [[ ! -f Dockerfile.php ]]` guard + verbatim multi-space `docker build`; worker multi-line `docker build --build-arg`; both caddy/worker errors say "Check Docker build output above." |
| `Caddyfile` heredoc | `modules/stack/caddyfile.sh` | byte-identical | UNQUOTED `CADDY` heredoc; full security headers; `/health` + `/csp-violations`; `@login rate_limit`; embedded all-in-one `$(... ALLINONE ...)` fragment |
| `docker-compose.yml` heredoc | `modules/stack/compose.sh` | byte-identical **except one disable comment** | see SC2034 note below; the redis-off quirk is preserved (below) |

The four previous `modules/stack/*` orphans were **stale v9.2** (e.g. the Caddyfile
orphan carried a `servers { protocols h1 h2 h3 }` block absent from the monolith;
the compose orphan was prod-only with inline env and no all-in-one/cadvisor; the
images orphan lacked `build_php_image`). Each was **overwritten** with the
monolith's current exact bytes — the module is the live authority.

## The one documented deviation — compose SC2034

`modules/stack/compose.sh` carries a single `# shellcheck disable=SC2034` comment
immediately before `local REDIS_MEM=…`. `REDIS_MEM` **is** used — at
`compose.sh:262-263` inside the `$(… cat <<REDIS_SVC … )` fragment
(`--maxmemory ${REDIS_MEM}` and `mem_limit: "${REDIS_MEM}"`). ShellCheck cannot
trace a variable through a heredoc nested in a command-substitution nested in the
outer `COMPOSE` heredoc, so it reports a false positive. The comment sits before
the heredoc and has **zero output impact** (it is not emitted into
`docker-compose.yml`); golden drift 6/6 confirms the file is byte-identical.

## Preserved quirk — redis-off `depends_on`

In the compose generator the `php_prod`/`worker_prod` services declare
`depends_on: redis` **unconditionally**, while the `redis` *service* block is
conditional on `ENABLE_REDIS`. So with redis off, the generated file names `redis`
in `depends_on` without defining the service. This is the monolith's existing
behaviour and is **preserved deliberately** — it is validated by the `redis-off`
golden fixture.

## Intentional host-stage behaviour differences (from wiring `stage_host`)

Extracting the host block out of `setup_stack` and onto the `host` stage means the
host steps now run **only** on the dispatcher's fresh-install path. This corrects
pre-existing coupling; the differences are deliberate and bounded:

1. **Dry-run no longer provisions the host.** `--dry-run` previously fell into
   `setup_stack` and executed host mutations; it now prints config and exits
   before any stage runs. (Bug fix.)
2. **An interactive "N" aborts before host changes.** Declining the confirm prompt
   stops before the stage loop, so no host mutation occurs.
3. **`update` / `env` no longer re-run host provisioning.** Those modes never
   entered the stage loop; the host steps are fresh-install-only, matching intent.
   (Host steps were already idempotent.)
4. **Fresh-install happy path is identical.** `host → stack → db → drupal → worker`
   runs in order (auto-confirmed under CI/root), and every generated artifact is
   byte-identical (drift 6/6).

## Harness rework (golden capture)

`tests/helpers/capture_golden_outputs.sh` no longer sed-extracts and `eval`s
`setup_stack` by line range. It now sources the four stack modules and calls the
generators directly — `generate_mycnf`, `build_caddy_image`, `build_php_image`,
`build_worker_image`, `generate_caddyfile`, `generate_compose` — in
`setup_stack`'s order, against the same deterministic env. Consequences:

- `SS_START`/`SS_END` are **removed** (no `setup_stack` line range to maintain).
- `_assert_fn_range "setup_stack"` is replaced by `_assert_fn_defined()`, which
  fails loudly if any `modules/stack/<file>` goes missing or stops defining its
  expected generator.
- The `setup_cli` `SC_START`/`SC_END` pin is **kept** purely as the vestigial
  P0-F drift canary (it is not rendered).

Because the harness no longer touches `setup_stack`, its delegation is now covered
by a new dispatcher test, **"setup_stack delegates to the stack generators in
canonical order (P0-G)"**, which loads the real (thin, heredoc-free) `setup_stack`
by function boundary and asserts the six generators fire in order.

## Verification

```bash
export PATH="$HOME/.npm-global/bin:$PATH"
bats tests/generated/golden_drift_test.bats                                 # 6/6 (all six stack files byte-identical, all 5 variants)
bats tests/installer/dispatch_stages_test.bats                              # 14/14 (incl. stage_host order + setup_stack delegation)
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # full unit/integration
bash -n actools.sh
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
shellcheck modules/host/*.sh modules/stack/*.sh                             # clean
shellcheck --severity=warning tests/helpers/capture_golden_outputs.sh      # clean
```

**135/135 overall** (golden drift 6 + unit/integration 129). `actools.sh` 1416 →
871 lines; `setup_stack` 430–483 (thin); host + stack logic byte-identical in
`modules/host/*` and `modules/stack/*`.

## Rollback

Revert the P0-G commits (`de64958`, `47b05d8`, `860d4a0`, `74bc5b0`, `e6af4fb`,
`0b220ce`, `433a3c2`). No data migration is expected. The change is confined to
`actools.sh` (host block removed; stack heredocs replaced by module calls; two
module-sourcing loops added), `modules/host/*`, `modules/stack/*`,
`tests/helpers/capture_golden_outputs.sh`, `tests/installer/dispatch_stages_test.bats`,
and docs. **No golden fixture was modified** in P0-G.

Reverting restores the monolithic `setup_stack` (inline host block + the ten
stack heredocs), the stale `modules/stack/*` orphans, and the harness's
sed-extract/eval of `setup_stack` with its `SS_*` line range.

Operational notes for a rollback:

- **Generated artifacts are byte-identical before and after P0-G**, so a revert
  has **no effect** on `my.cnf`, the Dockerfiles, the `Caddyfile`, or
  `docker-compose.yml`, nor on container state.
- **Already-installed hosts are unaffected by a code revert.** The host steps are
  idempotent; re-running the installer after a revert reproduces the same state.
- The two git-ignored observability artifacts seen in some working trees
  (`docker-compose.observability.yml`, `modules/observability/prometheus.sh`) are
  **not** part of P0-G and are excluded by `.gitignore`; they are untracked either
  way.
