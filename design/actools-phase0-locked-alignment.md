# Alignment — LOCKED Community-Plus Spec ↔ Phase 0 Implementation Plan

*Companion to `actools-phase0-implementation-plan.md`. Purpose: confirm the implementation plan is a faithful execution path for **`Actools_Drupal_Community_Plus_LOCKED.md`** — that it implements every LOCKED Phase 0 item and both build-trigger conditions, honors all four locked architecture decisions, builds none of the locked-deferred community-plus modules, and relitigates nothing. The LOCKED design is treated as fixed input; this document does not re-open it.*

---

## 0. Alignment verdict

**The plan aligns.** Its eight work packages (WP-0 … WP-8) implement **all nine** LOCKED §6 Phase 0 items and **both** §11 build-trigger conditions, and they respect **all four** §2 architecture decisions without altering any of them. Everything the plan adds beyond the literal §6 list (golden-file net, CLI unification, orphan deletion, doc reconciliation, design-canon home) is either *explicitly required by the §11 build trigger* or falls squarely inside "the modularization/seam-readiness that precedes the build" — none of it touches a locked decision, the locked module layout, or the locked build order.

**Five spots need the plan to quote the spec's exact wording** (Section 4 below). None is a conflict; each is a place to pin the locked API/constraint so the implementation lands on the locked shape rather than a near-miss. The one that matters most is **Decision 1's three-tier resolution order** — the repo's resolvers currently return a token, and WP-5 must implement the exact path order the spec prints.

---

## 1. Traceability A — LOCKED §6 Phase 0 items + §11 triggers → work package

Every locked Phase 0 item maps to a WP, and every WP that touches Phase 0 maps back to a locked item. No locked item is unowned; no Phase 0 WP is out-of-scope.

| LOCKED §6 / §11 requirement | Current status (verified) | Delivered by | Note |
|---|---|---|---|
| **1.** Resolver layer: `resolve_feature_handler`, `resolve_install_stage`, `resolve_profile_check` | Partial — `resolve_feature_handler` returns a *token* not a path; `resolve_install_stage`=0 files; `resolve_profile_check` (spec name) split into preflight/doctor | **WP-2** (`resolve_install_stage`) + **WP-5** (full 3-tier `resolve_feature_handler`; reconcile `resolve_profile_check` name) | See §4.1, §4.2 |
| **2.** First-class `--profile` on `init`, persisted to `actools.env` | Present — parse/validate-list/default/persist (`init.sh:40-41,61,67,117-122`) | already shipped; **WP-5** closes the file-existence gap | LOCKED says "validate the profile **exists**" → WP-5 adds it (§4.3) |
| **3.** Profile-aware `init`: `PROFILE_INIT_FIELDS`, enforce `PROFILE_REQUIRES_ACTOR` + `PROFILE_REQUIRES_CHANGE_TICKET` | Absent | **WP-5** | Accessors already exist in `profile.sh`; WP-5 wires them (§4.3) |
| **4.** Profile-aware `preflight`: run extras through dispatch; **fail** unknown for non-default | Partial — loads extras, only `print_skip`s | **WP-5** | LOCKED requires fail-on-unknown for non-default |
| **5.** Install-stage dispatcher: iterate `PROFILE_INSTALL_STAGES` via `run_install_stage` | Absent | **WP-2** | The mechanism that makes Decision 3 (append `plus_*`) possible |
| **6.** Profile-aware `doctor`: `PROFILE_DOCTOR_EXTRA` | Absent (cosmetic only); `doctor.sh:34` hard-sources `doctor_deep.sh` | **WP-5** | LOCKED Decision 1 names this exact replacement (`doctor_deep.sh` → resolver) |
| **7.** Profile-aware `handoff`: `PROFILE_HANDOFF_SECTIONS` | Partial — silent `*)` for profile sections | **WP-5** | Replace silent skip with `resolve_handoff_section` |
| **8.** Seam bats tests: default works; unknown fails; **fake profile exercises every dispatch point** | Partial — resolvers tested in isolation; nothing drives the surfaces *through* dispatch | **WP-6** (+ **WP-1** golden) | §4.4 (resolver-bypass guard), §4.5 (append guard) |
| **9.** E2E exercises **default + a stub test profile** | Partial — default only; `test` fixture is bats-only, not loadable | **WP-6** | Adds loadable `profiles/test.profile` + e2e that asserts dispatch fired |
| **§11 trigger #1:** Phase 0 PRs merged, **green CI**, e2e with a **fake downstream profile** | Not met | cumulative **WP-1…WP-7**; flipped in **WP-7** | "One PR per WP, each green" is built to match this wording |
| **§11 trigger #2:** a published **design-canon home** (`design/` or `actoolsDrupal-design`) | Absent / unverified | **WP-0(d)** | Cheap; done first |

