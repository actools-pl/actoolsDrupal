# Actools Drupal Community — Community-Plus Profile — LOCKED

> **Status:** LOCKED, May 2026
>
> Synthesised from the Council brainstorm (Gemini + ChatGPT) with cross-review, then aligned with the community-only strategic posture.
> Decisions captured here are settled. Implementation proceeds from this document.

---

## 1. The Locked Definition

> *The community-plus profile is an optional richer profile within Actools Drupal Community that adds hardening stages, deep-mode implementations, evidence generation, and governance gates — designed for schools, universities, and regulated organisations whose operational needs extend beyond a default install.*

Both the default `community` profile and the `community-plus` profile ship under MIT license in the same repository (`actools-pl/actoolsDrupal`). Both are developed in the open. Both accept community contributions. Neither carries a price tag, an upgrade URL, or telemetry.

Every feature in the community-plus profile must serve this definition. If a feature does not produce evidence, harden a control, or enforce governance — it does not belong in the profile.

---

## 2. Architecture — Locked

### Four decisions that cannot be reversed.

#### Decision 1 — A Resolver Layer drives profile-specific handlers

This is the most critical pre-implementation work. Currently, deep-mode handlers are sourced as fixed paths:

````bash
source "${INSTALL_DIR}/cli/commands/doctor_deep.sh"
````

That makes profile-aware substitution impossible without conditional logic in community code. The repo must add a resolver:

````bash
resolve_feature_handler "doctor_deep"
resolve_install_stage "host_hardening"
resolve_profile_check "preflight" "$check_id"
````

**Resolution order:**

1. Active profile override: `profiles.d/${ACTOOLS_PROFILE}/commands/${feature}.sh`
2. Profile-extension modules: `modules/${profile_module}/${feature}.sh` (when the active profile lists it)
3. Default handler: `cli/commands/${feature}.sh` or the existing gate stub

This pattern keeps the codebase clean. The default `community` profile resolves to existing community handlers; the `community-plus` profile resolves to community-plus handlers; default behaviour stays exactly as it is for users who never touch profile selection.

#### Decision 2 — First-class `--profile` on the staged journey

The current `ACTOOLS_PROFILE` environment-variable approach is too fragile for serious operator use. Workflow must be:

````bash
sudo ./actools.sh init \
  --profile community-plus \
  --domain example.com \
  --email admin@example.com \
  --site-name "Example" \
  --actor-id mp.singh \
  --change-ticket CHG-2026-001
````

`init` must:
- Accept `--profile` as a first-class argument
- Validate the profile exists (fail immediately if not)
- Persist `ACTOOLS_PROFILE=community-plus` into `actools.env`
- Enforce `PROFILE_REQUIRES_ACTOR` and `PROFILE_REQUIRES_CHANGE_TICKET` based on the chosen profile
- Consume `PROFILE_INIT_FIELDS` for profile-specific additional inputs

After `init`, the profile is "pinned" for the lifecycle of that deployment. Default if `--profile` is omitted: `community`.

#### Decision 3 — Stack hardening is APPENDED, not replaced

The community baseline `PROFILE_INSTALL_STAGES=(host stack db drupal worker)` stays exactly as it is. The community-plus profile appends additional stages:

````
PROFILE_INSTALL_STAGES=(host stack db drupal worker plus_hardening plus_guardian plus_evidence)
````

The community-plus profile MUST NOT define an alternative `plus_stack` that replaces community `stack`. Stages run sequentially; community stages run unchanged; community-plus stages add hardening, scanners, governance, and evidence layers on top.

This protects the default operator experience. Anyone running `--profile community` (the default) gets exactly the same installer behaviour they get today.

#### Decision 4 — Evidence is the differentiator

The community-plus profile's value comes from **producing evidence that auditors can ingest**, not from running scanners. Every community-plus feature must answer: *what evidence does this produce?*

- A scanner that reports findings → low value
- A scanner whose findings are recorded in a signed, hash-chained, timestamped evidence bundle that maps to a named control → high value

This shapes the priority ordering (Section 6) and the profile boundary (Section 4).

---

## 3. The Two Profiles

### `community` (default)

For everyday operators: individual developers, small sites, hobby deployments, small businesses, schools running a single Drupal site without compliance reporting requirements.

