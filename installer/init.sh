#!/usr/bin/env bash
# =============================================================================
# installer/init.sh — Guided actools.env creation.
#
# Replaces:  cp actools.env.example actools.env && nano actools.env
# With:      sudo ./actools.sh init --domain X --email Y --site-name "Z"
#
# Rules (Doc 1 §9.2):
#   - Refuse to overwrite an existing actools.env without --force
#   - Validate email format up front
#   - Default --site-name to the domain if not given
#   - Generate nothing (secrets are auto-generated later by core/secrets.sh
#     when install runs and DB_ROOT_PASS / DRUPAL_ADMIN_PASS are blank)
#   - Do not install anything
#   - Print exactly one next command
#
# D.0 additions:
#   - Accept --profile flag; validate against allowed list; write to actools.env
#   - Source installer/dispatch.sh for profile validation
#
# P0-E additions (profile validation, alignment §4.3):
#   - Validate the chosen profile's .profile FILE exists before persisting
#     actools.env (closes the latent --profile community-plus break: that
#     profile is in the allowed list but its file is a Phase-1 product).
#   - Source installer/profile.sh (the canonical loader) for the chosen profile
#     and enforce its governance flags via the existing accessors:
#       PROFILE_REQUIRES_ACTOR        -> requires --actor-id
#       PROFILE_REQUIRES_CHANGE_TICKET -> requires --change-ticket
#   - Consume PROFILE_INIT_FIELDS via profile_init_fields.
#   - Community (REQUIRES_*=false, fields domain/email/site-name) is unchanged.
#   - SCOPE: --actor-id / --change-ticket are VALIDATED but intentionally NOT
#     persisted to actools.env. P0-E is validation scaffolding only; recording
#     governance identity is a community-plus concern (forbidden here, → P0-H).
#
# Required globals (set by actools.sh before sourcing):
#   INSTALL_DIR, ENV_FILE, REAL_USER, REAL_HOME
# =============================================================================

