# Workflow Package — Production-Readiness Track (C / D / V / E)

*Governing process for the Phase-4.5 production-readiness program. Formalizes the
machinery that carried Phase 0 and P0-K…P0-O, adapted for three windows and for the
loss of cross-model review. Read §0 first — it changed the independence model.*

---

## 0. Independence model (read first — this changed)

Cross-**model** review (coder = Fable, reviewer = Opus) is **no longer available** —
Fable is withdrawn (US-government directive). **All three windows are now separate
Opus sessions.** Consequences, and how we compensate:

- Independence now rests on **session isolation + mechanical verification + the CI
  net**, *not* model diversity. Two Opus sessions share blind spots more than two
  different models would, so the **model-agnostic guardrails become load-bearing**.
- The review and doc-check windows operate **adversarially** — their job is to
  *find the defect* (re-derive, diff, inject guard violations), never to confirm
  the coder. A "looks right to me" pass is worthless when it's the same model.
- **Strict session isolation:** each window receives *only* its bundle (spec /
  handoff / baseline SHA) and the repo — no shared chat history, no leaked context.
- The invariant holds in spirit: **coder ≠ reviewer ≠ doc-checker**, three isolated
  windows, each grounding from its bundle + the baseline SHA alone.
- Honest caveat: this does **not** fully replace cross-model diversity. The
  mechanical net and the operator's own spot-checks carry more weight now than they
  did through K→O. When in doubt, prefer a smaller unit and a real e2e.

## 1. The three windows

| Window | Session | Receives | Emits | Never |
|---|---|---|---|---|
| **Coding** | fresh Opus | spec + baseline SHA + repo | patch/tree + `HANDOFF-<id>.md` + verbatim test transcript | self-approves; touches forbidden files; relies on memory over the repo |
| **Review** | Opus, separate | coder's bundle + baseline SHA + repo | verdict (APPROVE / Needs-revision) + deviation adjudication | trusts a claim it hasn't re-derived |
| **Doc-check** | fresh Opus, ≠ review | the **approved** tree + baseline SHA + repo | `DOCCHECK-<id>.md` (pass / drift-found) | runs before review APPROVEs (code phases) |

## 2. The per-phase cycle

1. **Spec** — the Review Gate authors it, grounded on a named **baseline SHA**:
   objective, allowed/forbidden files, the exact change, the gates, the ledger
   update, the Review-Gate decision criteria.
2. **Code** — coding window implements → `HANDOFF` + verbatim test transcript.
3. **Review** — review window independently re-derives → verdict + adjudication.
4. **Doc-check** — doc window (after APPROVE, for code phases) confirms docs are
   true against the approved code → `DOCCHECK`.
5. **Apply + gate** — operator applies the patch (author-reset, §7), CI goes green,
   a **branch e2e** runs if the phase is behavior-changing, then squash-merge.
6. **Ledger** — the Review Gate records baseline SHA → decision → merge SHA, and
   ratifies the prior entry.
7. The **next phase baselines on the new merge SHA.**

## 3. The handover contract (anti-drift)

Every handover carries a bundle, and the receiving window's **first action is the
pre-flight** — before any work:

- **Baseline lock.** The bundle states the SHA; the window confirms
  `git log --oneline -1` == that SHA. **Mismatch → STOP** and report.
- **Inputs exist and apply.** `git apply --check <patch>` to test applicability
  before `git am` (note: `git am --check` is *not* a valid flag on git 2.43); uploaded
  files present on disk. **Missing/non-applying → STOP** (this is the empty-upload
  and baseline-artifact surprise, prevented).
- **Scope manifest = scope diff.** The spec's allowed/forbidden list must equal the
  baseline→tree diff. Anything outside it is flagged, not waved through.

## 4. The guardrails

**Anti-drift (6):**
1. **One state, addressed by SHA** — every window grounds on the same baseline SHA.
2. **Files are the memory** — spec/handoff/verdict/doccheck are files that travel
   with the work; no window leans on remembered chat.
3. **Independent re-grounding at every gate** — reviewer re-runs tests; doc-checker
   re-checks docs against code. Surprises caught per-gate, not at the end.
4. **Scope manifest = diff** — out-of-scope changes caught mechanically.
5. **CI net is the backstop** — functional/doc drift fails CI regardless of window.
6. **Ledger chains the SHAs** — baseline → decision → merge, auditable; no float.

**Anti-surprise (4):**
1. **Pre-flight input check** (§3) before working.
2. **Branch e2e before merge** for any behavior change — never merge-then-discover.
3. **Known-flake protocol** — an SSH-timeout in the e2e is *infra*; re-run. The
   `Waiting for MariaDB… / MariaDB ready.` window is the real signal.
4. **STOP-before-merge** — no merge until review = APPROVE **and** (if
   behavior-changing) branch e2e green **and** doc-check = pass.

**Compensating for lost cross-model:** adversarial review/doc windows; the
mechanical net is the authority; session isolation strict (§0).

## 5. The CI net (every change passes)

