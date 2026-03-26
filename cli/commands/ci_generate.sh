#!/usr/bin/env bash
# =============================================================================
# cli/commands/ci_generate.sh — Phase 3: CI/CD Pipeline Generation
# Usage: actools ci --generate --platform=github-actions
# =============================================================================

cmd_ci_generate() {
  local platform="${1:-github-actions}"
  local output_dir="${2:-/tmp/actools-ci-output}"
  local drupal_root="${INSTALL_DIR}/docroot/prod"

  echo ""
  echo "=== Actools CI/CD Generator ==="
  echo "Platform : ${platform}"
  echo "Domain   : ${BASE_DOMAIN}"
  echo "PHP      : ${PHP_VERSION:-8.3}"
  echo ""

  case "$platform" in
    github-actions|github)
      generate_github_actions "$output_dir" "$drupal_root"
      ;;
    gitlab)
      echo "GitLab CI generation coming in Phase 3.1"
      ;;
    *)
      echo "Unknown platform: ${platform}"
      echo "Supported: github-actions, gitlab"
      exit 1
      ;;
  esac
}

generate_github_actions() {
  local output_dir="$1"
  local drupal_root="$2"
  local tpl_dir="${INSTALL_DIR}/templates/ci"
  local workflows_dir="${output_dir}/.github/workflows"

  mkdir -p "$workflows_dir"

  echo "Generating GitHub Actions workflows..."
  echo ""

  # Process each template — replace {{VARIABLES}}
  for tpl in "${tpl_dir}"/github-*.yml.tpl; do
    local filename
    filename=$(basename "$tpl" .tpl)
    local output="${workflows_dir}/${filename}"

    sed \
      -e "s|{{BASE_DOMAIN}}|${BASE_DOMAIN}|g" \
      -e "s|{{PHP_VERSION}}|${PHP_VERSION:-8.3}|g" \
      -e "s|{{DRUPAL_ROOT}}|${drupal_root}|g" \
      -e "s|{{DRUPAL_ADMIN_EMAIL}}|${DRUPAL_ADMIN_EMAIL}|g" \
      "$tpl" > "$output"

    echo "  ✓ Generated: .github/workflows/${filename}"
  done

  echo ""
  echo "=== Generated Files ==="
  echo "Location: ${output_dir}"
  echo ""
  echo "  .github/workflows/github-test.yml"
  echo "    → Runs on every PR: PHP CodeSniffer, PHPStan, composer validate"
  echo ""
  echo "  .github/workflows/github-deploy.yml"
  echo "    → Runs on merge to main: backup + pull + updb + health check"
  echo ""
  echo "  .github/workflows/github-security.yml"
  echo "    → Runs weekly: composer audit + Drupal security advisories"
  echo ""
  echo "=== Next Steps ==="
  echo "1. Copy .github/ to your Drupal repo root:"
  echo "   cp -r ${output_dir}/.github /path/to/your/drupal/repo/"
  echo ""
  echo "2. Add SSH deploy key to GitHub secrets:"
  echo "   GitHub repo → Settings → Secrets → DEPLOY_SSH_KEY"
  echo "   (use the private key that has SSH access to ${BASE_DOMAIN})"
  echo ""
  echo "3. Push to GitHub — workflows activate automatically"
  echo ""
}
