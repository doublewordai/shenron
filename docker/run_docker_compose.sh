#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

# Choose CUDA variant via CU=126|129|130
export CU=${CU:-126}

# If this script is downloaded from a GitHub Release, the placeholder below is stamped with the tag (e.g. v0.3.0).
# You can also set SHENRON_RELEASE_TAG manually.
_SHENRON_RELEASE_TAG_STAMP="__SHENRON_RELEASE_TAG__"
if [[ "$_SHENRON_RELEASE_TAG_STAMP" != "__SHENRON_RELEASE_TAG__" && -z "${SHENRON_RELEASE_TAG:-}" ]]; then
  export SHENRON_RELEASE_TAG="$_SHENRON_RELEASE_TAG_STAMP"
fi

# Prefer docker-compose.yml if it exists next to this script; fall back to docker-compose.yaml
if [[ -z "${COMPOSE_FILE:-}" ]]; then
  if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
  elif [[ -f "$SCRIPT_DIR/docker-compose.yaml" ]]; then
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
  else
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
  fi
fi

# Auto-download docker-compose if missing (lets you download just this script and run it)
if [[ ! -f "$COMPOSE_FILE" ]]; then
  if [[ "$COMPOSE_FILE" != "$SCRIPT_DIR/docker-compose.yml" && "$COMPOSE_FILE" != "$SCRIPT_DIR/docker-compose.yaml" ]]; then
    echo "Compose file not found: $COMPOSE_FILE" >&2
    exit 1
  fi

  if [[ -n "${SHENRON_RELEASE_TAG:-}" ]]; then
    SHENRON_COMPOSE_URL_DEFAULT="https://github.com/doublewordai/shenron/releases/download/${SHENRON_RELEASE_TAG}/docker-compose.yml"
  else
    SHENRON_COMPOSE_URL_DEFAULT="https://github.com/doublewordai/shenron/releases/latest/download/docker-compose.yml"
  fi
  SHENRON_COMPOSE_URL="${SHENRON_COMPOSE_URL:-$SHENRON_COMPOSE_URL_DEFAULT}"

  echo "Compose file not found; downloading: $SHENRON_COMPOSE_URL" >&2
  _tmp_compose=$(mktemp "${COMPOSE_FILE}.XXXXXX")
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SHENRON_COMPOSE_URL" -o "$_tmp_compose"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_tmp_compose" "$SHENRON_COMPOSE_URL"
  else
    echo "Missing downloader: install curl or wget" >&2
    exit 1
  fi
  chmod 0644 "$_tmp_compose"
  mv -f "$_tmp_compose" "$COMPOSE_FILE"
fi

# Common runtime config
if [[ -n "${SHENRON_VERSION:-}" ]]; then
  export SHENRON_VERSION
elif [[ -f "$ROOT_DIR/VERSION" ]]; then
  SHENRON_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
  export SHENRON_VERSION
elif [[ -n "${SHENRON_RELEASE_TAG:-}" ]]; then
  SHENRON_VERSION="${SHENRON_RELEASE_TAG#v}"
  export SHENRON_VERSION
fi
export MODELNAME=${MODELNAME:-Qwen/Qwen3-0.6B}
export APIKEY=${APIKEY:-sk-}
export VLLM_FLASHINFER_MOE_BACKEND=${VLLM_FLASHINFER_MOE_BACKEND:-throughput}

# vLLM runtime config (edit freely; no rebuild)
export VLLM_PORT=${VLLM_PORT:-8000}
export VLLM_HOST=${VLLM_HOST:-0.0.0.0}

# Onwards runtime config
export ONWARDS_PORT=${ONWARDS_PORT:-3000}

# Prometheus runtime config
export PROMETHEUS_PORT=${PROMETHEUS_PORT:-9090}

# Scouter reporter runtime config
export SCOUTER_COLLECTOR_INSTANCE=${SCOUTER_COLLECTOR_INSTANCE:-"host.docker.internal"} # needed for localhost outside of Docker network
export SCOUTER_COLLECTOR_URL=${SCOUTER_COLLECTOR_URL:-"http://${SCOUTER_COLLECTOR_INSTANCE}:4321"}
export SCOUTER_REPORTER_INTERVAL=${SCOUTER_REPORTER_INTERVAL:-10}
export SCOUTER_INGEST_API_KEY=${SCOUTER_INGEST_API_KEY:-"api-key"} # Optional API key for Scouter collector

