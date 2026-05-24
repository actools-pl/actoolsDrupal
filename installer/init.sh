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
# Required globals (set by actools.sh before sourcing):
#   INSTALL_DIR, ENV_FILE, REAL_USER, REAL_HOME
# =============================================================================

run_init() {
  local domain="" email="" site_name="" force=false unknown=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)    domain="${2:-}"; shift 2 ;;
      --email)     email="${2:-}"; shift 2 ;;
      --site-name) site_name="${2:-}"; shift 2 ;;
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

  # Required-field validation
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

  # Ownership and permissions — env contains secrets after install fills them
  chown "$REAL_USER:$REAL_USER" "$ENV_FILE" 2>/dev/null || true
  chmod 600 "$ENV_FILE"

  print_ok "actools.env" "created"
  print_ok "Domain" "$domain"
  print_ok "Admin email" "$email"
  print_ok "Site name" "$site_name"
  print_ok "Secrets" "will auto-generate during install"

  print_next "sudo ./actools.sh preflight"
}

_init_usage() {
  cat <<'USAGE'
Usage:
  sudo ./actools.sh init --domain <d> --email <e> [--site-name "<n>"] [--force]

Flags:
  --domain      Required. Base domain, e.g. example.com
  --email       Required. Drupal admin email address.
  --site-name   Optional. Drupal site name. Defaults to the domain.
  --force       Overwrite an existing actools.env.

Example:
  sudo ./actools.sh init \
    --domain example.com \
    --email admin@example.com \
    --site-name "Example Site"
USAGE
}
