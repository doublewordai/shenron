# Shenron: High-Performance AI Inference Stack

Shenron is a production-ready AI inference stack designed for high-performance LLM serving. It combines a Rust-based AI Gateway with [vLLM](https://github.com/vllm-project/vllm) for efficient inference.

## Features

- **High Performance**: Optimized for CUDA 12.6/12.9 with support for NVSHMEM and DeepEP kernels.
- **AI Gateway**: Built-in [Onwards](./onwards) gateway providing an OpenAI-compatible interface with:
  - Request routing and model overrides.
  - Hot-reloading configuration.
  - Rate limiting and concurrency control.
  - Prometheus metrics.
- **Dockerized**: Ready-to-deploy Docker images with all dependencies pre-configured.
- **Production Ready**: Includes health checks, SSH debugging, and flexible environment configuration.

## Architecture

Shenron consists of two main components:

1.  **Backend (vLLM)**: Handles the heavy lifting of LLM inference, optimized with custom CUDA kernels.
2.  **Gateway (Onwards)**: A Rust-based proxy that sits in front of vLLM, providing security, monitoring, and routing logic.

## Getting Started

### Running on Prime Intellect or similar

To use this in PI we create a new template with this container and then copy `entrypoint.sh` into the start script
in the advanced section. 

### Prerequisites

- NVIDIA GPU with Compute Capability 9.0+ (H100, B200, etc.)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed.
- Docker or Podman.

### Running with Docker

You can run Shenron using the provided `run_docker.sh` script:

```bash
# Clone the repository
git clone https://github.com/doublewordai/shenron.git
cd shenron

# Start the container
./docker/run_docker.sh
```

By default, the container starts with a small Qwen model for testing. You can customize the behavior using environment variables in a `.env` file (see `docker/.env.example`).

### Downloading Docker Compose files (no git clone)

These files are always directly downloadable from GitHub:

**Latest (main branch):**

```bash
curl -fsSL https://raw.githubusercontent.com/doublewordai/shenron/main/docker/run_docker_compose.sh -o run_docker_compose.sh
curl -fsSL https://raw.githubusercontent.com/doublewordai/shenron/main/docker/docker-compose.yml -o docker-compose.yml
chmod +x run_docker_compose.sh
```

**Versioned (release assets):**

```bash
TAG=v0.1.0  # pick a release tag
curl -fsSL https://github.com/doublewordai/shenron/releases/download/${TAG}/run_docker_compose.sh -o run_docker_compose.sh
curl -fsSL https://github.com/doublewordai/shenron/releases/download/${TAG}/docker-compose.yml -o docker-compose.yml
chmod +x run_docker_compose.sh
```

**Always-latest release (no tag needed):**

```bash
curl -fsSL https://github.com/doublewordai/shenron/releases/latest/download/run_docker_compose.sh -o run_docker_compose.sh
chmod +x run_docker_compose.sh

# This script will download docker-compose.yml automatically if it's missing
./run_docker_compose.sh
```

### Environment Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `MODELNAME` | The LLM model to load (HuggingFace ID) | `Qwen/Qwen3-0.6B` |
| `APIKEY` | The API key required to access the gateway | `sk-` |
| `VLLM_PORT` | Port for the internal vLLM server | `8000` |
| `ONWARDS_PORT` | Port for the public AI Gateway | `3000` |

## Usage

Once running, you can interact with Shenron using the OpenAI API format:

```bash
curl -X POST http://localhost:3000/v1/chat/completions 
  -H "Content-Type: application/json" 
  -H "Authorization: Bearer sk-" 
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "What is Shenron?"}]
  }'
```

## Development

### Building Docker Images

Shenron provides scripts to build images for different CUDA versions:

```bash
# Build for CUDA 12.6
./scripts/build-release.sh --cuda-version 126
```

### Working on the Gateway

The gateway logic is located in the `onwards/` directory. For more details on configuring or developing the gateway, see [onwards/README.md](./onwards/README.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.