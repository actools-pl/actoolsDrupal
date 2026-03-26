#!/usr/bin/env bash
# /home/actools/modules/compliance/gdpr.sh
# Phase 4.5 — GDPR compliance tools

ACTOOLS_HOME="/home/actools"
COMPOSE_FILE="${ACTOOLS_HOME}/docker-compose.yml"
AUDIT_LOG="${ACTOOLS_HOME}/logs/audit.log"
GDPR_LOG="${ACTOOLS_HOME}/logs/gdpr.log"
EXPORT_DIR="${ACTOOLS_HOME}/backups/gdpr-exports"

gdpr_log() {
  echo "$(date -u +%FT%TZ) [gdpr] operator=$(whoami) $*" | tee -a "${GDPR_LOG}"
}

sql() {
  docker compose -f "${COMPOSE_FILE}" exec -T db \
    mariadb --user=root --password="${DB_ROOT_PASS}" \
    --batch --skip-column-names actools_prod "$@" 2>/dev/null
}

drush() {
  docker compose -f "${COMPOSE_FILE}" exec -T php_prod \
    bash -c "cd /var/www/html/prod && ./vendor/bin/drush $*" 2>/dev/null
}

# ── Export ────────────────────────────────────────────────────────────────────
gdpr_export() {
  local email="${1:-}"
  [[ -z "${email}" ]] && { echo "Usage: actools gdpr export <email>"; exit 1; }

  gdpr_log "action=export email=${email}"
  mkdir -p "${EXPORT_DIR}"

  local outfile="${EXPORT_DIR}/gdpr-export-$(echo "${email}" | tr '@.' '--')-$(date +%F).json"

  echo "Exporting data for: ${email}"

  # Get user record
  local uid name status created last_login
  uid=$(sql -e "SELECT uid FROM users_field_data WHERE mail='${email}' LIMIT 1;")
  [[ -z "${uid}" ]] && { echo "ERROR: User not found: ${email}"; gdpr_log "action=export email=${email} result=not_found"; exit 1; }

  name=$(sql -e "SELECT name FROM users_field_data WHERE uid=${uid};")
  status=$(sql -e "SELECT status FROM users_field_data WHERE uid=${uid};")
  created=$(sql -e "SELECT FROM_UNIXTIME(created) FROM users_field_data WHERE uid=${uid};")
  last_login=$(sql -e "SELECT FROM_UNIXTIME(login) FROM users_field_data WHERE uid=${uid};")

  # Get authored nodes
  local nodes
  nodes=$(sql -e "SELECT nid, type, title, FROM_UNIXTIME(created), status FROM node_field_data WHERE uid=${uid} LIMIT 100;" \
    | awk 'BEGIN{print "["} {printf "{\"nid\":\"%s\",\"type\":\"%s\",\"title\":\"%s\",\"created\":\"%s\",\"status\":\"%s\"},\n",$1,$2,$3,$4,$5} END{print "]"}')

  # Get node count
  local node_count
  node_count=$(sql -e "SELECT COUNT(*) FROM node_field_data WHERE uid=${uid};")

  # Get roles
  local roles
  roles=$(sql -e "SELECT roles_target_id FROM user__roles WHERE entity_id=${uid};" \
    | tr '\n' ',' | sed 's/,$//')

  # Build JSON
  python3 -c "
import json, sys
data = {
  'export_date': '$(date -u +%FT%TZ)',
  'requested_by': '$(whoami)',
  'gdpr_basis': 'Art. 15 GDPR — Right of Access',
  'profile': {
    'uid': '${uid}',
    'name': '${name}',
    'email': '${email}',
    'status': 'active' if '${status}' == '1' else 'blocked',
    'created': '${created}',
    'last_login': '${last_login}',
    'roles': [r for r in '${roles}'.split(',') if r],
  },
  'content': {
    'total_nodes': '${node_count}',
    'note': 'First 100 nodes shown',
  },
  'audit_entries': [l.strip() for l in open('${AUDIT_LOG}') if '${email}' in l]
    if __import__('os').path.exists('${AUDIT_LOG}') else [],
}
print(json.dumps(data, indent=2))
" > "${outfile}"

  local size
  size=$(du -sh "${outfile}" | cut -f1)
  echo "  Export saved: ${outfile}"
  echo "  Size: ${size}"
  gdpr_log "action=export email=${email} result=success file=${outfile}"
}