Provides exactly what Actools Drupal Community provides today: the five-stage staged journey, the daily-operations CLI (`doctor`, `audit`, `backup`, `update`, `restore`, `restore-test`, `handoff`), and the optional advanced features documented in `docs/advanced.md`.

This profile is the default. No flag needed. Behaviour today and behaviour after the seam-hardening work should be identical for users on this profile.

### `community-plus`

For institutional operators: schools, universities, government departments, healthcare organisations, regulated workplaces — anyone whose operations need to produce evidence, enforce policy, or attribute changes.

**Adds beyond default community (in two layers):**

#### Layer 1 — Deterministic checks and evidence model

| Capability | What it does | Evidence produced |
|---|---|---|
| Active `audit --deep` | Configuration drift, permission drift, risky-module check, TLS posture, backup/restore evidence | JSON audit report with severity codes |
| Active `doctor --deep` | 30-day trend regression, config drift vs install baseline, capacity forecasting, slow-log anomaly detection | Operational health snapshot |
| Hardening stages | Kernel baseline, firewall posture, SSH hardening, filesystem permissions, Docker runtime hardening | Hardening report against named baseline |
| Filesystem integrity | Hash-chained permission/ownership snapshot | Drift report with before/after |
| Backup evidence | Verified backup + restore-test records | Signed evidence bundle |
| External scanners | SSLyze, Nmap, Drupal Security Review | Scanner output + interpretation |
| Audit log integrity | Hash-chained local audit log | Verifiable log with integrity check |

#### Layer 2 — Governance gates (require operator opt-in via `community-plus` profile init flags)

| Capability | What it does | Evidence produced |
|---|---|---|
| Actor identity required | `--actor-id` enforced on all sensitive commands | Every audit entry attributes the operator |
| Change ticket required | `--change-ticket` enforced; ticket recorded with operation | Linkage between operation and change-management system |
| Approval gates | Operations requiring `--approved-by` signed token | Independent approval record per sensitive operation |
| Off-site append-only audit mirror | Audit log mirrored to immutable remote store | Forensic evidence survives local compromise |
| RBAC policy reporting | Periodic snapshot of who-has-what role and why | Access-control evidence |
| Exception register | Track accepted risks with expiry and approver | Risk-acceptance documentation |
| Break-glass workflow | Emergency-access pathway with mandatory after-action report | Incident documentation |
| Compliance mappings | Evidence cross-referenced to SOC 2 / ISO 27001 / GDPR / HIPAA control families | Audit-ready evidence packages |
| Periodic scheduled deep scans | Automated `audit --deep` on cadence with delta reporting | Trend evidence over time |

**Approval gates apply to:**
- `actools update` — production code/config change
- `actools restore` — data-state change
- `actools migrate --apply` — schema change
- `actools gdpr delete` — irreversible privacy action
- `actools hardening-sync` — security posture change

Layer 1 is enabled automatically when the profile is selected. Layer 2 features activate when the operator opts in via init flags (`--actor-id`, `--change-ticket`, `--approver-key`, etc.).

---

## 4. Profile Boundary

The default `community` profile commands and the `community-plus` additions are organised by intent.

### Default `community` profile owns

````
actools doctor                    # daily operational health
actools audit                     # baseline audit, ci mode, json mode
actools status                    # container status
actools logs                      # log streaming
actools backup                    # run backup
actools update                    # pull + drush updb + caddy reload
actools restore                   # restore from backup
actools restore-test              # verify backup integrity
actools handoff                   # post-install summary
````

The default profile may warn, guide, and repair common operational issues. It does NOT do active security scanning, drift detection, evidence generation, or governance enforcement.

### `community-plus` profile adds

````
actools doctor --deep             # deep operational analysis with evidence
actools audit --deep              # active security audit with evidence
actools baseline-create           # establish hardening baseline
actools evidence                  # generate evidence bundle
actools verify                    # verify hash-chain integrity
actools compliance                # produce compliance-mapped report
actools policy                    # show enforced policy state
actools approve                   # generate approval token (Layer 2)
actools hardening-sync            # apply hardening plan
actools adopt                     # switch from default to community-plus on existing install
````

### The boundary discipline

If a feature is **operational** (is the site up, did the backup run, did the cron complete) → default community profile.

If a feature is **evidentiary** (prove the backup ran with integrity, prove the config matches policy, prove no drift since baseline) → community-plus profile.

When a feature could plausibly go either way, prefer routing it to community-plus — even as a "Lite" form. This prevents default-profile feature-creep, which would otherwise erode the value of the community-plus profile and make the codebase harder to maintain.

