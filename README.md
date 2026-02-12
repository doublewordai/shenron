# Shenron

Shenron now ships as a config-driven generator for production LLM docker-compose deployments.

`shenron` reads a model config YAML and generates:
- `docker-compose.yml`
- `.generated/onwards_config.json`
- `.generated/prometheus.yml`
- `.generated/scouter_reporter.env`
- `.generated/vllm_start.sh`

## Quick Start

```bash
uv pip install shenron
shenron get
docker compose up -d
```

`shenron get` reads a per-release config index asset, shows available configs with arrow-key selection, downloads the chosen config, and generates deployment artifacts in the current directory. You can also override config values on download with:
- `--api-key` (writes `api_key`)
- `--scouter-api-key` (writes `scouter_ingest_api_key`)
- `--scouter-colector-instance` (writes `scouter_collector_instance`)

`shenron .` still works and expects exactly one config YAML (`*.yml` or `*.yaml`) in the current directory, unless you pass a config file path directly.

## Configs

Repo configs are stored in `configs/`.

Available starter configs:
- `configs/Qwen06B-cu126-TP1.yml`
- `configs/Qwen06B-cu129-TP1.yml`
- `configs/Qwen06B-cu130-TP1.yml`
- `configs/Qwen30B-A3B-cu126-TP1.yml`
- `configs/Qwen30B-A3B-cu129-TP1.yml`
- `configs/Qwen30B-A3B-cu129-TP2.yml`
- `configs/Qwen30B-A3B-cu130-TP2.yml`
- `configs/Qwen235-A22B-cu129-TP2.yml`
- `configs/Qwen235-A22B-cu129-TP4.yml`
- `configs/Qwen235-A22B-cu130-TP2.yml`

This file uses the same defaults that were previously hardcoded in `docker/run_docker_compose.sh`.

## Generated Compose Behavior

`docker-compose.yml` is fully rendered from config values:
- model image tag from `shenron_version` + `cuda_version`
- `onwards` image tag from `onwards_version`
- service ports from config
- no `${SHENRON_VERSION}` placeholders

## Development

```bash
# Run tests (Rust + CLI + compose checks)
./scripts/ci.sh

# Install local package for manual testing
python3 -m pip install -e .

# Generate from repo config
shenron configs/Qwen06B-cu126-TP1.yml --output-dir /tmp/shenron-test
```

## Release Automation

- `release-assets.yaml` publishes stamped config files (`*.yml`) as release assets.
- `release-assets.yaml` also publishes `configs-index.txt`, which powers `shenron get`.
- `python-release.yaml` builds/publishes the `shenron` package to PyPI on release tags.
- Docker image build/push via Depot remains in `ci.yaml` and still triggers when `docker/Dockerfile.cu*` or `VERSION` changes.

## License

MIT, see `LICENSE`.
