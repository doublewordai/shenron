# Shenron docker-compose

## What the `build:` section does

In each `docker-compose-cu*.yml`, every service has a `build:` section that tells Docker Compose how to **build the image locally**:
- `context`: the directory sent to the Docker build (i.e. what files are available to `COPY` in the Dockerfile).
- `dockerfile`: the Dockerfile path (relative to the `context`).

If you run `docker compose up --build` (or `docker compose build`), Compose will build:
- `ghcr.io/doublewordai/shenron:${SHENRON_VERSION}-cu*` from `docker/Dockerfile.cu*`
- `ghcr.io/doublewordai/shenron:${SHENRON_VERSION}-onwards` from `docker/Dockerfile.onwards`
- `ghcr.io/doublewordai/shenron:${SHENRON_VERSION}-prometheus` from `docker/Dockerfile.prometheus`

If you already have those images built/pulled, you can run `docker compose up` without rebuilding.

## Launching (cu126/cu129/cu130)

From the repo root:

```bash
# Choose CUDA variant
export CU=126  # or 129, 130
export COMPOSE_FILE=docker/docker-compose.yml

# Common runtime config
export SHENRON_VERSION=$(cat VERSION)
export MODELNAME=Qwen/Qwen3-VL-235B-A22B-Instruct-FP8
export APIKEY=sk-
export HF_HOME=$HOME/.cache/huggingface

# Build images
docker compose -f "$COMPOSE_FILE" build

# Start stack
docker compose -f "$COMPOSE_FILE" up
```

Ports:
- Onwards: `http://localhost:${ONWARDS_PORT:-3000}`
- Prometheus: `http://localhost:${PROMETHEUS_PORT:-9090}` (scrapes `http://vllm:8000/metrics`)

vLLM is **not published to the host** (internal-only). To hit it from your machine for debugging:

```bash
docker compose -f "$COMPOSE_FILE" exec vllm curl -sS http://localhost:8000/health
```

## Editing vLLM args without rebuilding (docker-compose)

Edit `docker/run_docker_compose.sh` (it generates `docker/.generated/vllm_start.sh`), then restart just the vLLM service:

```bash
# pick CUDA variant
CU=130
COMPOSE_FILE=docker/docker-compose.yml

# apply changes (no rebuild)
docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate vllm
```

Notes:
- Keep `--host 0.0.0.0` so `onwards` and `prometheus` can reach vLLM over the docker network.
- If you change `VLLM_PORT`, rerun `./docker/run_docker_compose.sh` so it regenerates onwards/prometheus configs.
