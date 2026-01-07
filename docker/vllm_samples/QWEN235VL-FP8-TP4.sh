VLLM_USE_FLASHINFER_MOE_FP8=1 \
VLLM_FLASHINFER_MOE_BACKEND=throughput \
vllm serve Qwen/Qwen3-VL-235B-A22B-Instruct-FP8 \
  --tensor-parallel-size 4 \
  --limit-mm-per-prompt.video 0 \
  --async-scheduling \
  --gpu-memory-utilization 0.95 \
  --max-num-seqs 128 \
  --log-level info \
  > /var/log/vllm.log 2>&1 &
 