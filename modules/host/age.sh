#!/usr/bin/env bash
# =============================================================================
# modules/host/age.sh — Encrypted-Backup Keypair (age)
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact age-keypair logic,
# extracted verbatim from actools.sh. Sourced by actools.sh and driven by the
# `host` install stage (installer/dispatch.sh::actools::install::stage_host),
# sequenced AFTER install_packages so the `age` package is already present.
#
# Generated per-deployment, after 'age' is installed. Consumed by
# modules/backup/* and experimental/dr/* (read from ${INSTALL_DIR}). Owned by the
# install operator (REAL_USER) like other install secrets; encrypted-backup
# consumption is a deferred, currently-unwired subsystem
# (see ROADMAP.md#encrypted-backups). warn-not-fail: a missing key disables an
# optional subsystem and must not abort install.
# =============================================================================

setup_age_keypair() {
  if [[ ! -f "${INSTALL_DIR}/.age-key.txt" ]]; then
    log "Generating per-deployment age keypair..."
    if age-keygen -o "${INSTALL_DIR}/.age-key.txt" 2>/dev/null; then
      if ! chmod 600 "${INSTALL_DIR}/.age-key.txt"; then
        rm -f "${INSTALL_DIR}/.age-key.txt" "${INSTALL_DIR}/.age-public-key"
        warn "age keypair created but private-key permission hardening failed; encrypted-backup features will be unavailable until repaired."
      elif age-keygen -y "${INSTALL_DIR}/.age-key.txt" > "${INSTALL_DIR}/.age-public-key" 2>/dev/null; then
        chmod 644 "${INSTALL_DIR}/.age-public-key" || warn "age public key permissions could not be normalized."
        chown "$REAL_USER:$REAL_USER" "${INSTALL_DIR}/.age-key.txt" "${INSTALL_DIR}/.age-public-key" 2>/dev/null \
          || warn "age keypair generated but ownership could not be set to ${REAL_USER}."
        log "age keypair generated (owned by ${REAL_USER})."
      else
        warn "age keypair private key created but public-key derivation failed; encrypted-backup features will be unavailable until repaired."
      fi
    else
      warn "age-keygen failed; encrypted-backup features will be unavailable until a keypair is generated."
    fi
  else
    log "age keypair already present — preserving existing key."
  fi
}
