# experimental/ — quarantined 4.5-design seeds (NOT part of the live product)

The modules here are committed **design seeds for Phase 4.5 features that are
NOT wired, NOT validated, and NOT part of the supported runtime surface.** They
were moved out of `modules/` in Phase C3 (`git mv modules/<name> experimental/<name>`,
content byte-identical, history preserved) so the live set is unambiguous:
`modules/` now holds only the six modules the installer sources — `audit,
backup, db, drupal, host, stack`.

## What "quarantined" means here
This is an **in-place install**: the repo directory *is* the install dir and the
installer `chown -R`'s the whole tree, so these files still reside on the box.
The move removes them from the **live surface**, not the filesystem. The
enforced, machine-checked guarantee is stronger: the orphan-inventory guard
(`tests/guards/orphan_inventory_guard_test.bats`) fails CI if any
`experimental/…` path is ever reached by the live install closure or wired into
`actools.sh` / `installer/` / `cli/`. Nothing here executes on the live path.

## Contents (all unwired design reference)
- `ai/`            — `actools ai …` (Ollama assistant). Not a registered command.
- `compliance/`    — `actools gdpr …`. Not registered; unvalidated.
- `dr/`            — `actools immortalize` / `resurrect`. **Do not run on a live server.**
- `network/`       — Cloudflare tunnel setup doc/templates/service (DNS-01 / origin-cert).
- `observability/` — Prometheus/Grafana stack script (a referenced `alerts.yml` is not present).
- `preview/`       — `actools branch …` ephemeral previews. Not registered.
- `security/`      — audit-wrapper binary + sudoers-roles (RBAC seed).

## Known-stale internals (for whoever wires these later)
Moved verbatim; some carry hardcoded paths the move did NOT update (out of C3
scope — they never execute):
- `dr/resurrect.sh` copies `/home/actools/modules/security/…` (now `experimental/security/…`).
- `dr/immortalize.sh` and `ai/assistant.sh` glob `${INSTALL_DIR}/modules` (no longer
  holds these seeds) and `cli/commands/*.sh` (mostly removed in P0-O).
Fix paths + re-validate before wiring any of these into the live CLI.
