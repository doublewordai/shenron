#!/bin/bash
# Simple release workflow for Shenron
# Usage: ./scripts/release.sh [major|minor|patch] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    echo "Usage: $0 [major|minor|patch] [options]"
    echo ""
    echo "This script combines version bumping and Docker image building:"
    echo "  1. Bumps the version (major/minor/patch)"
    echo "  2. Creates git commit and tag"
    echo "  3. Builds Docker images for all CUDA versions, plus onwards & prometheus"
    echo "  4. Optionally pushes to registry"
    echo ""
    echo "Options:"
    echo "  --push         Push Docker images to registry"
    echo "  --latest       Also tag as 'latest'"
    echo "  --registry REG Docker registry (default: docker.io)"
    echo "  --dry-run      Show what would be done without making changes"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 patch                    # Bump patch version and build locally"
    echo "  $0 minor --push --latest    # Bump minor, build and push with latest tag"
    echo "  $0 major --dry-run          # Show what major release would do"
}

main() {
    local bump_type=""
    local build_args=""
    local dry_run="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            major|minor|patch)
                if [ -n "$bump_type" ]; then
                    print_error "Multiple bump types specified"
                    show_usage
                    exit 1
                fi
                bump_type="$1"
                shift
                ;;
            --push|--latest|--registry|--dry-run)
                build_args="$build_args $1"
                if [ "$1" = "--dry-run" ]; then
                    dry_run="true"
                fi
                if [ "$1" = "--registry" ]; then
                    build_args="$build_args $2"
                    shift
                fi
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
    
    if [ -z "$bump_type" ]; then
        print_error "Bump type required"
        show_usage
        exit 1
    fi
    
    print_info "Shenron Release Workflow"
    echo "========================"
    echo ""
    
    # Step 1: Bump version
    print_info "Step 1: Bumping version..."
    local version_args="$bump_type"
    if [ "$dry_run" = "true" ]; then
        version_args="$version_args --dry-run"
    fi
    
    if ! "$SCRIPT_DIR/bump-version.sh" $version_args; then
        print_error "Version bump failed"
        exit 1
    fi
    
    echo ""
    
    # Step 2: Build and optionally push Docker images
    print_info "Step 2: Building Docker images..."
    
    if ! "$SCRIPT_DIR/build-release.sh" $build_args; then
        print_error "Docker build failed"
        exit 1
    fi
    
    echo ""
    
    if [ "$dry_run" = "true" ]; then
        print_success "Dry run completed successfully!"
        print_info "Run without --dry-run to perform actual release"
    else
        print_success "Release completed successfully!"
        print_info "Don't forget to push git changes:"
        
        # Get the new version to show correct commands
        local version=$(cat "$SCRIPT_DIR/../VERSION" | tr -d '[:space:]')
        echo "  git push origin main"
        echo "  git push origin v$version"
    fi
}

main "$@"