---

## 5. Module Structure — Locked

All additions live in the existing `actools-pl/actoolsDrupal` repository. No separate downstream repo.

````
actools-pl/actoolsDrupal/
├── profiles/
│   ├── community.profile             # existing (default)
│   └── community-plus.profile        # NEW
├── installer/                        # existing scripts get profile-aware patches
│   ├── init.sh                       # PATCHED — first-class --profile, PROFILE_INIT_FIELDS dispatch
│   ├── preflight.sh                  # PATCHED — PROFILE_PREFLIGHT_EXTRA dispatch
│   └── output.sh                     # existing
├── modules/                          # existing modules unchanged
│   ├── audit/                        # existing
│   ├── backup/                       # existing
│   ├── stack/                        # existing
│   ├── ...                           # other existing modules
│   ├── plus_hardening/               # NEW (community-plus)
│   │   ├── kernel.sh
│   │   ├── firewall.sh
│   │   ├── ssh.sh
│   │   ├── filesystem.sh
│   │   └── docker_runtime.sh
│   ├── plus_scanner/                 # NEW
│   │   ├── nmap.sh
│   │   ├── sslyze.sh
│   │   ├── drupal_security_review.sh
│   │   ├── owasp_zap.sh              # Phase 3 — see Section 6
│   │   └── scheduler.sh              # Layer 2
│   ├── plus_governance/              # NEW
│   │   ├── actor.sh
│   │   ├── change_ticket.sh
│   │   ├── approval.sh               # Layer 2
│   │   ├── rbac.sh
│   │   ├── policy.sh
│   │   └── exception_register.sh     # Layer 2
│   ├── plus_audit_guardian/          # NEW
│   │   ├── append_only_log.sh
│   │   ├── hash_chain.sh
│   │   ├── evidence_bundle.sh
│   │   ├── verifier.sh
│   │   └── offsite_mirror.sh         # Layer 2
│   ├── plus_compliance/              # NEW
│   │   ├── soc2_evidence.sh
│   │   ├── iso27001_evidence.sh
│   │   ├── gdpr_operational.sh
│   │   └── hipaa_readiness.sh        # Phase 3
│   └── plus_doctor_deep/             # NEW
│       ├── trend_regression.sh
│       ├── config_drift.sh
│       ├── cert_forecast.sh
│       ├── backup_forecast.sh
│       └── slowlog_anomaly.sh
├── cli/
│   ├── actools                       # existing; help text gains community-plus section
│   └── commands/
│       ├── doctor.sh                 # existing; --deep now resolves via dispatch
│       ├── doctor_deep.sh            # existing gate stub; resolved by community-plus profile
│       ├── audit_deep.sh             # NEW gate stub for parity
│       ├── baseline.sh               # NEW
│       ├── evidence.sh               # NEW
│       ├── verify.sh                 # NEW
│       ├── compliance.sh             # NEW
│       ├── policy.sh                 # NEW
│       ├── approve.sh                # NEW (Layer 2)
│       ├── hardening_sync.sh         # NEW
│       └── adopt.sh                  # NEW
└── docs/
    ├── advanced.md                   # existing; gains community-plus section
    ├── community-plus-profile.md     # NEW — what the profile is, who it's for
    ├── governance-contract.md        # NEW — Layer 2 details
    ├── evidence-model.md             # NEW — hash chains, bundles, verification
    └── compliance-mapping.md         # NEW — control-family mappings
````

The `plus_` prefix on community-plus modules makes the profile boundary visible at the filesystem level. Anyone browsing the repo can tell which modules ship under which profile.

---

## 6. Build Order — Locked

The order is non-negotiable. Skipping ahead invites architectural debt.

### Phase 0 — Seam Hardening (foundational)

**Must complete before any community-plus feature module is written.** All changes are in the community installer surfaces (`installer/`, `cli/`, existing `modules/`).

