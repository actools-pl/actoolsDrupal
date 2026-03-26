#!/usr/bin/env bash
# =============================================================================
# modules/preview/branch.sh — Phase 3: Ephemeral Preview Environments
# Usage: actools branch feature-123
#        actools branch --list
#        actools branch --destroy feature-123
# =============================================================================

INSTALL_DIR="${INSTALL_DIR:-/home/actools}"
PREVIEW_DIR="${INSTALL_DIR}/previews"
PREVIEW_STATE="${INSTALL_DIR}/.preview-state.json"

# Initialise preview state file
init_preview_state() {
  [[ -f "$PREVIEW_STATE" ]] || echo '{"previews":{}}' > "$PREVIEW_STATE"
}

# Sanitise branch name — only alphanumeric and hyphens
sanitise_branch() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

branch_create() {
  local raw_name="$1"
  local branch
  branch=$(sanitise_branch "$raw_name")

  if [[ -z "$branch" ]]; then
    echo "ERROR: branch name required. Usage: actools branch feature-123"
    exit 1
  fi

  local domain="${branch}.${BASE_DOMAIN}"
  local db_name="actools_pr_${branch//-/_}"
  local db_pass
  db_pass=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16)
  local admin_pass
  admin_pass=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16)
  local php_svc="php_pr_${branch//-/_}"
  local container="actools_php_pr_${branch//-/_}"

  echo ""
  echo "=== Creating Preview Environment ==="
  echo "Branch  : ${branch}"
  echo "Domain  : https://${domain}"
  echo "DB      : ${db_name}"
  echo ""

  init_preview_state

  # Check if already exists
  if jq -e ".previews.\"${branch}\"" "$PREVIEW_STATE" &>/dev/null; then
    echo "Preview '${branch}' already exists. Destroy it first:"
    echo "  actools branch --destroy ${branch}"
    exit 1
  fi

  # Step 1: Clone prod database
  echo "Step 1/5: Cloning production database..."
  cd "$INSTALL_DIR"
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_name}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_name}'@'%';
FLUSH PRIVILEGES;
SQL

  # Dump prod and restore into preview DB
  docker compose exec -T db mariadb-dump \
    -uroot -p"${DB_ROOT_PASS}" actools_prod \
    | docker compose exec -T db mariadb \
      -uroot -p"${DB_ROOT_PASS}" "${db_name}"
  echo "  ✓ Database cloned"

  # Step 2: Copy docroot
  echo "Step 2/5: Copying production docroot..."
  mkdir -p "${INSTALL_DIR}/docroot/previews/${branch}"
  cp -r "${INSTALL_DIR}/docroot/prod/." \
        "${INSTALL_DIR}/docroot/previews/${branch}/"
  sudo mkdir -p "${INSTALL_DIR}/logs/php_pr_${branch//-/_}"
  sudo chown actools:actools "${INSTALL_DIR}/logs/php_pr_${branch//-/_}"
  echo "  ✓ Docroot copied"

  # Step 3: Update settings.php for preview DB
  echo "Step 3/5: Updating database connection..."
  local settings_file="${INSTALL_DIR}/docroot/previews/${branch}/sites/default/settings.php"
  if [[ -f "$settings_file" ]]; then
    # Add preview DB override at end of settings.php
    cat >> "$settings_file" << SETTINGS

// Preview environment override — ${branch}
\$databases['default']['default']['database'] = '${db_name}';
\$databases['default']['default']['username'] = '${db_name}';
\$databases['default']['default']['password'] = '${db_pass}';
\$databases['default']['default']['host'] = 'db';
\$settings['trusted_host_patterns'][] = '^${branch//./\\.}\\.${BASE_DOMAIN//./\\.}$';
SETTINGS
    echo "  ✓ Settings updated"
  fi

  # Step 4: Start PHP container for preview
  echo "Step 4/5: Starting preview container..."
  docker run -d \
    --name "${container}" \
    --network actools_actools_net \
    --restart unless-stopped \
    -v "${INSTALL_DIR}/docroot/previews/${branch}:/var/www/html/prod" \
    -v "${INSTALL_DIR}/logs/php_pr_${branch//-/_}:/var/log/php" \
    -e PHP_MEMORY_LIMIT=512m \
    -e DB_ROOT_PASS="${DB_ROOT_PASS}" \
    --label "actools.preview=true" \
    --label "actools.branch=${branch}" \
    --label "actools.created=$(date +%F)" \
    drupal:11-php8.3-fpm
  echo "  ✓ Container started: ${container}"

  # Step 5: Add Caddy vhost
  echo "Step 5/5: Adding Caddy vhost..."
  cat >> "${INSTALL_DIR}/Caddyfile" << CADDY

