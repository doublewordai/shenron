#!/bin/bash
# Version management script for Shenron
# Usage: ./scripts/bump-version.sh [major|minor|patch]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

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
    echo "Usage: $0 [major|minor|patch] [options]"
    echo ""
    echo "Version bump types:"
    echo "  major   - Increment major version (x.0.0)"
    echo "  minor   - Increment minor version (0.x.0)"
    echo "  patch   - Increment patch version (0.0.x)"
    echo ""
    echo "Options:"
    echo "  --dry-run     Show what would be done without making changes"
    echo "  --no-git     Don't create git commit and tag"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 patch              # Bump patch version and commit"
    echo "  $0 minor --dry-run    # Show what minor bump would do"
    echo "  $0 major --no-git     # Bump major version without git operations"
}

# Function to validate version format
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid version format: $version (expected: x.y.z)"
        exit 1
    fi
}

# Function to get current version
get_current_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        print_error "VERSION file not found at: $VERSION_FILE"
        exit 1
    fi
    
    local version=$(cat "$VERSION_FILE" | tr -d '[:space:]')
    validate_version "$version"
    echo "$version"
}

# Function to bump version
bump_version() {
    local current_version="$1"
    local bump_type="$2"
    
    IFS='.' read -r major minor patch <<< "$current_version"
    
    case "$bump_type" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
        *)
            print_error "Invalid bump type: $bump_type"
            show_usage
            exit 1
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to check git status
check_git_status() {
    if ! git -C "$ROOT_DIR" diff --quiet || ! git -C "$ROOT_DIR" diff --cached --quiet; then
        print_warning "Working directory has uncommitted changes"
        print_info "Current git status:"
        git -C "$ROOT_DIR" status --short
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted"
            exit 1
        fi
    fi
}

# Function to check if tag exists
check_tag_exists() {
    local version="$1"
    local tag="v$version"
    
    if git -C "$ROOT_DIR" tag | grep -q "^$tag$"; then
        print_error "Tag $tag already exists"
        print_info "Existing tags:"
        git -C "$ROOT_DIR" tag | sort -V | tail -5
        exit 1
    fi
}

# Function to update version file
update_version_file() {
    local new_version="$1"
    local dry_run="$2"
    
    if [ "$dry_run" = "true" ]; then
        print_info "Would update VERSION file to: $new_version"
    else
        echo "$new_version" > "$VERSION_FILE"
        print_success "Updated VERSION file to: $new_version"
    fi
}

# Function to create git commit and tag
create_git_commit_and_tag() {
    local version="$1"
    local dry_run="$2"
    local no_git="$3"
    
    if [ "$no_git" = "true" ]; then
        print_info "Skipping git operations (--no-git)"
        return
    fi
    
    local tag="v$version"
    local commit_msg="Bump version to $version"
    
    if [ "$dry_run" = "true" ]; then
        print_info "Would create git commit: '$commit_msg'"
        print_info "Would create git tag: '$tag'"
    else
        # Add VERSION file
        git -C "$ROOT_DIR" add "$VERSION_FILE"
        
        # Create commit
        git -C "$ROOT_DIR" commit -m "$commit_msg"
        print_success "Created git commit: '$commit_msg'"
        
        # Create tag
        git -C "$ROOT_DIR" tag -a "$tag" -m "Release $version"
        print_success "Created git tag: '$tag'"
        
        print_info "To push changes run:"
        print_info "  git push origin main && git push origin $tag"
    fi
}

# Main function
main() {
    local bump_type=""
    local dry_run="false"
    local no_git="false"
    
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
            --dry-run)
                dry_run="true"
                shift
                ;;
            --no-git)
                no_git="true"
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
    
    # Validate arguments
    if [ -z "$bump_type" ]; then
        print_error "Bump type required"
        show_usage
        exit 1
    fi
    
    # Get current version
    local current_version
    current_version=$(get_current_version)
    print_info "Current version: $current_version"
    
    # Calculate new version
    local new_version
    new_version=$(bump_version "$current_version" "$bump_type")
    print_info "New version: $new_version"
    
    # Check git status (unless --no-git)
    if [ "$no_git" != "true" ] && [ "$dry_run" != "true" ]; then
        check_git_status
        check_tag_exists "$new_version"
    fi
    
    # Show summary
    echo ""
    print_info "Summary:"
    echo "  Current version: $current_version"
    echo "  New version:     $new_version"
    echo "  Bump type:       $bump_type"
    echo "  Dry run:         $dry_run"
    echo "  Skip git:        $no_git"
    echo ""
    
    # Confirm unless dry run
    if [ "$dry_run" != "true" ]; then
        read -p "Proceed with version bump? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted"
            exit 1
        fi
    fi
    
    # Update version file
    update_version_file "$new_version" "$dry_run"
    
    # Create git commit and tag
    create_git_commit_and_tag "$new_version" "$dry_run" "$no_git"
    
    if [ "$dry_run" = "true" ]; then
        print_success "Dry run completed successfully"
        print_info "Run without --dry-run to make actual changes"
    else
        print_success "Version bumped successfully to $new_version"
        print_info "Next steps:"
        print_info "  1. Review the changes"
        print_info "  2. Push to remote: git push origin main && git push origin v$new_version"
        print_info "  3. Build and release: ./scripts/build-release.sh"
    fi
}

main "$@"