1. Resolver layer — `resolve_feature_handler`, `resolve_install_stage`, `resolve_profile_check`
2. First-class `--profile` flag on `actools.sh init`, persisted to `actools.env`
3. Profile-aware `init` — consume `PROFILE_INIT_FIELDS`, enforce `PROFILE_REQUIRES_ACTOR` and `PROFILE_REQUIRES_CHANGE_TICKET`
4. Profile-aware `preflight` — run profile extras through dispatch; unknown check IDs fail for non-default profiles
5. Install-stage dispatcher — iterate `PROFILE_INSTALL_STAGES` through `run_install_stage`
6. Profile-aware `doctor` — consume `PROFILE_DOCTOR_EXTRA`
7. Profile-aware `handoff` — consume `PROFILE_HANDOFF_SECTIONS`
8. Bats tests for the seam — default profile still works; unknown profile fails cleanly; fake test-profile in fixtures exercises every dispatch point
9. E2E test exercises both default profile and a stub test profile

This work produces no new user-visible features. It makes the community-plus profile *possible* without conditionals in community code.

### Phase 1 — Evidence Model (community-plus Layer 1)

10. Hash-chained local audit log
11. Actor identity capture and recording
12. Change-ticket capture and recording
13. Evidence bundle export format (signed JSON + manifest + verifier)
14. `actools verify` — verify integrity of existing evidence bundle

### Phase 2 — Deterministic Deep Checks (community-plus Layer 1)

15. Configuration drift vs install baseline
16. Filesystem permission/ownership drift
17. Enabled risky Drupal modules check
18. TLS posture (cert lifetime, cipher suite, redirect chain)
19. Backup integrity evidence (record of restore-test pass/fail)
20. RBAC snapshot
21. Container/image drift

### Phase 3 — External Scanners (community-plus Layer 1)

22. SSLyze integration (passive)
23. Nmap external surface scan (passive)
24. Drupal Security Review integration (Drupal module bridge)
25. OWASP ZAP integration (active, opt-in, requires explicit operator consent)

### Phase 4 — Compliance Reports (community-plus Layer 1)

26. SOC 2 evidence mapping (CC6 Access Control, CC7 Monitoring, CC8 Change Management)
27. ISO 27001 control-family mapping
28. GDPR operational evidence (extends existing GDPR module)
29. PDF + JSON report formats for institutional ingestion

### Phase 5 — Governance Gates (community-plus Layer 2)

30. Approval-gated operations (`--approved-by` token model)
31. Off-site append-only audit mirror
32. Exception register
33. Break-glass workflow with after-action requirement
34. Scheduled periodic deep scans (with delta reporting)

### Phase 6 — Advanced Backup Immutability (community-plus Layer 2)

35. Object-lock backed offsite vault (S3 Object Lock, B2 file lock equivalents)
36. Separate credential set for backup destruction (different actor identity required)
37. Retention policy enforcement
38. Tamper-detection on backup metadata

---

## 7. Migration Story — Locked

### From default profile to community-plus, no reinstall

The profile switch is a software change, not a reinstall. The flow:

````bash
# Step 1 — Preflight the upgrade (dry-run, no changes)
actools adopt --preflight --target-profile community-plus

# Step 2 — Adopt: install community-plus modules alongside existing community modules
actools adopt --target-profile community-plus \
  --actor-id mp.singh

# Step 3 — Create signed baseline of current state
actools baseline-create

# Step 4 — Run first deep audit (will likely find drift)
actools audit --deep

# Step 5 — Plan hardening (dry-run shows what would change)
actools hardening-sync --dry-run

# Step 6 — Apply hardening with operator awareness of restart impact
actools hardening-sync --change-ticket CHG-2026-001

# Step 7 — Initial evidence bundle
actools evidence --init
````

### What is preserved through profile switch

- Drupal database and content — untouched
- Drupal `sites/default/files` — untouched
- Active configuration — captured in baseline, then optionally adjusted by hardening
- Backups — preserved; new backup retention policy applied going forward
- Users and roles — preserved; RBAC snapshot taken for evidence
- TLS certificates — preserved unless TLS hardening detects weak ciphers

### Downtime expectations

The adoption itself, baseline creation, and first audit: zero downtime.

Hardening application: some operations require Caddy reload, Docker runtime change, or container restart. The dry-run plan shows exactly which operations require restart and the expected duration.

Operator messaging: *"No reinstall. No database destruction. Hardening changes that require restart are shown in the plan before execution."*

---

## 8. Positioning Narrative

The community-plus profile is **not** a sales pitch and is **not** a paid tier. It is a recognition that some operators need additional capabilities that don't belong in a default install — but those operators are still community users.

### Why an operator chooses community-plus

Three operational risks the profile addresses:

