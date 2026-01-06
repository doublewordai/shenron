#!/bin/bash
set -e

# Default values
MODELNAME=${MODELNAME:-"Qwen/Qwen3-0.6B"}
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

if [ -n "$PUBLIC_KEY" ]; then
    printf '%s\n' "$PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "SSH public key configured"
fi

if [ -n "$SSH_PORT" ]; then
    sed -i '/^[#[:space:]]*Port /d' /etc/ssh/sshd_config
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

echo "Starting SSH server on port $SSH_PORT"
/usr/sbin/sshd -D -e &
SSH_PID=$!
echo "SSH daemon started with PID $SSH_PID"

# ============================================================
# 2. Create Onwards Config and Start Onwards
# ============================================================
echo "=== Setting up Onwards proxy ==="

mkdir -p /etc/onwards

# Create onwards configuration
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
echo "Waiting for vLLM to be ready before starting onwards..."

# Function to check if vLLM is ready
wait_for_vllm() {
    echo "Checking if vLLM is ready on port $VLLM_PORT..."
    for i in $(seq 1 $WAIT_ATTEMPTS); do
        if curl -s "http://localhost:$VLLM_PORT/health" >/dev/null 2>&1 || \
           curl -s "http://localhost:$VLLM_PORT/v1/models" >/dev/null 2>&1; then
            echo "vLLM is ready!"
            return 0
        fi
        echo "Waiting for vLLM... (attempt $i/60)"
        sleep 5
    done
    echo "Warning: vLLM did not become ready in time, starting onwards anyway"
    return 1
}

# Start onwards in background after vLLM check
(
    wait_for_vllm
    echo "Starting onwards on port $ONWARDS_PORT"
    exec onwards --targets /etc/onwards/config.json --port $ONWARDS_PORT
) &
ONWARDS_PID=$!
echo "Onwards will start with PID $ONWARDS_PID after vLLM is ready"

# ============================================================
# 3. Start vLLM Server
# ============================================================
echo "=== Starting vLLM server ==="

# Activate the Python environment
source /opt/pagellm/.venv/bin/activate

# Standard vLLM parameters (you can edit these as needed)
VLLM_ARGS=(
    --model "$MODELNAME"
    --port "$VLLM_PORT"
    --host "127.0.0.1"
    --served-model-name "$MODELNAME"
    --max-model-len 8192
    --gpu-memory-utilization 0.75
    --tensor-parallel-size 1
    --pipeline-parallel-size 1
    --trust-remote-code
)

echo "Starting vLLM with model: $MODELNAME on port $VLLM_PORT"
echo "Command: vllm serve ${VLLM_ARGS[*]}"

# Start vLLM in background
vllm serve "${VLLM_ARGS[@]}" &
VLLM_PID=$!
echo "vLLM started with PID $VLLM_PID"

# ============================================================
# 4. Process Management and Cleanup
# ============================================================

# Function to handle shutdown
cleanup() {
    echo ""
    echo "=== Shutting down services ==="
    
    if [ -n "$ONWARDS_PID" ] && kill -0 "$ONWARDS_PID" 2>/dev/null; then
        echo "Stopping onwards (PID $ONWARDS_PID)..."
        kill -TERM "$ONWARDS_PID" 2>/dev/null || true
    fi
    
    if [ -n "$VLLM_PID" ] && kill -0 "$VLLM_PID" 2>/dev/null; then
        echo "Stopping vLLM (PID $VLLM_PID)..."
        kill -TERM "$VLLM_PID" 2>/dev/null || true
    fi
    
    if [ -n "$SSH_PID" ] && kill -0 "$SSH_PID" 2>/dev/null; then
        echo "Stopping SSH daemon (PID $SSH_PID)..."
        kill -TERM "$SSH_PID" 2>/dev/null || true
    fi
    
    # Wait for graceful shutdown
    sleep 2
    
    # Force kill if still running
    for pid in "$ONWARDS_PID" "$VLLM_PID" "$SSH_PID"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    
    echo "All services stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

echo "=== All services starting ==="
echo "SSH daemon: PID $SSH_PID"
echo "vLLM server: PID $VLLM_PID" 
echo "Onwards proxy: Will start after vLLM is ready"
echo ""
echo "Container is ready! You can:"
echo "  - SSH to port $SSH_PORT"
echo "  - Access vLLM API on port $VLLM_PORT"
echo "  - Access Onwards proxy on port $ONWARDS_PORT"
echo ""
echo "Press Ctrl+C to stop all services"

# Keep the script running and wait for any process to exit
wait_for_any_exit() {
    while true; do
        # Check if any critical process has exited
        if ! kill -0 "$VLLM_PID" 2>/dev/null; then
            echo "vLLM process has exited, shutting down..."
            break
        fi
        if ! kill -0 "$SSH_PID" 2>/dev/null; then
            echo "SSH daemon has exited, shutting down..."
            break
        fi
        sleep 5
    done
}

wait_for_any_exit
cleanup