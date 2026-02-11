# Docker Notes

The primary deployment flow is now config-first via the `shenron` CLI:

```bash
uv pip install shenron
wget https://github.com/doublewordai/shenron/releases/download/v0.5.3/Qwen06B-cu126-TP1.yml
shenron .
docker compose up -d
```

`shenron` generates `docker-compose.yml` and the `.generated/*` runtime files in your target directory.

## CUDA Images

CUDA-specific runtime images are still built from:
- `docker/Dockerfile.cu126`
- `docker/Dockerfile.cu129`
- `docker/Dockerfile.cu130`

CI continues to build and push those images through Depot when Dockerfiles or `VERSION` change.
