# Version Management and Release Scripts

This directory contains scripts to manage versions and releases for the Shenron Docker containers.

## Overview

The version management system uses semantic versioning (MAJOR.MINOR.PATCH) and provides three main scripts:

- `bump-version.sh` - Manages version bumping and git tagging
- `build-release.sh` - Builds and pushes Docker containers
- `release.sh` - Combined workflow for version bump + Docker build

## Quick Start

### 1. Simple Release (recommended)

```bash
# Patch release (bug fixes)
./scripts/release.sh patch

# Minor release (new features)
./scripts/release.sh minor --push --latest

# Major release (breaking changes)
./scripts/release.sh major --push --latest
```

### 2. Individual Steps

```bash
# Bump version only
./scripts/bump-version.sh patch

# Build Docker images only
./scripts/build-release.sh --push --latest
```

## Scripts

### `bump-version.sh`

Manages semantic versioning with git integration.

**Usage:**
```bash
./scripts/bump-version.sh [major|minor|patch] [options]
```

**Options:**
- `--dry-run` - Show what would be done
- `--no-git` - Don't create git commit/tag
- `--help` - Show help

**Examples:**
```bash
./scripts/bump-version.sh patch              # 1.2.3 → 1.2.4
./scripts/bump-version.sh minor              # 1.2.3 → 1.3.0
./scripts/bump-version.sh major              # 1.2.3 → 2.0.0
./scripts/bump-version.sh patch --dry-run    # Preview changes
```

### `build-release.sh`

Builds Docker containers for different CUDA versions, plus the `onwards` and `prometheus` containers.

**Usage:**
```bash
./scripts/build-release.sh [options]
```

**Options:**
- `--push` - Push to registry after building
- `--latest` - Also tag as 'latest'
- `--registry REGISTRY` - Custom registry (default: docker.io)
- `--repo REPOSITORY` - Repository name
- `--cuda-version VER` - Build specific CUDA version (126, 129, 130, or 'all')
- `--platforms PLATFORMS` - Target platforms
- `--build-arg ARG` - Additional build arguments
- `--dry-run` - Show what would be built

**Examples:**
```bash
./scripts/build-release.sh                           # Build locally
./scripts/build-release.sh --push --latest           # Build and push with latest tag
./scripts/build-release.sh --cuda-version 126 --push # Build only CUDA 12.6
./scripts/build-release.sh --dry-run                 # Preview build
```

### `release.sh`

Combined workflow that bumps version and builds containers.

**Usage:**
```bash
./scripts/release.sh [major|minor|patch] [options]
```

**Options:**
- `--push` - Push Docker images
- `--latest` - Tag as latest
- `--registry REG` - Custom registry
- `--dry-run` - Preview entire workflow

**Examples:**
```bash
./scripts/release.sh patch                    # Bump patch + build locally
./scripts/release.sh minor --push --latest    # Full minor release
./scripts/release.sh major --dry-run          # Preview major release
```

## Workflow

### Standard Release Process

1. **Make your changes** and commit them
2. **Choose version bump type:**
   - `patch` - Bug fixes, small changes
   - `minor` - New features, backwards compatible
   - `major` - Breaking changes
3. **Run release script:**
   ```bash
   ./scripts/release.sh minor --push --latest
   ```
4. **Push git changes:**
   ```bash
   git push origin main
   git push origin v1.2.0  # Use actual version
   ```

### Development Workflow

```bash
# Preview what a release would do
./scripts/release.sh patch --dry-run

# Build only locally for testing
./scripts/build-release.sh

# Build specific CUDA version
./scripts/build-release.sh --cuda-version 126

# Test version bump without git operations
./scripts/bump-version.sh patch --no-git --dry-run
```

## Docker Images

The build system creates images with the following naming conventions:

```
tytn/shenron:VERSION-cuCUDA
tytn/shenron:VERSION-onwards
tytn/shenron:VERSION-prometheus
```

**Examples:**
- `tytn/shenron:1.2.3-cu126`
- `tytn/shenron:1.2.3-cu129`
- `tytn/shenron:1.2.3-cu130`
- `tytn/shenron:1.2.3-onwards`
- `tytn/shenron:1.2.3-prometheus`
- `tytn/shenron:latest-cu126`
- `tytn/shenron:latest-onwards`

## Configuration

### Default Settings

- **Registry:** `docker.io`
- **Repository:** `tytn/shenron`
- **CUDA Versions:** 126, 129, 130
- **Platforms:** `linux/amd64`

### Custom Registry

```bash
# Build for custom registry
./scripts/build-release.sh --registry my-registry.com --push

# Full release to custom registry
./scripts/release.sh minor --registry my-registry.com --push --latest
```

## Prerequisites

- Docker with buildx support
- Git repository with proper permissions
- Docker registry authentication (for --push)

## Version File

The current version is stored in the root `VERSION` file:

```
$ cat VERSION
1.2.3
```

This file is automatically updated by the version bump script and used by the build script for tagging.

## Git Integration

- Creates semantic git tags (e.g., `v1.2.3`)
- Commits version file changes
- Checks for uncommitted changes
- Validates tag uniqueness

## Troubleshooting

### "VERSION file not found"
Run the bump-version script first: `./scripts/bump-version.sh patch`

### "Not authenticated with registry"
Login to Docker registry: `docker login` or `docker login my-registry.com`

### "Tag already exists"
The version tag already exists in git. Use a different version or delete the existing tag.

### Build fails
Check that all Dockerfiles exist and Docker buildx is properly configured.