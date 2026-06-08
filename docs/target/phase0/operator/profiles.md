# Profile Lifecycle and Error Behaviour

> **Status:** Phase 0 target contract — not yet released. This document describes intended
> behavior after Phase 0 seam hardening. It must not be treated as current released behavior
> until Phase 0 closure.

This document describes the profile system as it operates after Phase 0 seam hardening.

---

## What a profile is

A **deployment profile** selects a named set of install stages, preflight checks, doctor
checks, and handoff sections for a deployment. The active profile is pinned to a deployment
at `init` time and written into `actools.env` as `ACTOOLS_PROFILE`.

Profiles are source-only shell files in `profiles/`. They declare arrays and flags; they
contain no executable side effects.

### The community profile (default)

`profiles/community.profile` is the only profile that ships with the community installer.
It is the default — if `--profile` is omitted at `init`, `community` is used.

```bash
PROFILE_NAME="community"
PROFILE_DISPLAY="Actools Drupal Community"

PROFILE_REQUIRES_ACTOR=false
PROFILE_REQUIRES_CHANGE_TICKET=false

PROFILE_INIT_FIELDS=(domain email site-name)
PROFILE_PREFLIGHT_EXTRA=()
PROFILE_INSTALL_STAGES=(host stack db drupal worker)
PROFILE_DOCTOR_EXTRA=()
PROFILE_HANDOFF_SECTIONS=(site admin commands log)
```

For `community`, every resolver returns empty (no override). Community installs see zero
behaviour change from the seam hardening work.

---

## Profile file contract

Profile files must be side-effect-free. The following are **allowed**:

```bash
PROFILE_NAME="community"
PROFILE_DISPLAY="Actools Drupal Community"
PROFILE_REQUIRES_ACTOR=false
PROFILE_REQUIRES_CHANGE_TICKET=false
PROFILE_INIT_FIELDS=(domain email site-name)
PROFILE_PREFLIGHT_EXTRA=()
PROFILE_INSTALL_STAGES=(host stack db drupal worker)
PROFILE_DOCTOR_EXTRA=()
PROFILE_HANDOFF_SECTIONS=(site admin commands log)
```

The following are **forbidden** in a profile file:

- Starting services
- Writing files
- Calling package managers
- Sourcing feature modules directly
- Modifying global state outside the profile variables listed above

Profile files are loaded by `installer/profile.sh`. The loader sources
`profiles/${ACTOOLS_PROFILE}.profile` and exits with code `1` if the file is missing.

---

## Profile lifecycle

### 1. Selection at init

`actools.sh init --profile <name>` selects the profile. If `--profile` is omitted,
`community` is used. `init` validates the profile name against the allowed list in
`installer/dispatch.sh` (`_ACTOOLS_ALLOWED_PROFILES`).

**Phase 0 target (P0-E):** `init` will also validate that the profile file exists
(`profiles/<name>.profile`) before persisting. In the current D.0 state, init validates
list membership only. After P0-E, a missing profile file fails before persistence.

### 2. Persistence

`init` appends `ACTOOLS_PROFILE=<name>` to `actools.env`. This pins the profile for the
lifecycle of the deployment. The profile written is always explicit (never empty).

### 3. Reload on each command

`cli/actools` sources `actools.env` on every invocation and loads `installer/dispatch.sh`.
The `actools::cli::resolve_profile` function resolves the final profile from:
- `--profile` CLI flag (highest precedence)
- `ACTOOLS_PROFILE` in `actools.env`
- Default `community`

A conflict between the CLI flag and the env file value causes a **fail-closed error** (exit
code `2`) — profile selection is deployment-defining and must not change silently via a CLI
typo.

### 4. Profile-aware surfaces

After Phase 0 seam hardening, the following surfaces are profile-aware:

| Surface | Profile arrays consumed |
|---|---|
| `init` | `PROFILE_INIT_FIELDS`, `PROFILE_REQUIRES_ACTOR`, `PROFILE_REQUIRES_CHANGE_TICKET` |
| `preflight` | `PROFILE_PREFLIGHT_EXTRA` |
| Install (stage dispatcher) | `PROFILE_INSTALL_STAGES` |
| `doctor` | `PROFILE_DOCTOR_EXTRA` |
| `handoff` | `PROFILE_HANDOFF_SECTIONS` |

For `community`, all extra arrays are empty and both `REQUIRES_*` flags are `false`, so
each surface behaves identically to today.

---

## Allowed profiles

The dispatcher (`installer/dispatch.sh`) defines the single source of truth for valid
profile names:

```bash
_ACTOOLS_ALLOWED_PROFILES=(community community-plus test)
```

- `community` — the default, open-source installer profile
- `community-plus` — adds hardening, evidence, and governance stages (Phase 1; not yet
  implemented; reserved name)
- `test` — fixture profile used by the bats test suite only; not intended for production

---

## Error behaviour

### Unknown profile at init

```
FAIL  --profile  unknown profile 'foobar'
      Allowed profiles: community community-plus test
```

Exit code `3`. `actools.env` is not written.

### Missing profile file

**Phase 0 target behaviour (P0-E):** If the profile file `profiles/<name>.profile` does
not exist, `init` fails with an explicit error before writing `actools.env`.

```
FAIL  --profile  profile file not found: profiles/foobar.profile
```

**Current (D.0) behaviour:** `init` validates against the allowed list only. The live
profile loader (`installer/profile.sh:21-29`) exits `1` if the file is missing, but this
check occurs during install, not during init. After P0-E, the check moves to init.

### Profile conflict (CLI vs env file)

```
ERROR: --profile='community-plus' conflicts with actools.env (ACTOOLS_PROFILE='community')
       Profile selection is deployment-defining. To change profile:
         1. Edit actools.env directly: ACTOOLS_PROFILE=community-plus
         2. OR remove ACTOOLS_PROFILE from actools.env and re-run with --profile=community-plus
```

Exit code `2`. The operation is aborted. This prevents silent profile switches from CLI
typos on a live deployment.

### Unknown profile at runtime (not in allowed list)

The resolver (`actools::dispatch::resolve_feature_handler`) emits a warning to stderr and
returns empty (fall back to community defaults). This is fail-soft behaviour for the
dispatcher — community operators are never stranded by an unexpected profile value.

---

## Profile isolation guarantee (non-bypass rule)

No Phase 1+ feature may hardcode a path into a community-plus module:

```bash
# FORBIDDEN in community code:
source "${INSTALL_DIR}/modules/plus_hardening/kernel.sh"
```

All feature-specific resolution must pass through the resolver layer. The resolver bypass
bats test (`tests/test_d0_dispatch.bats:226`) enforces this statically — it asserts that
every `ACTOOLS_PROFILE` reader in the codebase either sources `dispatch.sh` or carries a
`DISPATCH_EXEMPT` annotation.

---

## Community-plus status

`community-plus` is a **reserved profile name** with no implementation in Phase 0. Running
`--profile community-plus` selects a named profile that has no resolver handlers yet.
The community-plus build is blocked until Phase 0 closure.

See `docs/architecture/phase0-seam-contract.md` and the LOCKED spec
(`design/Actools_Drupal_Community_Plus_LOCKED.md`) for the community-plus design.

---

## Cross-references

- Seam contract (resolver functions, profile contract):
  [`docs/architecture/phase0-seam-contract.md`](../../architecture/phase0-seam-contract.md)
- Install journey: [`install-community.md`](install-community.md)
- Troubleshooting: [`troubleshooting.md`](troubleshooting.md)