Golden-output **drift 6/6** + **cron fixture 3/3** + structural **guards**
(including the new **doc-claim guard**, D2) + **contract tests** + the
**real-install e2e** (branch dispatch for behavior-changing phases; fast/slow split
so the VM run is merge/nightly, not per-PR). The net is model-agnostic and is the
ultimate arbiter — it catches what three same-model windows might collectively miss.

## 6. Documentation workflow + placement

- **Devbox repo (`/home/actools/actoolsDrupal-src`) — authoritative for *all*
  docs**, operator-facing and internal.
- **GitHub `main`** carries the **end-user / operator-facing docs** (the public
  face) **and** the process record under `docs/runbooks/` (specs, handoffs, ledger
  — *files are the memory*, and a public ledger is a feature).
- **The Claude Project** holds a **copy of the operator-facing docs** + the
  plan-of-record + the current ledger — so all three windows read identical
  reference context. *Keeping the Project copy in sync with the devbox is itself an
  anti-drift control.*
- **Doc-checker standing checklist:**
  - every command in any doc exists in `cli/actools` (the doc-claim guard enforces
    this in CI; the human pass catches phrasing);
  - no doc claims an unshipped feature as live;
  - **no unmeasured performance/time guarantee survives** — e.g. the failover
    "≤5 min" is reworded to *"measured at X; target ≤2X"* or *"not yet measured"*
    (no number is published until a real rehearsal measures it, then 2× it);
  - the Project's operator-facing copy matches the devbox.

## 7. Commit-author rule (`actools-pl` only)

The agent names leaked because `git am` preserves the *patch* author and/or a
`Co-authored-by` trailer rode along. Fix and gate:

```bash
git -C ~/actoolsDrupal-src config user.name  "actools-pl"
git -C ~/actoolsDrupal-src config user.email "feezixmp@gmail.com"

# applying a coder's patch series — the coder authors patches AS actools-pl, so PLAIN
# git am yields the correct author. NOTE: `git am --reset-author` is NOT a valid flag
# (git 2.43 errors "unknown option `reset-author'"); never pass it. Run the author-check
# (below) after applying; if it ever shows a wrong author, force it with
# `git commit --amend --reset-author --no-edit` (single commit — that flag IS valid on
# git commit, just not on git am).
git am /tmp/patches/0*.patch
```

- **GitHub squash-merge:** edit the squash message to **drop any `Co-authored-by:`
  trailers** before confirming.
- **Author-check gate** (part of the merge checklist):
  ```bash
  git -C ~/actoolsDrupal-src log -1 --format='author=%an <%ae>'   # must be actools-pl <feezixmp@gmail.com>
  ```
  A leak is caught on the next commit, not four commits later.

## 8. Phase-artifact templates

**SPEC** — Objective · Baseline SHA · Allowed files · Forbidden scope · Grounding
(verified facts) · Implementation details · Tests (verbatim commands) · Done-means ·
Required handoff · Required ledger update · Review-Gate decision criteria.

**HANDOFF** — Repo state (branch, baseline SHA) · Task completed · **Deviations
(declared explicitly)** · Files changed · Files-not-changed-but-relevant · Test
transcript (verbatim) · Known risks · Exact next allowed task · **Review-Gate notes
(verify in order)**.

**VERDICT** — Per-check result table (scope / byte-identity / guard non-vacuity /
drift / patch-reproduces-tree) · Deviation adjudications (KEEP/revert + why) · jq /
environment caveats · Verdict (APPROVE / Needs-revision) · Apply steps · Squash
message.

**DOCCHECK** — Doc-claim guard result · Per-doc truth check (claim ↔ code) ·
Unmeasured-claim scan · Project-copy-in-sync check · Verdict (pass / drift-found +
the offending lines).

## 9. The work (phase roster)

Per the finalized plan-of-record (`PHASE4.5-READINESS-PLAN-SYNTHESIS.md`), revised
to **full 4.5, everything implemented**, no minimum-line off-ramp:

- **Track C (cleanup):** C1 inventory+guard · C2 delete dead-twin modules · C3
  quarantine 4.5-seed modules · C4 disentangle "Phase" vocabulary.
- **Track D (doc-truth):** D1 reconcile `technical-roadmap.md` · D2 doc-authority +
  doc-claim guard.
- **Track V (verification):** V1 live-verification matrix · V2 real-install command
  harness.
- **Track E (4.5 build):** E1–E20 (backup format → encrypted backups → binlog/PITR →
  update-rollback → MariaDB TLS → scan enforcement → isolation → audit-wrapper →
  RBAC → Cloudflare ACME/Tunnel → zero-inbound → DR snapshot/standby/manual-failover
  → GDPR export/delete). **E18 (automated failover) and Galera → Phase 5.**

Each phase runs the §2 cycle under the §3–§7 controls.

## 10. First actions (before C1)

1. Set the git config (§7).
2. Load the operator-facing doc copies + the plan-of-record + the ledger into the
   Claude Project (§6) so all windows share context.
3. The Review Gate writes the **C1** spec (baseline **`e3c7462`** — the current
   `main` HEAD after the Entry-020 ratification; **not** `9e5cba8`, which is one
   commit behind) → coding window → review → doc-check → merge → ledger Entry 021.