${domain} {
    root * /var/www/html/prod/web
    php_fastcgi ${container}:9000
    import drupal_base
    tls ${DRUPAL_ADMIN_EMAIL}
}
CADDY

  # Update Caddy docroot mount and reload
  docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null
  echo "  ✓ Caddy vhost added"

  # Save state
  local created_at
  created_at=$(date +%F)
  jq ".previews.\"${branch}\" = {
    \"domain\": \"${domain}\",
    \"db_name\": \"${db_name}\",
    \"db_pass\": \"${db_pass}\",
    \"container\": \"${container}\",
    \"created\": \"${created_at}\",
    \"admin_pass\": \"${admin_pass}\"
  }" "$PREVIEW_STATE" > /tmp/ps.tmp && mv /tmp/ps.tmp "$PREVIEW_STATE"

  echo ""
  echo "=== Preview Environment Ready ==="
  echo "  URL      : https://${domain}"
  echo "  Admin    : https://${domain}/user/login"
  echo "  User     : admin"
  echo "  Password : ${admin_pass}"
  echo "  DB       : ${db_name}"
  echo "  Expires  : $(date -d '+7 days' +%F)"
  echo ""
  echo "Destroy when done: actools branch --destroy ${branch}"
}

branch_destroy() {
  local branch
  branch=$(sanitise_branch "$1")

  echo "=== Destroying Preview Environment: ${branch} ==="
  init_preview_state

  local container="actools_php_pr_${branch//-/_}"
  local db_name="actools_pr_${branch//-/_}"
  local domain="${branch}.${BASE_DOMAIN}"

  # Stop and remove container
  docker stop "${container}" 2>/dev/null && \
    docker rm "${container}" 2>/dev/null && \
    echo "  ✓ Container removed" || \
    echo "  ! Container already gone"

  # Drop database
  cd "$INSTALL_DIR"
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" <<SQL
DROP DATABASE IF EXISTS \`${db_name}\`;
DROP USER IF EXISTS '${db_name}'@'%';
FLUSH PRIVILEGES;
SQL
  echo "  ✓ Database dropped"

  # Remove docroot
  sudo chmod -R 755 "${INSTALL_DIR}/docroot/previews/${branch}" 2>/dev/null || true
  sudo rm -rf "${INSTALL_DIR}/docroot/previews/${branch}"
  echo "  ✓ Docroot removed"

  # Remove Caddy vhost
  python3 << PYEOF
import re
with open('${INSTALL_DIR}/Caddyfile') as f:
    content = f.read()
pattern = r'\n${domain} \{[^}]+\}\n'
content = re.sub(pattern, '\n', content, flags=re.DOTALL)
with open('${INSTALL_DIR}/Caddyfile', 'w') as f:
    f.write(content)
print("  ✓ Caddy vhost removed")
PYEOF

  docker exec actools_caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null

  # Remove from state
  jq "del(.previews.\"${branch}\")" "$PREVIEW_STATE" > /tmp/ps.tmp && \
    mv /tmp/ps.tmp "$PREVIEW_STATE"

  echo ""
  echo "  ✓ Preview environment '${branch}' destroyed"
}

branch_list() {
  init_preview_state
  echo ""
  echo "=== Active Preview Environments ==="
  local count
  count=$(jq '.previews | length' "$PREVIEW_STATE")
  if [[ "$count" -eq 0 ]]; then
    echo "  No active preview environments."
  else
    jq -r '.previews | to_entries[] | "  \(.key)\n    URL: https://\(.value.domain)\n    Created: \(.value.created)\n    DB: \(.value.db_name)"' \
      "$PREVIEW_STATE"
  fi
  echo ""
}

branch_cleanup() {
  init_preview_state
  echo "=== Auto-cleanup: removing previews older than 7 days ==="
  local cutoff
  cutoff=$(date -d '-7 days' +%F)
  jq -r ".previews | to_entries[] | select(.value.created <= \"${cutoff}\") | .key" \
    "$PREVIEW_STATE" | while read -r branch; do
    echo "Destroying expired preview: ${branch} (created: $(jq -r ".previews.\"${branch}\".created" "$PREVIEW_STATE"))"
    branch_destroy "$branch"
  done
}
