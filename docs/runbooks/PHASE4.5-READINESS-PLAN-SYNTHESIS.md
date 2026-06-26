# Actools Drupal — Production-Readiness Plan to Phase 4.5 (Synthesis & Finalized Plan-of-Record)

*Prepared by the Review Gate. Three independent plans were produced for this
question; they are referred to below as **Plan A, B, and C** without attribution.
This document reconciles them against the **verified** state of the `main` tree
(current HEAD **`e3c7462`**, the Entry-020 ratification) and proposes one finalized,
sequenced plan. Every phase is sized to one reviewable unit, capture/guard-before-
change, reviewable in isolation, and ledger-recorded — the same discipline that
carried Phase 0 and P0-K…P0-O. Window roles and the independence model are governed
by the workflow package, not this document.*

---

## 1. What the three plans agreed on (high confidence)

All three converged on the same spine, which I adopt:

- **Clean and verify *before* building features.** Four layers, in order:
  **(1) cleanup → (2) doc-truth → (3) live-install verification → (4) the 4.5 build.**
  Building enterprise features on unwired orphans and overclaiming docs would
  violate the project's "live code is authoritative" rule.
- **Pay down the existing `ROADMAP.md` wiring debt first** (encrypted backups,
  MariaDB TLS, PITR) — it's partially coded, high-value, and clears the backlog
  before net-new work.
- **PITR before Galera**, and **Galera is not core 4.5** (see §4).
- **Each phase is one net-gated, reviewable unit** with a ledger entry — no
  big-bang rewrites, no fake implementations.

(All three also drew a "minimum production-ready line"; we **reject** that as a
stopping point — see §4.5. The target is the full 4.5.)

Where they differed was granularity (Plan A: 32 fine phases; Plan B: ~10 coarse;
Plan C: four named tracks) and a few sharp calls, adjudicated in §4.

## 2. What I verified against the repo (this corrects the brief's assumptions)

| Claim | Verified result | Consequence |
|---|---|---|
| Orphans ship to production | **True** — in-place install + `chown -R "$REAL_USER" "$INSTALL_DIR"` (`actools.sh:405`) | Layer 1 isn't cosmetic — dead/unwired code is *deployed*. Disposition matters. |
| Orphan module set | **12 of 19**: `ai, compliance, dr, health, migrate, network, observability, preflight, preview, security, storage, worker` (live: `audit, backup, db, drupal, host, stack`) | A precise delete-vs-quarantine list, not "just `modules/ai`." |
| Doc dual-truth (`command-reference` vs `cli-reference`) | **Already resolved** — `cli-reference.md` is a 7-line redirect | Layer 2 is *smaller* than the brief/Plan A & B assumed. |
| Doc-truth state | **Mostly won** — README/ROADMAP/enterprise/command-reference/advanced honest after P0-J | The one keystone overclaim is `technical-roadmap.md`. |
| `technical-roadmap.md` | **Overclaims** — ":7 All Phases 1–4 complete", ":13 32 modules / self-healing / observability / preview / dev assistant" as *shipped* | Reconciling it (without gutting the 5A–5F design) is the central doc task. |

**The headline:** the codebase is in better shape than the brief implied. The real
Layer-1/2 work is (a) disposing of 12 orphan trees that physically deploy, and
(b) reconciling one overclaiming target doc — not a sprawling doc war.

## 3. The finalized plan — four tracks

Track naming follows Plan C (cleanest, and it sidesteps the overloaded "Phase 1"):
**C**leanup, **D**oc-truth, **V**erification, **E**nterprise/4.5.

### Track C — Cleanup (Layer 1)

