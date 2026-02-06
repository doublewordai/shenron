#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/docker/run_docker_compose.sh" --dry-run

# Validate docker-compose file parses.
SHENRON_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")" \
  docker compose -f "$ROOT_DIR/docker/docker-compose.yml" config >/dev/null

# Confirm expected containers/services exist.
services="$(SHENRON_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")" docker compose -f "$ROOT_DIR/docker/docker-compose.yml" config --services)"
for svc in vllm onwards prometheus scouter-reporter; do
  if ! echo "$services" | grep -qx "$svc"; then
    echo "docker-compose config missing service: $svc" >&2
    exit 1
  fi

done

echo "docker-compose.yml ok"
