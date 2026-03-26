#!/usr/bin/env bash
# =============================================================================
# cron/stats.sh — Hourly Docker Stats Collection
# Used by Phase 2 cost-optimize command
# =============================================================================

STATS_DIR="/home/actools/logs/stats"
mkdir -p "$STATS_DIR"
TIMESTAMP=$(date -u +%FT%TZ)
docker stats --no-stream \
  --format "{\"container\":\"{{.Name}}\",\"cpu\":\"{{.CPUPerc}}\",\"mem\":\"{{.MemUsage}}\",\"timestamp\":\"${TIMESTAMP}\"}" \
  >> "$STATS_DIR/$(date +%F).jsonl" 2>/dev/null || true
find "$STATS_DIR" -name '*.jsonl' -mtime +30 -delete
