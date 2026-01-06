#!/bin/bash
# Build and release script for Shenron Docker containers
# Usage: ./scripts/build-release.sh [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

# Default values
REGISTRY=""
REPOSITORY="tytn/shenron"
PLATFORMS="linux/amd64"
BUILD_ARGS=""
PUSH="false"
LATEST="false"
DRY_RUN="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --push                Push images to registry after building"
    echo "  --latest              Also tag as 'latest'"
    echo "  --registry REGISTRY   Docker registry (default: docker.io)"
    echo "  --repo REPOSITORY     Repository name (default: $REPOSITORY)"
    echo "  --platforms PLATFORMS Build platforms (default: $PLATFORMS)"
    echo "  --cuda-version VER    CUDA version to build (126, 129, or 'all')"
    echo "  --build-arg ARG       Additional build arguments"
    echo "  --dry-run            Show what would be built without building"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Build locally"
    echo "  $0 --push --latest           # Build and push with latest tag"
    echo "  $0 --cuda-version 126 --push # Build only CUDA 12.6 version"
    echo "  $0 --platforms linux/amd64,linux/arm64 --push # Multi-platform build"
}

# Function to get current version
get_current_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        print_error "VERSION file not found at: $VERSION_FILE"
        print_info "Run ./scripts/bump-version.sh first"
        exit 1
    fi
    
    local version=$(cat "$VERSION_FILE" | tr -d '[:space:]')
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid version format in VERSION file: $version"
        exit 1
    fi
    echo "$version"
}

# Function to check if docker buildx is available
check_docker_buildx() {
    if ! docker buildx version >/dev/null 2>&1; then
        print_error "Docker buildx is required but not available"
        print_info "Please install Docker buildx or use Docker Desktop"
        exit 1
    fi
}

# Function to check if we're logged into the registry
check_docker_login() {
    local registry="$1"
    local push="$2"
    
    if [ "$push" != "true" ]; then
        return 0
    fi
    
    if [ -n "$registry" ] && [ "$registry" != "docker.io" ]; then
        print_info "Checking authentication for registry: $registry"
        if ! docker buildx imagetools inspect "$registry/hello-world:latest" >/dev/null 2>&1; then
            print_warning "Not authenticated with registry: $registry"
            print_info "Please login with: docker login $registry"
        fi
    fi
}

# Function to build Docker image
build_docker_image() {
    local version="$1"
    local cuda_version="$2"
    local dockerfile="$3"
    local push="$4"
    local latest="$5"
    local dry_run="$6"
    local platforms="$7"
    local registry="$8"
    local repository="$9"
    local build_args="${10}"
    
    local image_name="$repository"
    if [ -n "$registry" ]; then
        image_name="$registry/$repository"
    fi
    
    local cuda_suffix=""
    if [ "$cuda_version" != "default" ]; then
        cuda_suffix="-cu$cuda_version"
    fi
    
    local tags=(
        "$image_name:$version$cuda_suffix"
    )
    
    if [ "$latest" = "true" ]; then
        tags+=("$image_name:latest$cuda_suffix")
    fi
    
    # Build tag arguments
    local tag_args=""
    for tag in "${tags[@]}"; do
        tag_args="$tag_args --tag $tag"
    done
    
    # Build platform arguments
    local platform_args=""
    if [ -n "$platforms" ]; then
        platform_args="--platform $platforms"
    fi
    
    # Build push arguments
    local push_args=""
    if [ "$push" = "true" ]; then
        push_args="--push"
    else
        push_args="--load"
    fi
    
    # Build the command
    local build_cmd="docker buildx build"
    build_cmd="$build_cmd --file $dockerfile"
    build_cmd="$build_cmd $tag_args"
    build_cmd="$build_cmd $platform_args"
    build_cmd="$build_cmd $push_args"
    build_cmd="$build_cmd $build_args"
    build_cmd="$build_cmd $ROOT_DIR"
    
    print_info "Building Docker image for CUDA $cuda_version:"
    print_info "  Dockerfile: $dockerfile"
    print_info "  Tags: ${tags[*]}"
    print_info "  Platforms: $platforms"
    
    if [ "$dry_run" = "true" ]; then
        print_info "Would run: $build_cmd"
        return 0
    fi
    
    print_info "Running: $build_cmd"
    if eval "$build_cmd"; then
        print_success "Successfully built Docker image for CUDA $cuda_version"
        
        if [ "$push" = "true" ]; then
            print_success "Successfully pushed to registry"
        else
            print_success "Image built locally (use --push to push to registry)"
        fi
        
        print_info "Built tags:"
        for tag in "${tags[@]}"; do
            echo "  - $tag"
        done
    else
        print_error "Failed to build Docker image for CUDA $cuda_version"
        exit 1
    fi
}

