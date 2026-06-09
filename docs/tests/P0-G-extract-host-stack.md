# P0-G Extract Host and Stack Logic — Test Report

> **Status:** Passing — host provisioning and stack generation extracted into
> `modules/host/*` and `modules/stack/*` behind the install-stage dispatcher;
> all six generated stack files **byte-identical** (golden drift 6/6); the
> golden harness now renders via the modules directly.
> Phase: P0-G — Extract Host and Stack Logic
> Produced by: Coding Window (Opus)
> Date: 2026-06-09

---

## Summary

P0-G moves the live host steps and the four stack generators out of the
monolithic `actools.sh::setup_stack()` into the canonical modules
(`modules/host/*`, `modules/stack/*`) and drives them through the dispatcher
(`stage_host`) and the now-thin `setup_stack` (which calls the four
`modules/stack/*` generators). The defining property is that this is an
**authority** move with **no change to generated output**.

Defining properties this phase must hold (all verified below):

- **Generated output byte-identical.** The six stack files (`my.cnf`,
  `Dockerfile.caddy`, `Dockerfile.php`, `Dockerfile.worker`, `Caddyfile`,
  `docker-compose.yml`) match their golden fixtures across all five variants —
  **golden drift 6/6**, fixtures untouched.
- **Host order preserved.** `stage_host` invokes the seven host functions in the
  exact monolith order `packages → age → kernel → swap → firewall → docker →
  logrotate`.
- **Stack delegation preserved.** `setup_stack` calls the six generators in the
  canonical order `generate_mycnf → build_caddy_image → build_php_image →
  build_worker_image → generate_caddyfile → generate_compose`, then runs
  `docker compose pull/down/up` and `setup_backup_db_user`.
- **Module bodies byte-identical to the monolith.** Each generator body diffs
  empty against its monolith block (the one exception is a single
  `# shellcheck disable=SC2034` comment in `compose.sh`, no output impact).
- **Harness renders via modules.** The golden capture sources the four stack
  modules and calls the generators directly; no `setup_stack` sed-extract/eval.

---

## Test surface (before → after)

"Before" = clean P0-F baseline (`133`). P0-G adds **+2** tests, both in
`dispatch_stages_test.bats` (the `stage_host` order test added when wiring
`stage_host`, and the `setup_stack` delegation test added with the harness
rework). No other suite changed; **no golden fixture was modified**.

| Suite | Before | After | Δ |
|---|---:|---:|---:|
| `tests/core/validate_test.bats` | 11 | 11 | — |
| `tests/core/secrets_test.bats` | 10 | 10 | — |
| `tests/installer/init_test.bats` | 11 | 11 | — |
| `tests/installer/init_profile_test.bats` | 10 | 10 | — |
| `tests/installer/preflight_test.bats` | 6 | 6 | — |
| `tests/installer/doctor_test.bats` | 5 | 5 | — |
| `tests/installer/dispatch_stages_test.bats` | 12 | **14** | **+2** |
| `tests/installer/cli_authority_test.bats` | 14 | 14 | — |
| `tests/test_d0_dispatch.bats` | 48 | 48 | — |
| **Regression total** | **127** | **129** | **+2** |
| `tests/generated/golden_drift_test.bats` | 6 | 6 | — (fixtures unchanged) |
| **Grand total** | **133** | **135** | **+2** |

---

## Tests added — `tests/installer/dispatch_stages_test.bats` (+2)

Both run rootless; neither executes docker/apt/systemctl or any privileged
command.

1. **`real handler: stage_host drives the host modules in canonical monolith
   order (P0-G)`** (added when wiring `stage_host`) — installs recorder stubs for
   the seven host functions, runs `run_install_stage host`, and asserts the exact
   order `install_packages → setup_age_keypair → tune_kernel → configure_swap →
   configure_firewall → install_docker → configure_logrotate` (and exactly seven
   calls). `packages` first guarantees the `age` package exists before
   `setup_age_keypair`.
2. **`real orchestrator: setup_stack delegates to the stack generators in
   canonical order (P0-G)`** (added with the harness rework) — loads the **real**
   (now thin, heredoc-free) `setup_stack` from `actools.sh` by function boundary
   (`sed -n '/^setup_stack() {/,/^}/p'`, no line numbers), stubs the mkdir/chown
   prologue, the `docker compose pull/down/up` orchestration, and
   `setup_backup_db_user`, then asserts the six generators fire in canonical order
   (and nothing else emits). This restores the `setup_stack`-body coverage that
   the harness rework moved off the golden path.