| ID | Objective | Scope | Risk | Verification | Size |
|---|---|---|---|---|---|
| **C1** | Inventory + pin the live-module set | Add a "Standalone modules" section to `runtime-authority-map.md` classifying all 18 trees (live/dead/planned); new `orphan_inventory_guard` asserting the *sourced* set == the documented live set; per-module grep-proofs in the ledger. **No deletion yet.** | Low | Guard non-vacuous (inject a fake `source modules/ai/…` on the live path → fails); drift 6/6 | M |
| **C2** | Delete dead-twin modules | `git rm` the orphans that duplicate live inline/module logic: `ai, health, preflight, worker, storage, preview`, and the `migrate` *module* (**keep** the separate inline `migrate` CLI text-guide); fix `lint.yml` shellcheck globs + doc pointers. The P0-O pattern at module scope. | Low-Med | Inventory guard stays green; drift 6/6; **real-install e2e green** (deletion transparent); per-module grep empty | M |
| **C3** | Quarantine the 4.5-seed modules | Move `compliance, dr, network, security, observability` + the PITR scripts (`encrypted_backup, deploy-pitr, pitr-restore, cli-pitr, db-full-backup, binlog-rotate`) into an `experimental/` tree the installer does **not** deploy; fix relative paths + cross-links. (Quarantine, **not** delete — these are committed 4.5 design.) | Med | Installer no longer deploys them (e2e + a deploy-set assertion); doc-link check; drift 6/6 | M |
| **C4** | File-level orphan inventory + a file-level wiring guard for the 6 live modules (the dir-level C1 guard only pinned which module dirs are live). | Classify all 35 files (21 wired / 1 doc / 13 unwired); guard fails CI on any unclassified or wiring-flipped file. The original "Phase vocabulary" work was folded into **D1** (the `technical-roadmap.md` canonical glossary). | Low | Guard non-vacuous (flip a wired file to unwired, or leave a live-module file unclassified → fails); drift 6/6 | S |

> *The roster captures the plan as conceived; the authoritative as-executed record — including the `ai`/`preview` reclassification (dead-twin → 4.5-seed) and the C4 repurposing — is `docs/runbooks/PHASE0_LEDGER.md`.*

### Track D — Doc-truth (Layer 2) — *smaller than the brief assumed*

| ID | Objective | Scope | Risk | Verification | Size |
|---|---|---|---|---|---|
| **D1** | Reconcile the keystone doc | `technical-roadmap.md`: stop asserting `v11.0` / "All Phases 1–4 complete" / the 32-module/AI/preview/observability list as *shipped*; re-label planned/experimental — **while preserving the 5A–5F design bodies** (the legitimate target). | Med | Doc-claim guard (below); the doc names nothing unshipped as "complete" | M |
| **D2** | Doc-authority + a doc-claim-vs-CLI guard | Declare the authority per doc; add `command_claim_guard` parsing the real `cli/actools` dispatch + installer modes and failing CI if any doc advertises a command that isn't registered (experimental commands live in an explicit "not registered" table). | Low-Med | Guard non-vacuous (a fake `actools nonexistent` doc claim → fails) | M |

### Track V — Verification (Layer 3)

| ID | Objective | Scope | Risk | Verification | Size |
|---|---|---|---|---|---|
| **V1** | Live-verification matrix | `live-verification-matrix.md`: every live command with precondition, safe/destructive class, expected output + exit, CI/manual status. | Low | Matrix guard: every `cli/actools` command has a row; destructive commands carry a dry-run/staging strategy | S |
| **V2** | Real-install command harness | Extend `e2e.yml` past the doctor/audit smoke to run the **safe** CLI surface on the live VM (`status, logs, doctor, audit, dry-run, storage-info, tls-status, restore-test, backup`…); pull forward the ROADMAP **fast/slow CI split** (VM run on merge/nightly, not per-PR). | Med-High | Hetzner e2e transcript artifact; the doc-claim guard must match observed behavior | L |

### Track E — Phase 4.5 build (Layer 4), on the clean foundation

Sequenced. The target is **full 4.5 — every item implemented and net-gated**, with
no off-ramp; the point after E9 is a non-binding **safe-to-run checkpoint** (the
system is genuinely runnable in production there *while the build continues*), not a
stopping line — see §4.5.