| Risk | Default-profile answer | Community-plus answer |
|---|---|---|
| **Unknown drift** | "We trust the install script." | Signed baseline + continuous drift detection + drift report on every audit |
| **Weak evidence** | "We have logs somewhere." | Hash-chained audit log + signed evidence bundles + compliance-mapped exports |
| **Unaccountable operations** | "Someone ran the deploy." | Actor identity + change ticket + approval gate + operation history with cryptographic linkage |

### Compliance language — disciplined

Across all documentation, public communication, and in-product output:

**Always say:**
- "Evidence aligned to SOC 2 control families"
- "Operational outputs that map to ISO 27001 controls"
- "GDPR operational evidence"
- "Audit-ready reports"

**Never say:**
- "SOC 2 compliant"
- "ISO 27001 certified"
- "HIPAA compliant"
- "FedRAMP authorised"

Software does not provide certification. Audit firms do, after observing operating practice over time. The community-plus profile provides the evidence those audits need — that's the honest and defensible claim.

---

## 9. Drupal Community Alignment

Both profiles ship under MIT license in the same community repository. Both are developed in the open. Both accept community contributions.

The project commits to:

- **Single license (MIT) for all profiles, forever.** No tier moves to a different license. No "open core" / "available source" hybrid.
- **Public roadmap.** Issues, milestones, and design documents visible in the repo. No private backlog.
- **All design canon published.** This LOCKED doc, the master architecture, the brief, and future synthesis docs all live in `docs/` or a parallel design repo.
- **Pull requests welcome on both profiles.** No "core team" vs "community contributor" distinction.
- **No telemetry.** No phone-home. No usage tracking. No analytics call-outs.
- **The operator owns their installation completely.** All data, all logs, all evidence stays on the operator's infrastructure.
- **Documentation written for operators, not buyers.** No upgrade prompts, no pricing, no upsell language anywhere in the project.

This posture is what earns Drupal-community trust over time. Adoption follows trust. Trust follows alignment with community values.

---

## 10. The Risks — Documented Permanently

### Risk 1 — Feature creep across the profile boundary

The default `community` profile must not absorb community-plus features. Every operator request for a feature that sits ambiguously between operational and evidentiary should route to community-plus, even as a Lite version. Without that discipline, the boundary erodes within a release cycle, the codebase complexity rises, and the community-plus profile loses its reason to exist as a distinct shape.

**Safety check:** Every PR that adds to the default profile must answer "is this operational or evidentiary?" If the answer is "evidentiary" or "ambiguous", reroute to community-plus.

### Risk 2 — Resolver bypass during implementation

Once the resolver layer exists, every new feature must use it. If anyone proposes "we can hardcode this one path just this once" — the boundary collapses. Code review must catch resolver bypass; CI may add a static check that no source path starts with `${INSTALL_DIR}/modules/plus_` outside the resolver.

---

## 11. Status — Code Jail

> *The community-plus profile is DESIGNED. It is NOT being built.*
>
> *Phase 0 (seam hardening) must complete with merged PRs and green CI before any community-plus module is written. This document is the complete specification through Phase 6. When the time comes, execution begins from this document. No redesign. No rethinking. Just build.*

### Lock status

| Item | Status |
|---|---|
| Definition | LOCKED |
| Architecture (4 decisions) | LOCKED |
| Two-profile structure | LOCKED |
| Profile boundary | LOCKED |
| Module structure | LOCKED |
| Build order (Phases 0–6) | LOCKED |
| Migration story | LOCKED |
| Positioning narrative | LOCKED |
| Compliance language discipline | LOCKED |
| Drupal community alignment commitments | LOCKED |
| Risk register | LOCKED |
| Code | DO NOT TOUCH |

### Build trigger

Two internal conditions, both must be true before community-plus implementation begins:

1. **Phase 0 PRs merged.** Resolver layer, install-stage dispatcher, profile-aware staged journey, `--profile` first-class flag, profile-extra dispatch — all in `main` with green CI and an e2e run that includes a fake downstream profile in test fixtures.
2. **A design canon home exists.** Either a `design/` directory in the existing repo or a separate `actoolsDrupal-design` repo, where this LOCKED, the brief, and the master architecture all live publicly and are referenceable from the issue tracker.

When both are true, Phase 1 (Evidence Model) work begins.

---

*Community-Plus Profile LOCKED — May 2026, synthesised from Council brainstorm (Gemini + ChatGPT) and aligned with community-only strategic posture.*