# vLLM generation config override (pass as a single JSON string argument)
export VLLM_OVERRIDE_GENERATION_CONFIG=${VLLM_OVERRIDE_GENERATION_CONFIG:-'{"max_new_tokens":16384,"presence_penalty":1.5,"temperature":0.7,"top_p":0.8,"top_k":20,"min_p":0}'}

# Edit this array to control how vLLM is launched.
VLLM_ARGS=(
    --model "${MODELNAME}"
    --port "${VLLM_PORT}"
    --host "${VLLM_HOST}"
    --gpu-memory-utilization 0.7
    --tensor-parallel-size 1
    --trust-remote-code
    --limit-mm-per-prompt.video 0
    --async-scheduling
    --scheduling-policy "priority"
    --enable-auto-tool-choice
    --tool-call-parser "hermes"
    --generation-config "auto"
    --override-generation-config "${VLLM_OVERRIDE_GENERATION_CONFIG}"
)

mkdir -p "$SCRIPT_DIR/.generated"

# Generate onwards targets file (bind-mounted into onwards) [atomic]
_tmp_onwards=$(mktemp "$SCRIPT_DIR/.generated/onwards_targets.json.XXXXXX")
cat >"${_tmp_onwards}" <<EOF_ONWARDS
{
  "targets": {
    "${MODELNAME}": {
      "url": "http://vllm:${VLLM_PORT}/v1",
      "keys": ["${APIKEY}"],
      "onwards_model": "${MODELNAME}"
    }
  }
}
EOF_ONWARDS
chmod 0644 "${_tmp_onwards}"
mv -f "${_tmp_onwards}" "$SCRIPT_DIR/.generated/onwards_config.json"

# Generate Prometheus config (bind-mounted into prometheus) [atomic]
_tmp_prom=$(mktemp "$SCRIPT_DIR/.generated/prometheus.yml.XXXXXX")
cat >"${_tmp_prom}" <<EOF_PROM
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: vllm
    metrics_path: /metrics
    static_configs:
      - targets: ["vllm:${VLLM_PORT}"]
EOF_PROM
chmod 0644 "${_tmp_prom}"
mv -f "${_tmp_prom}" "$SCRIPT_DIR/.generated/prometheus.yml"

# Generate Scouter reporter env (loaded by docker compose) [atomic]
_tmp_scouter_env=$(mktemp "$SCRIPT_DIR/.generated/scouter_reporter.env.XXXXXX")
cat >"${_tmp_scouter_env}" <<EOF_SCOUTER_ENV
SCOUTER_MODE=reporter
PROMETHEUS_URL=http://prometheus:9090
COLLECTOR_URL=${SCOUTER_COLLECTOR_URL}
REPORTER_INTERVAL=${SCOUTER_REPORTER_INTERVAL}
MODEL_NAME=${MODELNAME}
SCOUTER_INGEST_API_KEY=${SCOUTER_INGEST_API_KEY}
EOF_SCOUTER_ENV
chmod 0644 "${_tmp_scouter_env}"
mv -f "${_tmp_scouter_env}" "$SCRIPT_DIR/.generated/scouter_reporter.env"

# Generate Onwards start script (bind-mounted into onwards) [atomic]
_tmp_onwards_start=$(mktemp "$SCRIPT_DIR/.generated/onwards_start.sh.XXXXXX")
cat >"${_tmp_onwards_start}" <<EOF_ONWARDS_START
#!/usr/bin/env bash
set -euo pipefail

exec onwards --targets /generated/onwards_config.json --port "${ONWARDS_PORT}"
EOF_ONWARDS_START
chmod +x "${_tmp_onwards_start}"
mv -f "${_tmp_onwards_start}" "$SCRIPT_DIR/.generated/onwards_start.sh"

# Generate vLLM start script (bind-mounted into vllm) [atomic]
_tmp_vllm_start=$(mktemp "$SCRIPT_DIR/.generated/vllm_start.sh.XXXXXX")
cat >"${_tmp_vllm_start}" <<EOF_VLLM
#!/usr/bin/env bash
set -euo pipefail

VLLM_FLASHINFER_MOE_BACKEND="${VLLM_FLASHINFER_MOE_BACKEND:-throughput}" \
vllm serve ${VLLM_ARGS[@]}
EOF_VLLM
chmod +x "${_tmp_vllm_start}"
mv -f "${_tmp_vllm_start}" "$SCRIPT_DIR/.generated/vllm_start.sh"

# Build images
# docker compose -f "$COMPOSE_FILE" build

# Start stack
if [ "$DRY_RUN" = "true" ]; then
  echo "Dry-run: generated docker/.generated/* (not running docker compose)"
  exit 0
fi

docker compose --project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE" up -d
