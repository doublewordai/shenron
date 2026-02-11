#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
cp "$ROOT_DIR/configs/Qwen06B-cu126-TP1.yml" "$workdir/"

shenron "$workdir"

compose="$workdir/docker-compose.yml"
config="$workdir/Qwen06B-cu126-TP1.yml"

shenron_version="$(awk -F': ' '/^shenron_version:/ {print $2}' "$config")"
cuda_version="$(awk -F': ' '/^cuda_version:/ {print $2}' "$config")"
onwards_version="$(awk -F': ' '/^onwards_version:/ {print $2}' "$config")"

if grep -q '\${SHENRON_VERSION}' "$compose"; then
  echo "docker-compose.yml should be fully rendered" >&2
  exit 1
fi

if ! grep -q "ghcr.io/doublewordai/shenron:${shenron_version}-cu${cuda_version}" "$compose"; then
  echo "docker-compose.yml missing expected shenron image tag" >&2
  exit 1
fi

if ! grep -q "ghcr.io/doublewordai/onwards:${onwards_version}" "$compose"; then
  echo "docker-compose.yml missing expected onwards image tag" >&2
  exit 1
fi

echo "docker-compose.yml is fully rendered"
