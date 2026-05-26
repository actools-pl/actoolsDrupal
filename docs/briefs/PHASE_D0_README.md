# D.0 — Community Seam Hardening (Resolver Dispatch Foundation)

**Phase status:** Delivered  
**Foundation version:** v14.1.0  
**Brief:** `docs/briefs/d0_phase_brief.md` (authored by Sir Opus)

---

## What D.0 delivered

A single canonical dispatch surface through which every operation entry point
asks "given the active profile, what is the handler for operation X?" and
receives a deterministic answer.

**New files:**

| File | Purpose |
|---|---|
| `installer/dispatch.sh` | Resolver function family + profile validation + `actools::cli::resolve_profile` |
| `tests/fixtures/profiles/test/manifest.sh` | Test fixture profile activator + handler stubs |
| `tests/fixtures/profiles/test/plus_preflight_check.sh` | Preflight stub |
| `tests/fixtures/profiles/test/plus_doctor_check.sh` | Doctor stub |
| `tests/fixtures/profiles/test/plus_handoff_section.sh` | Handoff stub |
| `tests/test_d0_dispatch.bats` | D.0 verification suite (33 tests) |
| `docs/briefs/PHASE_D0_README.md` | This file |

**Modified files:**

| File | What changed |
|---|---|
| `installer/init.sh` | `--profile` flag parsing; dispatch.sh sourcing; profile validation; writes `ACTOOLS_PROFILE` to `actools.env` |
| `installer/preflight.sh` | Sources `dispatch.sh` after `profile.sh` sets `ACTOOLS_PROFILE` |
| `installer/handoff.sh` | Sources `dispatch.sh` after `profile.sh` sets `ACTOOLS_PROFILE` |
| `cli/commands/doctor.sh` | Sources `dispatch.sh`; adds "Active profile" line |
| `cli/actools` | Global `--profile` flag parsing; `ACTOOLS_PROFILE` resolution via `actools::cli::resolve_profile`; exports profile |
| `actools.sh` | Sources `dispatch.sh` after `INSTALL_DIR` is set (covers all modes) |
| `README.md` | Added `--profile` paragraph |
| `CHANGELOG.md` | D.0 entry |

---

## What D.0 deliberately did NOT deliver

1. **No `plus_*` modules.** The seam is in place; modules arrive in D.1+.
2. **No resolver call sites.** `dispatch.sh` is sourced and available; it is
   not called from any entry point. Calling resolvers is D.1+ work.
3. **No install-stage refactor.** Stage dispatcher lands in D.1.
4. **No `actools.env` migration for existing installs.** Default-by-absence is
   the contract. Existing installs without `ACTOOLS_PROFILE` resolve to community.
5. **No `actools doctor --deep` changes.** Deep mode placeholder unchanged.

---

## D.0 defining property (verified)

Adding `--profile community-plus` to any `actools` command on a D.0 install
does nothing observable — because no `plus_*` modules exist. Community
installs produce byte-identical journey output to v14.1 (modulo the new
"Active profile" line in `actools doctor`).

---

## Where to find the dispatch surface

```bash
# The resolver function family:
installer/dispatch.sh

# The allowed profiles list (single source of truth):
grep "_ACTOOLS_ALLOWED_PROFILES" installer/dispatch.sh

# D.0 bats tests:
tests/test_d0_dispatch.bats

# Fixture profile:
tests/fixtures/profiles/test/

# Sibling-scope audit:
# All files reading ACTOOLS_PROFILE either source dispatch.sh or carry
# a DISPATCH_EXEMPT comment. The meta-test in test_d0_dispatch.bats enforces this.
```

---

## D.1 entry point

D.1 (install-stage dispatcher) hangs `plus_*` hardening modules off the
`PROFILE_INSTALL_STAGES` pattern. The first D.1 change is adding
`run_install_stage` and iterating `profile_install_stages` through it.
D.0's `actools::dispatch::resolve_feature_handler` is the D.1 entry point.
