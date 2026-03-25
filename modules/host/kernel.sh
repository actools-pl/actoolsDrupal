#!/usr/bin/env bash
# =============================================================================
# modules/host/kernel.sh — Kernel Tuning
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

tune_kernel() {
  section "Kernel Tuning"
  cat > /etc/sysctl.d/99-actools.conf <<SYSCTL
vm.overcommit_memory=1
vm.swappiness=10
fs.file-max=2097152
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=10240 65535
SYSCTL
  sysctl --system >/dev/null 2>&1
  log "Kernel tuning applied."
}