| ID | Objective | Risk | Key gate | Size |
|---|---|---|---|---|
| **E1** | Backup-format contract (restore understands `.sql.gz` + `.sql.gz.age` + checksum/manifest) *before* producing encrypted output | High | Fixtures: plain/encrypted/corrupt/missing-key; restore-test contract; live restore-test green | M |
| **E2** | Encrypted full-backup deployment (wire the quarantined encrypted-backup code as live) | High | Golden cron; no-DB-password-on-argv guard; no plaintext dump left; live e2e backup→encrypted artifact+manifest | M |
| **E3** | Binlog generation + archive net (`ENABLE_PITR`; my.cnf/compose) | High | Intentional golden drift; `docker compose config`; live e2e proves `log_bin=ON`; encrypted binlog archive | M |
| **E4** | PITR dry-run planner (non-destructive) | Med | Fixture timeline (missing binlog / target-before-dump / corrupt); zero DB mutation in tests | M |
| **E5** | PITR destructive restore on **staging** | High | Live e2e: marker rows → backup → later row → restore-to-timestamp → assert rows | L |
| **E6** | `update` self-rollback on failed post-update health | High | Mock-docker contract; staged live e2e injects failing health → proves rollback | M |
| **E7** | MariaDB TLS in transit (per-deployment certs) | High | Intentional golden compose/my.cnf; live e2e verifies SSL vars + Drupal bootstrap; cert-perms guard | L |
| **E8** | Security-scan enforcement (Trivy gate; pinned actions; allowlist+expiry) | Med | CI proves pinned actions + threshold; allowlist file | S |
| **E9** | Container / PHP-FPM isolation (`no-new-privileges`, cap drops, volume review) | High | Live e2e writes files + cache rebuild + worker status; intentional golden drift | L |
| — | **▽ safe-to-run checkpoint** — system safely runnable here; **build continues to full 4.5.** *Not* a stopping point (see §4.5) | — | — | — |
| **E10** | Standard CLI invocation audit-wrapper (`actools → actools-audit → actools-real`) | Med | Installed CLI-authority test updated; live e2e proves wrapper appends audit log | M |
| **E11** | RBAC roles (sudoers; opt-in flag) | High | `visudo -c` guard; fixture sudoers parse; audit-attribution check | M |
| **E12** | Cloudflare Caddy ACME wiring (DNS-01; custom Caddy build, pinned plugin) | Med | Golden Caddyfile/Dockerfile; `caddy validate`; token-not-in-logs guard | M |
| **E13** | Cloudflare Tunnel opt-in install (`cloudflared`; default install unchanged) | Med-High | Mock-systemd tests; optional live e2e when tunnel secret exists | M |
| **E14** | Zero-open-inbound verification (only claim zero-trust after the firewall proves it) | High | Live e2e w/ safety escape; `ufw status` + tunnel-health assertions; rollback printed first | M |
| **E15** | DR snapshot contract (refactor `immortalize`/`resurrect` → verified redacted encrypted manifest) | Med | Schema + redaction tests (no secret/key in snapshot); live e2e generate→decrypt→validate | M |
| **E16** | Standby restore rehearsal (fresh server from backup+manifest) | High | Cloud e2e provisions disposable standby, restores, runs doctor, compares marker | L |
| **E17** | Manual failover command (provider-specific; dry-run/apply; floating IP) | High | Dry-run contract; live failover rehearsal on non-prod domain; rollback tested | L |
| ~~E18~~ | **Automated failover monitor → deferred to Phase 5** (the roadmap's own comment marks automatic failover Phase 5; **manual failover E17 is the 4.5 line**). No failover time is published until measured on a real rehearsal — then stated as **2× the measured value**, never "≤5 min" up front | — | — | — |
| **E19** | GDPR export/report first (non-destructive) | Med | Fixture-user export; no-DB-password-on-argv; audit entry; JSON schema | M |
| **E20** | GDPR delete with safety gates (UID-1 protection; pre-delete export; dry-run) | High | Staging e2e: create→dry-run→export→delete→verify anonymization | M |
| — | **Galera (3-node HA): DEFERRED to a gated HA profile / Phase 5 — not core 4.5** (see §4) | — | — | — |

## 4. Key decisions where the plans diverged (my adjudication)

1. **Galera *and* automated failover are *not* core Phase 4.5 — defer both to Phase 5.** Plan B argued (correctly, and I agree) that moving a single-node MariaDB to a 3-node synchronous Galera cluster is a massive architectural shift that **invalidates the README's single-server promise**; Plans A and C both placed it last and gated behind an explicit HA profile. **Automated failover (E18)** is also Phase 5 — the roadmap's *own* comment marks automatic failover Phase 5, so **manual failover (E17) is the 4.5 line.** **Decision:** both land in **Phase 5 / multi-tenancy**, after PITR is proven. The 4.5 HA story is satisfied by encrypted backups + PITR + manual failover + standby rehearsal (E1–E5, E16–E17), not synchronous clustering or automatic promotion. **Related rule:** no performance/time guarantee (e.g. the failover "≤5 min") is published in any doc until measured on a real rehearsal — then stated conservatively as **2× the measured value**.

2. **Delete vs quarantine the orphans (Plan C's refinement, adopted).** The 12 orphans split: **delete** the dead-twins (duplicates of live logic — `ai, health, preflight, worker, storage, preview, migrate-module`, the P0-O pattern), but **quarantine** the committed 4.5-design seeds (`compliance, dr, network, security, observability` + PITR scripts) into `experimental/` so they stop shipping yet aren't lost. Plan B's "just delete `modules/ai`/`modules/dr`" would have erased real future intent.

3. **Layer 2 is small.** Because doc-truth was mostly won in P0-J and `cli-reference.md` already redirects, Track D collapses to one keystone reconciliation (`technical-roadmap.md`) + the durable doc-claim guard. The brief and Plans A/B over-budgeted this.

4. **Granularity.** I took Plan A's fine decomposition for the **feature track** (where small units genuinely de-risk destructive DB/network work) and Plan C's **four-track framing** for structure. Plan B's coarse phases are good for the executive view but too large to review as single units.

5. **No "minimum production-ready" off-ramp — the target is the full 4.5.** Two of the three plans drew a "minimum line" (after their backup/TLS work) and treated the rest as optional. **We reject that framing.** In practice "minimum/MVP" becomes a permanent way-station: victory is declared at the minimum, the remaining work is forever "planned," and the hardening never lands. The deliverable is **all of Track C/D/V + E1–E20 (less the two Phase-5 deferrals), built for real and net-gated** — not stubbed-and-marked-planned. The point after E9 (encrypted backups + PITR + update-rollback + MariaDB TLS + scan-enforcement + isolation, on a cleaned and verified base) is a **non-binding safe-to-run checkpoint** — genuinely runnable in production there *while the build continues* — but **not** a place to stop.

## 5. Top risks across the program + de-risking

1. **Destructive DB paths (restore, PITR replay, update-rollback, GDPR delete).** → Format/dry-run/contract *before* destructive; staging-only live proofs; confirmation gates; `restore-test` stays green throughout.
2. **Wiring stale quarantined scripts into prod prematurely.** → C3 quarantine + the orphan-inventory guard keep them un-deployed until their E-phase explicitly wires them with coverage.
3. **Network lockout during zero-trust (E12–E14).** → Always print a rollback/escape path before applying; never remove SSH without a proven alternate management path; firewall claims only after `ufw status` proves them.
4. **Backup encryption key loss (E2).** → Installer must emit a loud, blocking acknowledgment that the operator has stored the private key offline before completing.
5. **CI flake/cost from the live harness (V2) and standby rehearsals.** → Fast/slow split (VM runs on merge/nightly, not per-PR); disposable cloud standbys with teardown; transcripts as artifacts.

## 6. Immediate next step

The clean entry point is **C1 — orphan-module inventory + live-set guard** (low-risk,
doc+test only, no deletions). It produces the evidence base and the guard that makes
C2/C3's deletions and quarantines safe — exactly the capture/guard-before-change
order that worked in K→O. On your go, I'll write the C1 bundle (spec + coding-window
prompt + README) against **`e3c7462`** (the current HEAD); window roles run per the
workflow package — three Opus windows, coding → review → doc-check.

> **Open questions to settle before C3/E-track** (flagged by the plans, unresolved
> by the tree): the target Caddy ACME mode (DNS-01 vs origin-cert — both appear in
> `ROADMAP.md`); whether any hardcoded `/home/actools` paths leak into live behavior
> vs. resolve via `INSTALL_DIR`/`ACTOOLS_HOME` (audit `modules/stack/compose.sh`);
> and the audit-wrapper's intended topology (script-replacing-symlink vs alias).
