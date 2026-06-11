# Phase 0 Unlock Decision Memo

## Verdict

Phase 0: **GO**
Post-closure track (P0-K…P0-P): **UNLOCKED**
community-plus feature work (evidence model): **gated behind P0-K…P0-P** — not yet unlocked

## Evidence summary

| Area | Result | Evidence |
|---|---|---|
| Resolver | PASS | `resolve_feature_handler` / `resolve_install_stage` / `resolve_profile_check` exist and are used; resolver-bypass static check passes (P0-E; resolver-bypass audit added P0-I). |
| Install-stage dispatcher | PASS | `run_install_stage` executes `PROFILE_INSTALL_STAGES` (P0-D). |
| Profile validation | PASS | `init --profile community` works; omitted → `community`; unknown + missing-file fail before persistence; profile-required actor + change-ticket enforced via `test.profile` (P0-E, P0-I). |
| Init | PASS | profile-aware (P0-H). |
| Preflight | PASS | profile-aware; unknown non-default profile checks fail cleanly (P0-H, P0-I). |
| Doctor | PASS | profile-aware; `--deep` baseline-fallback exits 2 (gate notice) (P0-H). |
| Handoff | PASS | profile-aware (P0-H). |
| CLI authority | PASS | single source `cli/actools`, installed verbatim to `/usr/local/bin/actools` by `setup_cli()` (`actools.sh:702-717`); `cli_authority_test.bats` enforces no heredoc generator (P0-F). |
| Generated files | PASS | golden drift **6/6** (docker-compose, Caddyfile, my.cnf, Dockerfiles); CLI output checked. Held across every phase. |
| Default e2e | PASS | `fresh-install` (community) job green (`e2e.yml`). |
| Fake-profile e2e | PASS | `tests/test_p0i_fake_profile_e2e.bats` 13/13 — asserts all 10 dispatch markers + failure paths + community-routes-through-NONE; whole tree **158/158** (P0-I). |
| Docs/changelog/ledger | PASS | P0-J documentation-truth pass corrected 12 files (phantom-command relabeling; CLI/architecture/roadmap corrections); CHANGELOG + ledger maintained; Entry 015 + this memo. |

## Remaining limitations

- **Fresh-install profile selection is not wired:** `main()` sources `profiles/community.profile` unconditionally (`actools.sh:804`). Selected-profile sourcing is deferred to **P0-P** and is meaningful only once a second product profile exists. No behavior gap today (community is the only product profile).
- **The stateless core, DB layer, and backup cron are still inline** in `actools.sh` (~871 lines). Modularization continues in **P0-K…P0-M** (extracted fresh from inline, with the orphan twins retired).
- **Standalone feature modules** (`ai`, `compliance/gdpr`, `dr`, `preview`, `observability`, PITR backup) are experimental/unwired. Disposition (wire / park / delete) is **P0-O**, gated by a completeness/currency/safety audit.
- **`doctor --deep`** is a gate notice (exit 2), not yet implemented.
- **Broad stale-content doc reconcile** (beyond the actively-false claims fixed in P0-J) is deferred to **P0-O**.

## Risks accepted

| Risk | Why accepted | Owner |
|---|---|---|
| `test.profile` ships under `profiles/` | Test-only seam; never selected by the community install (selection deferred); the only scanner of `profiles/*.profile` (the append-only guard) passes it (`+=`). | Phase 0 |
| Orphan modules remain in the tree | Now doc-labeled experimental/not-wired; the **duplicate-function guard lands in P0-K** to prevent accidental wiring; final disposition tracked for P0-O. | P0-O |
| Deferred install-spine sourcing | `community` is the only product profile, so there is no behavior gap; gated to P0-P. | P0-P |

## Promotion decision for target docs

- [x] Keep under `docs/target/phase0/operator/`
- [ ] Promote to `docs/operator/`
- [ ] Partially promote only implemented sections

Rationale: P0-K…P0-O may still shift architecture and docs; promote after P0-O's doc authority lock.

## Next allowed phase

GO:

```text
Post-closure modularization track — P0-K (Guards + stateless core extraction).
NOT "Phase 1" (term retired as overloaded). community-plus evidence-model feature
work is gated behind completion of P0-K…P0-P. See IMPLEMENTATION_PHASES_MASTER.
```

## Sign-off

Reviewer: Review Gate (Opus) / Conductor
Date: 2026-06-11
Confidence: High — architecture verified across P0-A…P0-I (drift held 6/6, whole suite 158/158, CLI single-source, resolver-bypass + exec-bit guards non-vacuous); the closure blockers were documentation-only and have been corrected.
