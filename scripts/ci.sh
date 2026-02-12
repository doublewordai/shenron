#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_test() {
  local t="$1"
  echo "==> $t"
  "$t"
}

echo "==> cargo test"
(cd "$ROOT_DIR" && cargo test)

echo "==> install local shenron package"
python3 -m pip install --upgrade pip
python3 -m pip install -e "$ROOT_DIR"

run_test "$ROOT_DIR/tests/test_generate_from_config.sh"
run_test "$ROOT_DIR/tests/test_compose_generation.sh"
run_test "$ROOT_DIR/tests/test_get_command.sh"

if command -v docker >/dev/null 2>&1; then
  run_test "$ROOT_DIR/tests/test_docker_compose.sh"
else
  echo "==> docker not available, skipping docker compose validation"
fi
