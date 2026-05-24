# Profile contract

A profile defines what the staged installer journey (`init → preflight →
install → handoff → doctor`) collects, checks, builds, and reports for a
given product variant.

The community installer ships exactly one profile: **`community`**.

Other products that build on this installer pattern — DrupalFortress
Standard and DrupalFortress Institutional, for example — live in
separate repositories and add their own `.profile` files following this
contract. They do not ship here.

## File format

A `.profile` is a sourced shell file. It must set the variables below
and must have no executable side effects.

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

## Field reference

| Variable | Type | What it controls |
|---|---|---|
| `PROFILE_NAME` | string | Internal identifier, lowercase. Used by `installer/profile.sh`. |
| `PROFILE_DISPLAY` | string | Human-readable name shown in titles. |
| `PROFILE_REQUIRES_ACTOR` | bool | If `true`, `init` requires `--actor-id`. |
| `PROFILE_REQUIRES_CHANGE_TICKET` | bool | If `true`, `init` requires `--change-ticket`. |
| `PROFILE_INIT_FIELDS` | array | Required CLI flags during `init`. Names map to `--<name>`. |
| `PROFILE_PREFLIGHT_EXTRA` | array | Extra check IDs the profile adds to base preflight. |
| `PROFILE_INSTALL_STAGES` | array | Module stage groups to run during install. |
| `PROFILE_DOCTOR_EXTRA` | array | Extra check IDs the profile adds to base doctor. |
| `PROFILE_HANDOFF_SECTIONS` | array | Which sections render in the post-install summary. |

## Selection

The active profile is read from `ACTOOLS_PROFILE`. Default: `community`.

```bash
export ACTOOLS_PROFILE=community
```

`installer/profile.sh` loads `profiles/${ACTOOLS_PROFILE}.profile`. If
the file does not exist, the script exits with a message that this
build only ships the `community` profile.

## Inheritance

A downstream profile inherits from `community` by sourcing it and
overriding the arrays:

```bash
# profiles/standard.profile  (lives in the DrupalFortress repo)
source "${INSTALL_DIR}/profiles/community.profile"

PROFILE_NAME="standard"
PROFILE_DISPLAY="DrupalFortress Standard"
PROFILE_PREFLIGHT_EXTRA=(kernel rootless_docker gvisor falco nftables)
PROFILE_INSTALL_STAGES+=(host_hardening rootless_docker gvisor falco guardian)
PROFILE_DOCTOR_EXTRA=(php_runtime falco guardian filesystem_ro)
PROFILE_HANDOFF_SECTIONS+=(security validation)
```

## What this directory must not contain

- `standard.profile` — lives in the DrupalFortress repository
- `institutional.profile` — lives in the DrupalFortress repository
- Any profile that requires non-MIT licensed code paths

This keeps the community installer light and avoids the trap of
shipping hardened-platform features into the community surface.
