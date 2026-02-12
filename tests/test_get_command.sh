#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
asset_dir="$tmpdir/assets"
work_dir="$tmpdir/work"

mkdir -p "$asset_dir" "$work_dir"
cp "$ROOT_DIR/configs/Qwen06B-cu126-TP1.yml" "$asset_dir/Qwen06B-cu126-TP1.yml"
printf "Qwen06B-cu126-TP1.yml\n" > "$asset_dir/configs-index.txt"

shenron get \
  --index-url "file://$asset_dir/configs-index.txt" \
  --base-url "file://$asset_dir/" \
  --name "Qwen06B-cu126-TP1.yml" \
  --dir "$work_dir"

required=(
  "$work_dir/Qwen06B-cu126-TP1.yml"
  "$work_dir/docker-compose.yml"
  "$work_dir/.generated/onwards_config.json"
  "$work_dir/.generated/prometheus.yml"
  "$work_dir/.generated/scouter_reporter.env"
  "$work_dir/.generated/engine_start.sh"
)

for f in "${required[@]}"; do
  if [ ! -f "$f" ]; then
    echo "expected file not found after shenron get: $f" >&2
    exit 1
  fi
done

echo "shenron get downloaded config and generated expected files"
