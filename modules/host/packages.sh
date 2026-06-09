#!/usr/bin/env bash
# =============================================================================
# modules/host/packages.sh — System Package Installation
#
# LIVE AUTHORITY (P0-G): this module carries the monolith's exact System
# Packages logic, extracted verbatim from actools.sh (former top-level
# "System Packages" block). It is sourced by actools.sh and driven by the
# `host` install stage (installer/dispatch.sh::actools::install::stage_host).
# Preserves the PKG_DONE_FLAG idempotency guard, the `age` package (required
# by modules/host/age.sh::setup_age_keypair), section logging, and order.
# =============================================================================

install_packages() {
  section "System Packages"
  mkdir -p /var/lib/actools
  if [[ ! -f "$PKG_DONE_FLAG" ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    apt-get install -y -qq \
      curl git unzip zip jq ca-certificates gnupg lsb-release age \
      ufw fail2ban rclone dnsutils logrotate
    touch "$PKG_DONE_FLAG"
    log "Packages installed."
  else
    log "Packages already installed -- skipping upgrade."
  fi
}
