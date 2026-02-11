#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
cp "$ROOT_DIR/configs/Qwen06B-cu126-TP1.yml" "$workdir/"

shenron "$workdir"

docker compose -f "$workdir/docker-compose.yml" config >/dev/null
services="$(docker compose -f "$workdir/docker-compose.yml" config --services)"
for svc in vllm onwards prometheus scouter-reporter; do
  if ! echo "$services" | grep -qx "$svc"; then
    echo "docker-compose config missing service: $svc" >&2
    exit 1
  fi
done

echo "docker-compose.yml parses and includes expected services"
