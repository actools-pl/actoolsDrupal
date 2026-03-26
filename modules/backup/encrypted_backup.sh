#!/usr/bin/env bash
# =============================================================================
# modules/backup/encrypted_backup.sh — Phase 4.5: Age-Encrypted Backups
# =============================================================================

INSTALL_DIR="${INSTALL_DIR:-/home/actools}"
BACKUP_DIR="${INSTALL_DIR}/backups"
AGE_PUBLIC_KEY=$(cat "${INSTALL_DIR}/.age-public-key" 2>/dev/null)
AGE_KEY_FILE="${INSTALL_DIR}/.age-key.txt"

backup_encrypted() {
  local env="${1:-prod}"
  local db_name="actools_${env}"
  local timestamp
  timestamp=$(date +%F_%H%M%S)

  mkdir -p "$BACKUP_DIR"

  echo ""
  echo "=== Encrypted Backup: ${env} ==="
  echo "Timestamp : ${timestamp}"
  echo "Key       : ${AGE_PUBLIC_KEY:0:20}..."
  echo ""

  # Step 1: DB dump
  echo "Step 1/4: Dumping database..."
  local db_dump="${BACKUP_DIR}/${env}_db_${timestamp}.sql.gz"
  cd "$INSTALL_DIR"
  docker compose exec -T db mariadb-dump \
    -uroot -p"${DB_ROOT_PASS}" \
    --single-transaction --quick \
    "${db_name}" | gzip > "$db_dump"
  echo "  ✓ DB dump: $(du -sh "$db_dump" | cut -f1)"

  # Step 2: Files archive
  echo "Step 2/4: Archiving files..."
  local files_src="${INSTALL_DIR}/docroot/${env}/web/sites/default/files"
  local files_arc="${BACKUP_DIR}/${env}_files_${timestamp}.tar.gz"
  if [[ -d "$files_src" ]]; then
    tar -czf "$files_arc" -C "$files_src" . 2>/dev/null
    echo "  ✓ Files archive: $(du -sh "$files_arc" | cut -f1)"
  else
    echo "  ! No files directory found — skipping"
  fi

  # Step 3: Encrypt both with age
  echo "Step 3/4: Encrypting with age..."
  age -r "$AGE_PUBLIC_KEY" -o "${db_dump}.age" "$db_dump"
  sha256sum "${db_dump}.age" > "${db_dump}.age.sha256"
  rm -f "$db_dump"  # Remove unencrypted dump
  echo "  ✓ Encrypted DB: $(du -sh "${db_dump}.age" | cut -f1)"

  if [[ -f "$files_arc" ]]; then
    age -r "$AGE_PUBLIC_KEY" -o "${files_arc}.age" "$files_arc"
    sha256sum "${files_arc}.age" > "${files_arc}.age.sha256"
    rm -f "$files_arc"  # Remove unencrypted archive
    echo "  ✓ Encrypted files: $(du -sh "${files_arc}.age" | cut -f1)"
  fi

  # Step 4: Verify checksums
  echo "Step 4/4: Verifying checksums..."
  sha256sum -c "${db_dump}.age.sha256" &>/dev/null \
    && echo "  ✓ DB checksum verified" \
    || echo "  ✗ DB checksum FAILED"

  echo ""
  echo "=== Backup complete ==="
  echo "  DB  : ${db_dump}.age"
  [[ -f "${files_arc}.age" ]] && echo "  Files: ${files_arc}.age"
  echo ""
  echo "To decrypt (on any machine with the private key):"
  echo "  age --decrypt -i ~/.age-key.txt ${db_dump}.age > restore.sql.gz"
}

backup_decrypt() {
  local encrypted_file="$1"
  local output_file="${2:-${encrypted_file%.age}}"

  if [[ -z "$encrypted_file" ]]; then
    echo "Usage: actools backup-decrypt <file.age> [output_file]"
    exit 1
  fi

  if [[ ! -f "$AGE_KEY_FILE" ]]; then
    echo "ERROR: Private key not found at ${AGE_KEY_FILE}"
    echo "Copy the private key from your secure storage to this path."
    exit 1
  fi

  echo "Decrypting: ${encrypted_file}"
  age --decrypt -i "$AGE_KEY_FILE" "$encrypted_file" > "$output_file"
  echo "  ✓ Decrypted to: ${output_file}"
}

backup_list_encrypted() {
  echo ""
  echo "=== Encrypted Backups ==="
  ls -lht "${BACKUP_DIR}"/*.age 2>/dev/null \
    | awk '{print "  " $NF " (" $5 ")"}'  \
    || echo "  No encrypted backups found."
  echo ""
}