---

## 2. Traceability B — the four §2 locked decisions → how the plan honors them

| LOCKED §2 decision | What it fixes | How the plan honors it | The care-point |
|---|---|---|---|
| **Decision 1 — Resolver layer drives handlers** | Resolution order: (1) `profiles.d/${ACTOOLS_PROFILE}/commands/${feature}.sh` → (2) `modules/${profile_module}/${feature}.sh` → (3) `cli/commands/${feature}.sh` or gate stub | **WP-5** completes `resolve_feature_handler` to this exact order; **WP-5** replaces the hard-sourced `doctor_deep.sh` with the resolver (the spec's own example) | **§4.1** — today the resolver returns `plus_<feature>` (a token), not a resolved path. WP-5 must implement the three tiers verbatim. |
| **Decision 2 — First-class `--profile` on the staged journey** | `init` accepts/validates-exists/persists `--profile`; enforces actor + change-ticket; consumes `PROFILE_INIT_FIELDS`; default `community` | **WP-5** wires `init` to the existing `profile.sh` accessors (`profile_requires_actor`, `profile_requires_change_ticket`, `profile_init_fields`); validates file existence | **§4.3** — uses the accessors that already exist; the only new behavior is file-existence validation + actor/ticket enforcement |
| **Decision 3 — Stack hardening is APPENDED, not replaced** | Community `PROFILE_INSTALL_STAGES=(host stack db drupal worker)` stays; community-plus *appends* `plus_hardening plus_guardian plus_evidence`; **MUST NOT** define a `plus_stack` that replaces community `stack` | **WP-2**'s dispatcher iterates the stage array, so appending is the *only* extension mechanism; **WP-1/WP-3** golden tests prove community stages are byte-identical | **§4.5** — add an explicit test/guard that community's stage list is unchanged and no `plus_stack` shadows `stack` (also LOCKED §10 Risk 1) |
| **Decision 4 — Evidence is the differentiator** | Hash-chained logs, signed bundles, compliance mappings — the value of community-plus | **The plan deliberately does NOT touch this.** It ends at the seam and hands off to "begin LOCKED Phase 1 (Evidence Model)." | Correct by omission — Decision 4 is LOCKED **Phases 1–6**, out of Phase 0 scope (§3 below) |

---

## 3. Scope guardrails — what Phase 0 must NOT do (and confirmation it doesn't)

The LOCKED doc is a "Code Jail" (§11): Phase 0 makes community-plus *possible* without building it. The plan stays inside the jail:

- **Builds no `plus_*` module.** LOCKED §5 lists `plus_hardening`, `plus_scanner`, `plus_governance`, `plus_audit_guardian`, `plus_compliance`, `plus_doctor_deep` as **NEW** modules for Phases 1–6. The plan creates **none** of them. WP-5 only builds the *resolution path* those future modules will plug into. ✔
- **Creates no new community-plus CLI commands.** LOCKED §5 lists `audit_deep.sh`, `baseline.sh`, `evidence.sh`, `verify.sh`, `compliance.sh`, `policy.sh`, `approve.sh`, `hardening_sync.sh`, `adopt.sh` as NEW (Phase 1+). The plan adds none; WP-4 only *unifies the existing CLI*. ✔
- **Does not let community-plus replace community stack.** WP-2's append-only dispatcher + WP-1 byte-identity enforce Decision 3. ✔ (Guard made explicit in §4.5.)
- **Does not touch the evidence/governance model** (Decision 4, §3 Layers 1–2). Deferred to Phase 1+. ✔
- **Does not need the `adopt` migration path** (§4, §7). `adopt` is a Phase 1+ command; the plan's WP-5 resolver is precisely what later makes `adopt` (default→community-plus, no reinstall) implementable. ✔
- **Relitigates nothing locked.** No change to the four decisions, the two-profile structure, the profile boundary (§4), the module layout (§5), the build order (§6), the migration story (§7), or the compliance-language discipline (§8). The plan's only "decisions" (WP-0: which CLI, which engine-of-truth, which path semantics) are *implementation* choices the LOCKED doc leaves open — and they match what `ROADMAP.md` already names. ✔

---

## 4. Precise alignment tightenings (pin the spec's exact wording)

Small, surgical additions to the plan so the implementation lands on the locked shape. None changes the plan's structure or effort materially; each just removes ambiguity.

### 4.1 Decision 1 — implement the exact three-tier resolution order (WP-5)
The spec prints the order; the implementation must match it, not a token. WP-5's `resolve_feature_handler "<feature>"` must resolve, in order:
1. `profiles.d/${ACTOOLS_PROFILE}/commands/${feature}.sh` (active-profile override)
2. `modules/${profile_module}/${feature}.sh` (when the active profile lists that module)
3. `cli/commands/${feature}.sh` (or the existing gate stub)

Returning empty for `community` (baseline) is already the right default and must be preserved so community behavior is unchanged.

### 4.2 Reconcile the `resolve_profile_check` name (WP-5)
LOCKED §6 item 1 and Decision 1 name a single generic `resolve_profile_check "preflight" "$check_id"`. The repo implemented it as two functions (`resolve_preflight_check`, `resolve_doctor_check`). To stay faithful to the locked API, WP-5 should add `resolve_profile_check <surface> <check_id>` as the locked-named entry that delegates to the per-surface logic (keeping the existing two as internals). This honors the spec name without re-opening the design.

### 4.3 Decision 2 — use the accessors that already exist (WP-5)
`init.sh` must (a) source `profile.sh`; (b) **validate the `.profile` file exists** and fail immediately if not (LOCKED Decision 2 wording — closes the `--profile community-plus` latent break, since `community-plus.profile` legitimately does not exist until Phase 1); (c) enforce `PROFILE_REQUIRES_ACTOR` / `PROFILE_REQUIRES_CHANGE_TICKET` via `profile_requires_actor` / `profile_requires_change_ticket`; (d) consume `PROFILE_INIT_FIELDS` via `profile_init_fields`. All four accessors already exist — WP-5 is wiring, not authoring.

### 4.4 LOCKED §10 Risk 2 — keep the resolver-bypass CI guard (WP-6)
The spec says CI *may* add a static check that **no source path starts with `${INSTALL_DIR}/modules/plus_` outside the resolver**. The repo already ships a "sibling-scope grep guard" in `test_d0_dispatch.bats`. WP-6 should preserve and extend it so resolver bypass can't creep in during Phases 1–6.

### 4.5 Decision 3 + LOCKED §10 Risk 1 — append-only stage guard (WP-2/WP-6)
Add an explicit test asserting (a) community `PROFILE_INSTALL_STAGES` remains exactly `(host stack db drupal worker)`, and (b) no profile defines a `plus_stack` (or any stage) that *replaces* a community stage rather than appending. This encodes Decision 3 and the §10 Risk-1 "feature creep across the profile boundary" check as CI, not convention.

---

## 5. Where the plan legitimately exceeds the literal §6 list (and why that's allowed)

These items are not numbered in §6, but the LOCKED doc itself requires or implies them, so they are in-scope seam-readiness — not scope creep:

| Plan item | Why it's locked-compatible (and often locked-required) |
|---|---|
| **Golden-file net** (WP-1) | The only way to satisfy "community installs see ZERO behaviour change" (Decision 3, `dispatch.sh:19-20`) *provably*. §11 trigger #1 requires green CI; byte-identity is what makes that meaningful. |
| **CLI unification** (WP-4) | Decision 1 routes `doctor --deep` through dispatch and §5 says `cli/actools` "gains a community-plus section" — both assume **one** CLI. Two divergent CLIs make the resolver seam unreliable. `ROADMAP.md:105-120` already commits to this collapse. |
| **Orphan deletion** (WP-8) | The canonical-modular acceptance set (one home per concern) the plan and reports define; deferred to last, on proof, to avoid DR/CI breakage. |
| **Doc reconciliation** (WP-7) | §9 commits to "all design canon published" and docs "written for operators"; the false `architecture.md`/`cli/actools` claims contradict the shipped system and must be corrected before the gate flips. |
| **Design-canon home** (WP-0) | This *is* §11 build-trigger condition #2 verbatim. |
| **`actools.sh` in shellcheck** (WP-1) | §11 trigger #1 requires green CI on the live authority; today the largest live file is excluded. |

---

## 6. Net + next step

The implementation plan and the LOCKED spec are **consistent end-to-end**: the plan is the execution path the locked doc's §11 "build trigger" is waiting on, it satisfies all nine §6 items plus both trigger conditions, and it honors the four §2 decisions while building none of the Phases 1–6 modules. Folding in the five tightenings in Section 4 makes the implemented API land exactly on the locked shape.

If useful, I can now merge these tightenings directly into `actools-phase0-implementation-plan.md` (so the plan and this alignment are a single document), or expand **WP-5** into a concrete, file-by-file checklist that implements Decision 1's three-tier resolver and the four profile-aware surfaces against the exact line numbers in the repo.

---

*Cross-walked against `Actools_Drupal_Community_Plus_LOCKED.md` (§2 Decisions 1–4, §4 Profile Boundary, §5 Module Structure, §6 Build Order, §7 Migration, §10 Risk register, §11 Code Jail / Build trigger) and `actools-phase0-implementation-plan.md` (WP-0 … WP-8). The locked design is fixed input and is not re-opened.*