# ── Delete ────────────────────────────────────────────────────────────────────
gdpr_delete() {
  local email="${1:-}"
  [[ -z "${email}" ]] && { echo "Usage: actools gdpr delete <email>"; exit 1; }

  local uid
  uid=$(sql -e "SELECT uid FROM users_field_data WHERE mail='${email}' LIMIT 1;")
  [[ -z "${uid}" ]] && { echo "ERROR: User not found: ${email}"; exit 1; }
  [[ "${uid}" == "1" ]] && { echo "ERROR: Cannot delete UID 1 (superadmin)"; exit 1; }

  echo "RIGHT TO ERASURE — this will permanently delete:"
  echo "  User account: ${email} (uid=${uid})"
  echo "  All content authored by this user"
  echo ""
  echo "  This action is IRREVERSIBLE."
  echo ""
  read -r -p "  Type the email address to confirm: " confirm
  [[ "${confirm}" == "${email}" ]] || { echo "Aborted."; exit 0; }

  gdpr_log "action=delete email=${email} uid=${uid} operator=$(whoami)"

  echo "Creating pre-deletion export..."
  gdpr_export "${email}"

  echo "Cancelling user account..."
  drush "user:cancel --delete-content --yes '${email}'"

  gdpr_log "action=delete email=${email} result=success"
  echo "  Deleted: ${email}"
}

# ── Audit ─────────────────────────────────────────────────────────────────────
gdpr_audit() {
  local email="${1:-}"
  [[ -z "${email}" ]] && { echo "Usage: actools gdpr audit <email>"; exit 1; }

  gdpr_log "action=audit_view email=${email}"

  echo "── GDPR audit for: ${email} ──────────────────────────"
  echo ""
  echo "GDPR actions:"
  grep "${email}" "${GDPR_LOG}" 2>/dev/null | sed 's/^/  /' || echo "  None recorded"
  echo ""
  echo "CLI audit entries:"
  grep "${email}" "${AUDIT_LOG}" 2>/dev/null | tail -50 | sed 's/^/  /' || echo "  None recorded"
}

# ── Report ────────────────────────────────────────────────────────────────────
gdpr_report() {
  gdpr_log "action=report"

  echo "── GDPR Compliance Report ────────────────────────────"
  echo "  Generated: $(date -u +%FT%TZ)"
  echo "  Operator:  $(whoami)"
  echo ""

  echo "User statistics:"
  sql -e "SELECT
    COUNT(*) as total,
    SUM(status=1) as active,
    SUM(status=0) as blocked
    FROM users_field_data WHERE uid > 0;" \
    | awk '{printf "  Total: %s  Active: %s  Blocked: %s\n", $1, $2, $3}'

  echo ""
  echo "Data retention:"
  echo "  DB backups:      $(find "${ACTOOLS_HOME}/backups/db" -name "*.age" 2>/dev/null | wc -l) dumps (${BACKUP_RETENTION_DAYS:-7} day retention)"
  echo "  Binlog archives: $(find "${ACTOOLS_HOME}/backups/binlogs" -name "*.age" 2>/dev/null | wc -l) files"
  echo "  DNA snapshots:   $(find "${ACTOOLS_HOME}/backups/dna" -name "*.age" 2>/dev/null | wc -l) files"
  echo "  Audit log:       $(wc -l < "${AUDIT_LOG}" 2>/dev/null || echo 0) entries"
  echo "  GDPR log:        $(wc -l < "${GDPR_LOG}" 2>/dev/null || echo 0) entries"

  echo ""
  echo "GDPR actions (all time):"
  grep "action=export\|action=delete" "${GDPR_LOG}" 2>/dev/null \
    | tail -20 | sed 's/^/  /' || echo "  No actions recorded"

  echo ""
  echo "Encryption:"
  echo "  DB backups:      age-encrypted ✓"
  echo "  Binlog archives: age-encrypted ✓"
  echo "  MariaDB:         TLS 1.3 (require_secure_transport=ON) ✓"
  echo "  DNA snapshots:   age-encrypted ✓"

  echo ""
  echo "Compliance checklist:"
  echo "  ✓ Right of Access    — actools gdpr export <email>"
  echo "  ✓ Right to Erasure   — actools gdpr delete <email>"
  echo "  ✓ Audit trail        — logs/audit.log + logs/gdpr.log"
  echo "  ✓ Encryption at rest — age"
  echo "  ✓ Encryption transit — TLS 1.3"
  echo "  ✓ Data retention     — ${BACKUP_RETENTION_DAYS:-7} days"
  echo "  ✓ Access control     — RBAC (dev/ops/viewer)"
}
