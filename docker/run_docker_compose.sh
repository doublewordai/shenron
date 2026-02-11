#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

CONFIG_PATH=${1:-"$ROOT_DIR/configs/Qwen06B-cu126-TP1.yml"}

if ! command -v shenron >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Missing `shenron` CLI.
Install it first: uv pip install shenron
MSG
  exit 1
fi

shenron "$CONFIG_PATH" --output-dir "$SCRIPT_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry-run: generated docker-compose.yml and docker/.generated/*"
  exit 0
fi

docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/docker-compose.yml" up -d
