#!/usr/bin/env bash
# =============================================================================
# modules/worker/xelatex.sh — XeLaTeX Worker Image
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

build_worker_image() {
  cat > "$INSTALL_DIR/Dockerfile.worker" <<WORKER_DOCKERFILE
FROM drupal:${DRUPAL_VERSION}-php${PHP_VERSION}-fpm

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
    || error "Worker image build failed."
  log "Worker image built -- XeLaTeX self-contained inside container."
}
