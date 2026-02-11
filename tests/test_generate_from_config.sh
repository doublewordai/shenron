#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for cfg in "$ROOT_DIR"/configs/*.yml; do
  workdir="$(mktemp -d)"
  cp "$cfg" "$workdir/"

  shenron "$workdir"

  required=(
    "$workdir/docker-compose.yml"
    "$workdir/.generated/onwards_config.json"
    "$workdir/.generated/prometheus.yml"
    "$workdir/.generated/scouter_reporter.env"
    "$workdir/.generated/vllm_start.sh"
  )

  for f in "${required[@]}"; do
    if [ ! -f "$f" ]; then
      echo "expected generated file not found for $(basename "$cfg"): $f" >&2
      exit 1
    fi
  done

  rm -rf "$workdir"
done

echo "generator produced expected files for all configs"
