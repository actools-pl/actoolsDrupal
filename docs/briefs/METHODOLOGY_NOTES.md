# METHODOLOGY_NOTES.md — Actools Drupal Community-Plus Arc

**Project:** actoolsDrupal — community-only Drupal 11 install platform with community-plus profile extensions
**Arc origin:** D.0 — Community Seam Hardening (resolver dispatch foundation)
**Document character:** Continuous process. Methodology entries accrete by observation, not by template. Empty sections are honest; they fill as phases close.

---

## The partnership

Three members, locked, permanent regardless of future contributor scale:

- **Orchestrator** — names scope, locks briefs, makes strategic decisions, routes external review consolidated reports to Sir Opus
- **Sir Opus** — brief author, reviewer gate, empirical PoC verifier; verdicts to Sonnet only through orchestrator
- **Sonnet** — implementer; works in own window with locked brief as handoff package; the best engineer this partnership knows

The orchestrator may rotate external review instances (typically ChatGPT for Roles A/B/C, Gemini for Role D when prompted properly). External rotations are capacity-protection work; the founding three never expand.

---

## The methodology orbit

The discipline framework travels from WPGovern. The lessons themselves are observation-earned within this arc. WPGovern's `METHODOLOGY_NOTES.md` (and Sonnet's `CODING_AGENT_REFERENCE.md`) are reference context — useful, not authoritative for this project's claims.

Specific lessons formalize in this document only after observation within the Drupal arc. The held-candidate model travels: single observation → hold; second observation across distinct phases → eligible for formalization.

---

## Lessons (Drupal arc)

*Empty at D.0 start. Lessons accrete by observation as phases close.*

The first candidates to watch (potentially observable in D.0):

- **Universal lessons that almost certainly travel from WPGovern:**
  - Integration tests at every wiring layer (WPGovern Lesson 1)
  - Same-window vs fresh-window external review (WPGovern Lesson 3)
  - Brief authorship ceremony non-negotiable (WPGovern Lesson 4)
  - Settled decisions don't get relitigated (WPGovern Lesson 6)
  - Glob patterns must filter sidecar files (WPGovern Lesson 7)
  - Perimeter discipline — calibration earned through demonstrated work (WPGovern Lesson 8)
  - Pattern-match assumption / discipline-travel between sibling modules (WPGovern Lesson 2 eighth refinement)
  - Doctrine-vs-implementation audit (WPGovern Lesson 11)
  - Four-role layered review architecture for fresh-surface phases (WPGovern Lesson 9 second refinement)

These will register as Drupal-arc lessons after their first observation in this project's surfaces.

---

## Held candidates (single observation; awaiting second to formalize)

| Candidate | Origin | What it claims | Observation site to watch |
|---|---|---|---|
| Internal-verification-scope-must-enumerate-sibling-files | WPGovern H.6.2 + H.7 latent fix | When a brief names files for a fix, the brief author must also enumerate sibling files that share the defect class, not rely on review to surface them | D.0's sibling-scope meta-test; D.0 verification round |
| Sonnet's bonus-discipline within scope | WPGovern H.6.1 / H.6.2 / H.7 / H.7.1 — four data points | Sonnet contributes structural improvements within scope that compound methodology (test consolidation, contract-level checks, byte-preserving patterns); structurally different from orchestrator's or reviewers' contributions because it's about the implementer's role | D.0 implementation round; closure recognition |

---

## Refinements (Drupal arc)

*Empty at D.0 start. Refinements register when an existing lesson develops a more precise edge case worth naming.*

---

## Closed phases

*Empty at D.0 start.*

When a phase closes:
- Phase ID + closure type (internal verdict / external review)
- Methodology candidates observed
- Methodology refinements registered
- Cross-references to relevant artifacts (briefs, review reports, PoC results)

---

## Active phase

**D.0 — Community Seam Hardening (Resolver Dispatch Foundation)**

Status: Brief LOCKED. Implementation pending. See `docs/briefs/d0_phase_brief.md`.

---

## Cross-project references

| Project | Methodology document | Status |
|---|---|---|
| WPGovern | `wpgovern/METHODOLOGY_NOTES.md` | 11 lessons + 8 refinements + 8 milestones at v1 close. Source for the discipline framework. |
| Drupal (this) | `docs/briefs/METHODOLOGY_NOTES.md` (this file) | Empty at D.0 start; accretes by observation. |
| Sonnet's coding agent reference | `CODING_AGENT_REFERENCE.md` (from WPGovern, applicable here) | First-person-from-inside implementer methodology — referenced by name from the D.0 brief; assumed internalized by Sonnet. |

---

## Operating principles (carried from the partnership)

- **No exit options.** Never selling, never flipping, perpetual maintenance posture.
- **Operational features only.** Feature requests are filtered to "what is required and what makes the system better in operation"; aspirational requests are politely declined or ignored.
- **Quarterly informational cadence externally.** Public posture is informational, not solicitous. Maybe one informative post on a new feature every three to four months. The work speaks for itself.
- **Community-only platform; content products monetize separately.** Drupal-pure positioning. No cross-references to other governance projects in this arc's design canon.

---

*Document accretes from D.0 onward. Last update: D.0 brief lock.*
