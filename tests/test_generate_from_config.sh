#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

workdir="$(mktemp -d)"
cp "$ROOT_DIR/configs/Qwen06B-cu126-TP1.yml" "$workdir/"

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
    echo "expected generated file not found: $f" >&2
    exit 1
  fi
done

echo "generator produced expected files"