---

## Golden drift — six stack files byte-identical (fixtures untouched)

The drift gate re-renders each of the five variants and compares SHA256 manifests
against the committed fixtures. P0-G changed **where** the files are generated
(the four `modules/stack/*` functions) but not **what** is generated, so all five
variants pass with the fixtures unchanged:

- `default`, `redis-off`, `s3-on`, `cadvisor-on`, `all-in-one` — all match.
- `redis-off` specifically validates the preserved quirk (unconditional
  `depends_on: redis` while the redis service is conditional).
- `all-in-one` validates the embedded `$(… ALLINONE …)` Caddyfile fragment and the
  `ALLINONE_SVC` compose fragment; `cadvisor-on` the `CADVISOR_SVC` fragment;
  `s3-on` the `S3_ENV_BLOCK`.

The harness now sources `modules/stack/{mycnf,images,caddyfile,compose}.sh` and
calls the generators directly; `_assert_fn_defined()` guards that each module
defines its expected generator, and `_assert_fn_range "setup_cli"` is retained as
the P0-F drift canary.

---

## Module-body fidelity checks (extraction-time)

Each generator was assembled by byte-for-byte `sed` extraction of its monolith
block and verified with an empty `diff` of the function body against the source
range:

- `modules/stack/mycnf.sh::generate_mycnf` — body == monolith my.cnf block.
- `modules/stack/images.sh::{build_caddy_image,build_php_image,build_worker_image}`
  — each body == its monolith block.
- `modules/stack/caddyfile.sh::generate_caddyfile` — body == monolith Caddyfile
  block (incl. the all-in-one fragment).
- `modules/stack/compose.sh::generate_compose` — body == monolith compose block
  **except** one `# shellcheck disable=SC2034` comment before `local REDIS_MEM`
  (`REDIS_MEM` is used at `compose.sh:262-263` inside the nested `REDIS_SVC`
  fragment; shellcheck cannot trace it; no output impact).
- `modules/host/*` — byte-identical to the monolith host steps; `docker.sh`'s
  `local bashrc` is the one intentional adaptation.

---

## Commands run

```bash
export PATH="$HOME/.npm-global/bin:$PATH"

# BEFORE (clean P0-F baseline):
bats tests/generated/golden_drift_test.bats                                 # 6/6
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 127/127

# AFTER (each unit, re-run at every generated-file move):
bats tests/generated/golden_drift_test.bats                                 # 6/6 (fixtures unchanged)
bats tests/installer/dispatch_stages_test.bats                              # 14/14
bats tests/core/*.bats tests/installer/*.bats tests/test_d0_dispatch.bats   # 129/129

# Syntax + lint:
bash -n actools.sh
find installer core modules cli -name '*.sh' -print0 | xargs -0 -n1 bash -n # clean
shellcheck modules/host/*.sh modules/stack/*.sh                             # clean
shellcheck --severity=warning tests/helpers/capture_golden_outputs.sh      # clean
```

---

## Result

PASS — golden drift **6/6** before and after (six stack files byte-identical;
fixtures untouched). Unit/integration **129/129** (127 prior + 2 new),
**135/135** overall. All `bash -n` clean; `modules/host/*`, `modules/stack/*`, and
the harness shellcheck-clean (warning+). `actools.sh` 1416 → 871 lines.

---

## Limitations / notes

- The new tests are static/structural plus rootless execution with recorder
  stubs; they do **not** exercise live `docker`/`apt`/`ufw` (no daemon in the test
  environment). Output fidelity is enforced by the golden drift gate; ordering by
  the recorder-stub assertions.
- This phase moves **host** and **stack** authority only. **DB** user/credential
  creation and **worker runtime** wiring remain folded (their stages stay
  documented no-ops); only the worker **image** build moved.
- The `modules/stack/compose.sh` SC2034 suppression is a confirmed false positive
  (see release note); it is the single deviation from byte-identical module
  bodies and has no effect on `docker-compose.yml`.
