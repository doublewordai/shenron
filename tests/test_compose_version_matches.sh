#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
compose="$ROOT_DIR/docker/docker-compose.yml"

# Expect docker-compose to use SHENRON_VERSION (and not a hardcoded fallback) so releases don't drift.
# shellcheck disable=SC2016
if ! grep -q '\${SHENRON_VERSION}' "$compose"; then
  echo "docker-compose.yml does not reference SHENRON_VERSION" >&2
  exit 1
fi

# shellcheck disable=SC2016
if grep -q '\${SHENRON_VERSION:-' "$compose"; then
  echo "docker-compose.yml should not hardcode a SHENRON_VERSION fallback" >&2
  exit 1
fi

echo "docker-compose version is controlled by SHENRON_VERSION (VERSION=$version)"
