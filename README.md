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
wget https://github.com/doublewordai/shenron/releases/download/v0.5.3/Qwen06B-cu126-TP1.yml
shenron .
docker compose up -d
```

`shenron .` expects exactly one config YAML (`*.yml` or `*.yaml`) in the current directory, unless you pass a config file path directly.

## Configs

Repo configs are stored in `configs/`.

Current starter config:
- `configs/Qwen06B-cu126-TP1.yml`

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
- `python-release.yaml` builds/publishes the `shenron` package to PyPI on release tags.
- Docker image build/push via Depot remains in `ci.yaml` and still triggers when `docker/Dockerfile.cu*` or `VERSION` changes.

## License

MIT, see `LICENSE`.
