#!/bin/bash
set -euo pipefail

# Default values
MODELNAME=${MODELNAME:-"Qwen/Qwen3-VL-235B-A22B-Instruct-FP8"}
APIKEY=${APIKEY:-"sk-"}
VLLM_PORT=${VLLM_PORT:-8000}
ONWARDS_PORT=${ONWARDS_PORT:-3000}
SSH_PORT=${SSH_PORT:-2222}
WAIT_ATTEMPTS=${WAIT_ATTEMPTS:-60}

echo "=== Container Entrypoint Starting ==="
echo "Model: $MODELNAME"
echo "SSH Port: $SSH_PORT"
echo "vLLM Port: $VLLM_PORT"
echo "Onwards Port: $ONWARDS_PORT"

# ============================================================
# 1. Setup and Start SSH Daemon - useful for debugging
# ============================================================
echo "=== Setting up SSH server ==="

mkdir -p /run/sshd /root/.ssh
chmod 700 /root/.ssh

if [ -n "${PUBLIC_KEY:-}" ]; then
  printf '%s\n' "$PUBLIC_KEY" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  echo "SSH public key configured"
fi

if [ -n "${SSH_PORT:-}" ]; then
  sed -i '/^[#[:space:]]*Port /d' /etc/ssh/sshd_config
  echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

echo "Starting SSH server on port $SSH_PORT"
/usr/sbin/sshd -D -e &
SSH_PID=$!
echo "SSH daemon started with PID $SSH_PID"

# ============================================================
# 2. Create Onwards Config
# ============================================================
echo "=== Setting up Onwards proxy ==="

mkdir -p /etc/onwards

cat > /etc/onwards/config.json << EOF
{
  "targets": {
    "$MODELNAME": {
      "url": "http://localhost:$VLLM_PORT/v1",
      "keys": ["$APIKEY"],
      "onwards_model": "$MODELNAME"
    }
  }
}
EOF

echo "Onwards config created for model: $MODELNAME"

# ============================================================
# 3. Start vLLM + Onwards under simple supervision (Option A)
#    - If vLLM or onwards crashes, restart them
#    - Do NOT kill SSH or exit PID 1 just because they crashed
# ============================================================

# Activate the Python environment
source /opt/shenron/.venv/bin/activate

# vLLM args (edit as needed)
VLLM_ARGS=(
  --model "$MODELNAME"
  --port "$VLLM_PORT"
  --host "127.0.0.1"
  --served-model-name "$MODELNAME"
  --gpu-memory-utilization 0.9
  --tensor-parallel-size 4
  --trust-remote-code
  --limit-mm-per-prompt.video 0 # disable video inputs
  --async-scheduling
  --scheduling-policy "priority"
)

start_vllm() {
  echo "=== Starting vLLM server ==="
  echo "Command: vllm serve ${VLLM_ARGS[*]}"
  # NOTE: keep logs for post-mortem
  VLLM_LOGGING_LEVEL=INFO \
  VLLM_USE_FLASHINFER_MOE_FP8=1 \
    VLLM_FLASHINFER_MOE_BACKEND=throughput \
    vllm serve "${VLLM_ARGS[@]}" >> /var/log/vllm.log 2>&1 &
  VLLM_PID=$!
  echo "vLLM started with PID $VLLM_PID"
}

start_onwards() {
  echo "=== Starting Onwards proxy ==="
  echo "Starting onwards on port $ONWARDS_PORT"
  onwards --targets /etc/onwards/config.json --port "$ONWARDS_PORT" >> /var/log/onwards.log 2>&1 &
  ONWARDS_PID=$!
  echo "Onwards started with PID $ONWARDS_PID"
}

# Supervisor loops
(
  while true; do
    start_vllm
    wait "$VLLM_PID" || true
    code=$?
    echo "vLLM exited (code=$code). Restarting in 2s. (SSH stays up)"
    sleep 2
  done
) &
VLLM_SUP_PID=$!

(
  while true; do
    start_onwards
    wait "$ONWARDS_PID" || true
    code=$?
    echo "Onwards exited (code=$code). Restarting in 2s. (SSH stays up)"
    sleep 2
  done
) &
ONWARDS_SUP_PID=$!

# ============================================================
# 4. Cleanup on container stop (SIGTERM/SIGINT)
# ============================================================
cleanup() {
  echo ""
  echo "=== Shutting down services ==="

  # Stop supervisors first
  kill -TERM "${VLLM_SUP_PID:-}" "${ONWARDS_SUP_PID:-}" 2>/dev/null || true

  # Then stop children
  kill -TERM "${ONWARDS_PID:-}" "${VLLM_PID:-}" "${SSH_PID:-}" 2>/dev/null || true
  sleep 2
  kill -KILL "${ONWARDS_PID:-}" "${VLLM_PID:-}" "${SSH_PID:-}" 2>/dev/null || true

  echo "All services stopped"
  exit 0
}

trap cleanup SIGTERM SIGINT

echo "=== All services starting ==="
echo "SSH daemon: PID $SSH_PID"
echo "vLLM supervisor: PID $VLLM_SUP_PID"
echo "Onwards supervisor: PID $ONWARDS_SUP_PID"
echo ""
echo "Container is ready! You can:"
echo "  - SSH to port $SSH_PORT"
echo "  - Access vLLM API on port $VLLM_PORT (when running)"
echo "  - Access Onwards proxy on port $ONWARDS_PORT (when running)"
echo ""

# Keep PID 1 alive by waiting on SSH (if SSH dies, container exits)
wait "$SSH_PID"
echo "SSH daemon exited; shutting down..."
cleanup