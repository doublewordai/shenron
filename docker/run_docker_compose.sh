#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Choose CUDA variant via CU=126|129|130
export CU=${CU:-126}
COMPOSE_FILE=${COMPOSE_FILE:-"$SCRIPT_DIR/docker-compose.yml"}

# Common runtime config
export SHENRON_VERSION=${SHENRON_VERSION:-0.2.0}
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
    --override-generation-config \'{
    \"max_new_tokens\": 16384,
    \"presence_penalty\": 1.5,
    \"temperature\": 0.7,
    \"top_p\": 0.8,
    \"top_k\": 20,
    \"min_p\": 0
    }\'
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
docker compose -f "$COMPOSE_FILE" up -d
