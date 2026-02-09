# Copilot instructions (Shenron)

## What this repo is
- This repository is primarily a **docker-compose distribution + launcher script** for a multi-service inference stack.
- The stack is defined in [docker/docker-compose.yml](docker/docker-compose.yml) and is driven by [docker/run_docker_compose.sh](docker/run_docker_compose.sh), which generates runtime config into `docker/.generated/`.

## Big-picture runtime architecture
- `vllm` (GPU inference) runs `vllm serve ...` inside `ghcr.io/doublewordai/shenron:${SHENRON_VERSION}-cu${CU}`.
- `onwards` is an **external gateway image** (`ghcr.io/doublewordai/onwards:latest`) configured via a generated JSON file.
- `prometheus` scrapes vLLM metrics over the docker network.
- `scouter-reporter` reads Prometheus and reports to a Scouter collector (reachable via `host.docker.internal`).

## Local workflows (source of truth)
- Generate configs only: `./docker/run_docker_compose.sh --dry-run` (writes `docker/.generated/*`).
- Start the stack: `./docker/run_docker_compose.sh` (runs `docker compose ... up -d`).
- vLLM is **not exposed to the host**; debug it via compose exec, e.g. `docker compose -f docker/docker-compose.yml exec vllm curl -sS http://localhost:8000/health`.

## Editing behavior (important conventions)
- If changing vLLM launch flags, edit the `VLLM_ARGS=(...)` array in [docker/run_docker_compose.sh](docker/run_docker_compose.sh). Do **not** hand-edit `docker/.generated/vllm_start.sh` (it is regenerated).
- If you change `MODELNAME`, `APIKEY`, or ports (e.g. `VLLM_PORT`), rerun `./docker/run_docker_compose.sh` to regenerate `docker/.generated/onwards_config.json`, `prometheus.yml`, and `*.env`.
- When updating only runtime args (no image rebuild), restart just vLLM:
  `docker compose -f docker/docker-compose.yml up -d --no-deps --force-recreate vllm`

## Versioning and releases (don’t break this)
- `VERSION` is the single source of truth for the release version (used as `SHENRON_VERSION`).
- Compose must reference `${SHENRON_VERSION}` **without** a hardcoded fallback; tests enforce this (see [tests/test_compose_version_matches.sh](tests/test_compose_version_matches.sh)).
- [docker/run_docker_compose.sh](docker/run_docker_compose.sh) contains the placeholder `__SHENRON_RELEASE_TAG__` which is stamped by the release workflow; keep that placeholder intact.

## Tests / CI expectations
- Run the same checks as CI: `./scripts/ci.sh`.
  - Includes shell tests in [tests/](tests/) and optionally runs docker-compose validation if `docker` is available.
- ShellCheck is expected to pass for the launcher script: `shellcheck -x docker/run_docker_compose.sh`.

## When making changes
- Prefer small, surgical edits to [docker/run_docker_compose.sh](docker/run_docker_compose.sh), [docker/docker-compose.yml](docker/docker-compose.yml), and the shell tests.
- If you add/remove any generated artifact, update the required-file list in [tests/test_run_docker_compose_dry_run.sh](tests/test_run_docker_compose_dry_run.sh).