run_init() {
  local domain="" email="" site_name="" force=false profile="" unknown=""
  local actor_id="" change_ticket=""
  # Set after the .profile file is validated (just before sourcing profile.sh).
  # Local so init never leaks profile identity into the caller's environment.
  local ACTOOLS_PROFILE=""

  # Source dispatch.sh for profile validation.
  # DISPATCH_EXEMPT: init creates the env file; dispatch.sh is sourced here
  # for actools::dispatch::profile_is_valid only. ACTOOLS_PROFILE is not set
  # from an env file at this point — validation uses the --profile flag value.
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/dispatch.sh" 2>/dev/null || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)    domain="${2:-}"; shift 2 ;;
      --email)     email="${2:-}"; shift 2 ;;
      --site-name) site_name="${2:-}"; shift 2 ;;
      --profile)   profile="${2:-}"; shift 2 ;;
      --profile=*) profile="${1#*=}"; shift ;;
      --actor-id)        actor_id="${2:-}"; shift 2 ;;
      --actor-id=*)      actor_id="${1#*=}"; shift ;;
      --change-ticket)   change_ticket="${2:-}"; shift 2 ;;
      --change-ticket=*) change_ticket="${1#*=}"; shift ;;
      --force)     force=true; shift ;;
      --help|-h)
        _init_usage
        return 0
        ;;
      *)
        unknown+="$1 "
        shift
        ;;
    esac
  done

  print_title "ACTOOLS INIT"

  if [[ -n "$unknown" ]]; then
    print_warn "flags" "ignored: $unknown"
  fi

  # Profile validation — must be a known profile or empty (defaults to community).
  if [[ -n "$profile" ]] && ! actools::dispatch::profile_is_valid "$profile" 2>/dev/null; then
    print_fail "--profile" "unknown profile '${profile}'"
    echo "  Allowed profiles: ${_ACTOOLS_ALLOWED_PROFILES[*]:-community community-plus test}" >&2
    return 3
  fi
  # Default to community if not specified.
  [[ -z "$profile" ]] && profile="community"

  # P0-E §4.3(b) — validate the profile FILE exists BEFORE persisting actools.env.
  # List membership (above) is necessary but not sufficient: community-plus is an
  # allowed name whose .profile is a Phase-1 product that does not ship here, so
  # `init --profile community-plus` must fail now rather than writing an env file
  # that the next run cannot load. Fail with the same exit code as an unknown
  # profile (3) — both are "this profile cannot be used here" conditions.
  local profile_file="${INSTALL_DIR}/profiles/${profile}.profile"
  if [[ ! -f "$profile_file" ]]; then
    print_fail "--profile" "profile '${profile}' has no profile file"
    print_fix "Expected: ${profile_file}"
    print_fix "This build ships only the 'community' profile; others are separate products."
    return 3
  fi

  # P0-E §4.3(a),(c),(d) — source the canonical loader for the chosen profile and
  # read its governance contract through the existing accessors. The file is known
  # to exist (checked just above), so profile.sh will not exit here. This sets the
  # PROFILE_* contract variables and defines profile_requires_actor /
  # profile_requires_change_ticket / profile_init_fields.
  ACTOOLS_PROFILE="$profile"
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/profile.sh"

  # P0-E §4.3(d) — consume PROFILE_INIT_FIELDS. The base fields domain/email/
  # site-name are validated exactly as before (below). Any field a profile
  # declares beyond those three is an "extra" whose collection/validation is a
  # surface concern wired in P0-H; community declares no extras, so this loop is
  # a no-op for the default profile and changes no community behavior.
  local _extra_fields=() _f
  while IFS= read -r _f; do
    [[ -z "$_f" ]] && continue
    case "$_f" in
      domain|email|site-name) : ;;   # handled by the existing validation below
      *) _extra_fields+=("$_f") ;;   # declared but not yet wired (→ P0-H)
    esac
  done < <(profile_init_fields 2>/dev/null || true)

  # Required-field validation. Funnels missing/invalid base fields AND missing
  # governance flags into a single failure path (exit 1).
  local missing=0
  if [[ -z "$domain" ]]; then
    print_fail "--domain" "required"
    missing=1
  fi
  if [[ -z "$email" ]]; then
    print_fail "--email" "required"
    missing=1
  elif [[ ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    print_fail "--email" "invalid format: $email"
    missing=1
  fi

  # P0-E §4.3(c) — profile-driven governance. Community sets both flags false, so
  # neither check fires for the default profile (behavior preserved). A profile
  # that sets PROFILE_REQUIRES_ACTOR / PROFILE_REQUIRES_CHANGE_TICKET true makes
  # the corresponding flag mandatory. Validated only — NOT persisted (see header).
  if profile_requires_actor && [[ -z "$actor_id" ]]; then
    print_fail "--actor-id" "required by profile '${profile}'"
    missing=1
  fi
  if profile_requires_change_ticket && [[ -z "$change_ticket" ]]; then
    print_fail "--change-ticket" "required by profile '${profile}'"
    missing=1
  fi

  if (( missing )); then
    echo
    _init_usage
    return 1
  fi

  # Default site name to domain
  [[ -z "$site_name" ]] && site_name="$domain"

  # Refuse to clobber an existing config
  if [[ -f "$ENV_FILE" && "$force" != "true" ]]; then
    print_fail "actools.env" "already exists at $ENV_FILE"
    print_fix "Re-run with --force to overwrite, or delete the file first."
    return 1
  fi

  # Sanity check that the template exists
  local template="${INSTALL_DIR}/actools.env.example"
  if [[ ! -f "$template" ]]; then
    print_fail "actools.env.example" "missing from repository"
    print_fix "Re-clone the repository — the template is required."
    return 1
  fi

  # Copy template, patch the three operator-facing fields.
  # SITE_NAME is quoted because it may legitimately contain spaces.
  # BASE_DOMAIN and DRUPAL_ADMIN_EMAIL syntactically cannot contain spaces.
  cp "$template" "$ENV_FILE"
  sed -i \
    -e "s|^BASE_DOMAIN=.*|BASE_DOMAIN=${domain}|" \
    -e "s|^DRUPAL_ADMIN_EMAIL=.*|DRUPAL_ADMIN_EMAIL=${email}|" \
    -e "s|^SITE_NAME=.*|SITE_NAME=\"${site_name}\"|" \
    "$ENV_FILE"

  # Write ACTOOLS_PROFILE to env file — always explicit after init.
  # NOTE (P0-E): --actor-id / --change-ticket were validated above but are
  # intentionally NOT written here — recording governance identity is a
  # community-plus concern deferred to P0-H; P0-E only proves the requirement.
  {
    echo ""
    echo "# -- Profile (set by actools init; do not edit directly) ---------------"
    echo "ACTOOLS_PROFILE=${profile}"
  } >> "$ENV_FILE"

  # Ownership and permissions — env contains secrets after install fills them
  chown "$REAL_USER:$REAL_USER" "$ENV_FILE" 2>/dev/null || true
  chmod 600 "$ENV_FILE"

  print_ok "actools.env" "created"
  print_ok "Domain" "$domain"
  print_ok "Admin email" "$email"
  print_ok "Site name" "$site_name"
  print_ok "Profile" "$profile"
  print_ok "Secrets" "will auto-generate during install"

  print_next "sudo ./actools.sh preflight"
}

_init_usage() {
  cat <<'USAGE'
Usage:
  sudo ./actools.sh init --domain <d> --email <e> [--site-name "<n>"] [--profile <p>] \
                         [--actor-id <id>] [--change-ticket <ref>] [--force]

Flags:
  --domain         Required. Base domain, e.g. example.com
  --email          Required. Drupal admin email address.
  --site-name      Optional. Drupal site name. Defaults to the domain.
  --profile        Optional. Deployment profile. Defaults to 'community'.
                   This build ships only 'community'; other profiles
                   (e.g. community-plus) are separate products and cannot be
                   selected until their profile file is installed.
  --actor-id       Operator identity. Required only when the selected profile
                   sets PROFILE_REQUIRES_ACTOR (community does not).
  --change-ticket  Change-ticket reference. Required only when the selected
                   profile sets PROFILE_REQUIRES_CHANGE_TICKET (community does not).
  --force          Overwrite an existing actools.env.

Example:
  sudo ./actools.sh init \
    --domain example.com \
    --email admin@example.com \
    --site-name "Example Site"
USAGE
}
