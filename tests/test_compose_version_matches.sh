#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
compose="$ROOT_DIR/docker/docker-compose.yml"

# Expect the fallback in docker-compose to match VERSION so the stack stays tied to Shenron releases.
fallback="$(sed -nE 's/.*\$\{SHENRON_VERSION:-([^}]*)\}.*/\1/p' "$compose" | head -n1)"

if [ -z "$fallback" ]; then
  echo "Could not find SHENRON_VERSION fallback in docker-compose.yml" >&2
  exit 1
fi

if [ "$fallback" != "$version" ]; then
  echo "docker-compose.yml SHENRON_VERSION fallback ($fallback) != VERSION ($version)" >&2
  exit 1
fi

echo "docker-compose version fallback matches VERSION: $version"
