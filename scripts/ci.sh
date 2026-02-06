#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_test() {
  local t="$1"
  echo "==> $t"
  "$t"
}

run_test "$ROOT_DIR/tests/test_compose_version_matches.sh"
run_test "$ROOT_DIR/tests/test_run_docker_compose_dry_run.sh"

if command -v docker >/dev/null 2>&1; then
  run_test "$ROOT_DIR/tests/test_docker_compose.sh"
else
  echo "==> docker not available, skipping docker compose validation"
fi