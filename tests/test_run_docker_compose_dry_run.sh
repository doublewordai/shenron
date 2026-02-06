#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

gen_dir="$ROOT_DIR/docker/.generated"
rm -rf "$gen_dir"

"$ROOT_DIR/docker/run_docker_compose.sh" --dry-run

required=(
  "$gen_dir/onwards_config.json"
  "$gen_dir/prometheus.yml"
  "$gen_dir/scouter_reporter.env"
  "$gen_dir/onwards_start.sh"
  "$gen_dir/vllm_start.sh"
)

for f in "${required[@]}"; do
  if [ ! -f "$f" ]; then
    echo "Expected generated file not found: $f" >&2
    exit 1
  fi

done

echo "run_docker_compose.sh --dry-run generated files ok"
