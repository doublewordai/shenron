docker run --gpus all -it -p 3000:3000 \
  --env-file $(pwd)/docker/.env \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -v $(pwd)/docker/entrypoint.sh:/entrypoint.sh \
  --entrypoint /bin/bash \
  tytn/shenron:0.1.0-cu126 \
  -c "chmod +x /entrypoint.sh && /entrypoint.sh"