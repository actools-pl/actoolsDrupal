#!/usr/bin/env bash
# =============================================================================
# modules/stack/images.sh — Docker Image Building
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact image-build logic,
# extracted verbatim (byte-for-byte via sed) from actools.sh setup_stack() —
# the three Dockerfile heredocs and their `docker build` invocations. Sourced
# by actools.sh and called by setup_stack (and, in tests, by the golden-capture
# harness, which shims `docker`).
#
#   build_caddy_image  — Dockerfile.caddy heredoc is QUOTED ('CADDY_DOCKERFILE')
#                        so it stays literal (no variable expansion).
#   build_php_image    — preserves the `if [[ ! -f Dockerfile.php ]]` guard
#                        (use a repo-provided Dockerfile.php when present, else
#                        generate). Heredoc is unquoted so ${DRUPAL_VERSION} and
#                        ${PHP_VERSION} expand exactly as in the monolith. The
#                        docker-build line's multiple-space spacing is verbatim.
#   build_worker_image — unquoted heredoc (same expansion); multi-line
#                        docker build with --build-arg DRUPAL_VERSION/PHP_VERSION.
# =============================================================================

build_caddy_image() {
  cat > "$INSTALL_DIR/Dockerfile.caddy" <<'CADDY_DOCKERFILE'
FROM caddy:2.8-builder AS builder
RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit

FROM caddy:2.8-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
CADDY_DOCKERFILE

  log "Building custom Caddy image with caddy-ratelimit plugin..."
  docker build -t actools_caddy:custom -f "$INSTALL_DIR/Dockerfile.caddy" "$INSTALL_DIR" \
    || error "Caddy image build failed. Check Docker build output above."
  log "Custom Caddy image built."
}

build_php_image() {
  # Dockerfile.php — use repo version if available, otherwise generate
  if [[ ! -f "$INSTALL_DIR/Dockerfile.php" ]]; then
  cat > "$INSTALL_DIR/Dockerfile.php" <<PHP_DOCKERFILE
FROM drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm
RUN apt-get update -qq && apt-get install -y -qq git unzip && rm -rf /var/lib/apt/lists/*
RUN pecl install redis && docker-php-ext-enable redis
PHP_DOCKERFILE
  fi
  docker build -t actools_php:custom     -f "$INSTALL_DIR/Dockerfile.php"     "$INSTALL_DIR"     2>&1 | tail -5 || warn "PHP image build failed"
  log "PHP image with phpredis built."
}

build_worker_image() {
  cat > "$INSTALL_DIR/Dockerfile.worker" <<WORKER_DOCKERFILE
FROM drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm

RUN pecl install redis && docker-php-ext-enable redis

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      texlive-xetex \
      texlive-fonts-recommended \
      texlive-latex-extra \
      poppler-utils \
      ghostscript \
      default-mysql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN xelatex --version
WORKER_DOCKERFILE

  log "Building custom worker image with XeLaTeX toolchain..."
  docker build \
    -t actools_worker:latest \
    -f "$INSTALL_DIR/Dockerfile.worker" \
    --build-arg DRUPAL_VERSION="${DRUPAL_VERSION:-11}" \
    --build-arg PHP_VERSION="${PHP_VERSION:-8.3}" \
    "$INSTALL_DIR" \
    || error "Worker image build failed. Check Docker build output above."
  log "Worker image built -- XeLaTeX self-contained inside container."
}
