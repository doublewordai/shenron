#!/usr/bin/env bash
set -euo pipefail

export VLLM_FLASHINFER_MOE_BACKEND=throughput
exec vllm serve --model Qwen/Qwen3-0.6B --port 8000 --host 0.0.0.0 --gpu-memory-utilization 0.7 --tensor-parallel-size 1 --limit-mm-per-prompt.video 0 --scheduling-policy priority --tool-call-parser hermes --generation-config auto --override-generation-config '{"max_new_tokens":16384,"min_p":0,"presence_penalty":1.5,"temperature":0.7,"top_k":20,"top_p":0.8}' --trust-remote-code --async-scheduling --enable-auto-tool-choice