# Function to get git commit info
get_git_info() {
    local commit_hash=""
    local branch=""
    local is_dirty="false"
    
    if git -C "$ROOT_DIR" rev-parse HEAD >/dev/null 2>&1; then
        commit_hash=$(git -C "$ROOT_DIR" rev-parse --short HEAD)
        branch=$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || echo "unknown")
        
        if ! git -C "$ROOT_DIR" diff --quiet || ! git -C "$ROOT_DIR" diff --cached --quiet; then
            is_dirty="true"
        fi
    fi
    
    echo "commit_hash=$commit_hash branch=$branch is_dirty=$is_dirty"
}

# Main function
main() {
    local cuda_versions=("126" "129")
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --push)
                PUSH="true"
                shift
                ;;
            --latest)
                LATEST="true"
                shift
                ;;
            --registry)
                REGISTRY="$2"
                shift 2
                ;;
            --repo)
                REPOSITORY="$2"
                shift 2
                ;;
            --platforms)
                PLATFORMS="$2"
                shift 2
                ;;
            --cuda-version)
                case "$2" in
                    "126"|"129")
                        cuda_versions=("$2")
                        ;;
                    "all")
                        cuda_versions=("126" "129")
                        ;;
                    *)
                        print_error "Invalid CUDA version: $2 (supported: 126, 129, all)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --build-arg)
                BUILD_ARGS="$BUILD_ARGS --build-arg $2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Get version and git info
    local version
    version=$(get_current_version)
    
    eval "$(get_git_info)"
    
    # Add git metadata as build args
    if [ -n "$commit_hash" ]; then
        BUILD_ARGS="$BUILD_ARGS --build-arg GIT_COMMIT=$commit_hash"
        BUILD_ARGS="$BUILD_ARGS --build-arg GIT_BRANCH=$branch"
        BUILD_ARGS="$BUILD_ARGS --build-arg VERSION=$version"
    fi
    
    # Check prerequisites
    check_docker_buildx
    check_docker_login "$REGISTRY" "$PUSH"
    
    # Show summary
    echo ""
    print_info "Build Summary:"
    echo "  Version: $version"
    echo "  Registry: ${REGISTRY:-docker.io}"
    echo "  Repository: $REPOSITORY"
    echo "  CUDA versions: ${cuda_versions[*]}"
    echo "  Platforms: $PLATFORMS"
    echo "  Push to registry: $PUSH"
    echo "  Tag as latest: $LATEST"
    echo "  Dry run: $DRY_RUN"
    if [ -n "$commit_hash" ]; then
        echo "  Git commit: $commit_hash"
        echo "  Git branch: $branch"
        if [ "$is_dirty" = "true" ]; then
            print_warning "  Working directory has uncommitted changes"
        fi
    fi
    echo ""
    
    # Confirm unless dry run
    if [ "$DRY_RUN" != "true" ]; then
        read -p "Proceed with build? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Build cancelled"
            exit 1
        fi
    fi
    
    # Build each CUDA version
    for cuda_version in "${cuda_versions[@]}"; do
        local dockerfile="$ROOT_DIR/docker/Dockerfile.cu$cuda_version"
        
        if [ ! -f "$dockerfile" ]; then
            print_error "Dockerfile not found: $dockerfile"
            continue
        fi
        
        build_docker_image \
            "$version" \
            "$cuda_version" \
            "$dockerfile" \
            "$PUSH" \
            "$LATEST" \
            "$DRY_RUN" \
            "$PLATFORMS" \
            "$REGISTRY" \
            "$REPOSITORY" \
            "$BUILD_ARGS"
        
        echo ""
    done
    
    if [ "$DRY_RUN" = "true" ]; then
        print_success "Dry run completed successfully"
    else
        print_success "All builds completed successfully!"
        
        if [ "$PUSH" = "true" ]; then
            print_info "Images pushed to registry:"
            for cuda_version in "${cuda_versions[@]}"; do
                local image_name="$REPOSITORY"
                if [ -n "$REGISTRY" ]; then
                    image_name="$REGISTRY/$REPOSITORY"
                fi
                echo "  - $image_name:$version-cu$cuda_version"
                if [ "$LATEST" = "true" ]; then
                    echo "  - $image_name:latest-cu$cuda_version"
                fi
            done
        else
            print_info "To push images to registry, run with --push flag"
        fi
    fi
}

main "$@"