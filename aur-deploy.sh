#!/bin/bash
set -euo pipefail

# AUR Deployment Script for Claude Desktop
# This script helps deploy the package to AUR

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# Configuration
AUR_PACKAGE_NAME="claude-desktop-bin"
AUR_REPO_URL="ssh://aur@aur.archlinux.org/${AUR_PACKAGE_NAME}.git"

# Check prerequisites
check_prerequisites() {
    # Check for git
    if ! command -v git &>/dev/null; then
        log_error "git is not installed"
    fi

    # Check for SSH key
    if [ ! -f "$HOME/.ssh/aur" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
        log_error "No SSH key found for AUR. Please set up AUR SSH access first."
    fi

    # Check for makepkg
    if ! command -v makepkg &>/dev/null; then
        log_error "makepkg is not installed"
    fi

    log_info "Prerequisites check passed"
}

# Setup AUR SSH config
setup_ssh_config() {
    if ! grep -q "aur.archlinux.org" "$HOME/.ssh/config" 2>/dev/null; then
        log_info "Setting up SSH config for AUR..."
        cat >> "$HOME/.ssh/config" << EOF

Host aur.archlinux.org
    IdentityFile ~/.ssh/aur
    User aur
EOF
        chmod 600 "$HOME/.ssh/config"
    fi
}

# Get current version from build
get_current_version() {
    local pkg_file=$(find . -maxdepth 1 -name "claude-desktop-*.pkg.tar.*" | head -1)
    if [ -z "$pkg_file" ]; then
        log_error "No package file found. Please run build2.sh first."
    fi

    local version=$(echo "$pkg_file" | grep -oP 'claude-desktop-\K[0-9]+\.[0-9]+\.[0-9]+')
    if [ -z "$version" ]; then
        log_error "Cannot extract version from package file"
    fi

    echo "$version"
}

# Clone or update AUR repository
prepare_aur_repo() {
    local repo_dir="aur-${AUR_PACKAGE_NAME}"

    if [ -d "$repo_dir" ]; then
        log_info "Updating existing AUR repository..."
        cd "$repo_dir"
        git pull origin master || true
        cd ..
    else
        log_info "Cloning AUR repository..."
        git clone "$AUR_REPO_URL" "$repo_dir" || {
            log_warn "Repository doesn't exist on AUR. Creating new repository..."
            mkdir -p "$repo_dir"
            cd "$repo_dir"
            git init
            git remote add origin "$AUR_REPO_URL"
            cd ..
        }
    fi

    echo "$repo_dir"
}

# Update PKGBUILD with version
update_pkgbuild() {
    local repo_dir="$1"
    local version="$2"

    log_info "Updating PKGBUILD with version $version..."

    # Copy template and update version
    cp PKGBUILD.template "$repo_dir/PKGBUILD"
    sed -i "s/VERSION_PLACEHOLDER/$version/g" "$repo_dir/PKGBUILD"

    # Generate .SRCINFO
    cd "$repo_dir"
    makepkg --printsrcinfo > .SRCINFO
    cd ..

    log_info "PKGBUILD and .SRCINFO updated"
}

# Commit and push to AUR
deploy_to_aur() {
    local repo_dir="$1"
    local version="$2"

    cd "$repo_dir"

    # Configure git if needed
    if [ -z "$(git config user.name)" ]; then
        log_warn "Git user not configured. Using defaults..."
        git config user.name "Claude Desktop Maintainer"
        git config user.email "maintainer@example.com"
    fi

    # Check for changes
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes to deploy"
        return 0
    fi

    # Commit changes
    git add PKGBUILD .SRCINFO
    git commit -m "Update to version $version

- Automated deployment via aur-deploy.sh
- Built from upstream Claude Desktop Windows installer"

    # Push to AUR
    log_info "Pushing to AUR..."
    if git push origin master; then
        log_info "Successfully deployed to AUR!"
    else
        # Try to push to HEAD:master if master doesn't exist
        git push origin HEAD:master || log_error "Failed to push to AUR"
    fi

    cd ..
}

# Verify deployment
verify_deployment() {
    local version="$1"

    log_info "Verifying deployment..."

    # Wait a moment for AUR to process
    sleep 2

    # Check if package is available (this is a basic check)
    if curl -s "https://aur.archlinux.org/packages/${AUR_PACKAGE_NAME}" | grep -q "$version"; then
        log_info "Package version $version is now available on AUR!"
        log_info "Users can install with: yay -S ${AUR_PACKAGE_NAME}"
    else
        log_warn "Package may take a few minutes to appear on AUR"
    fi
}

# Main deployment process
main() {
    log_info "Starting AUR deployment for Claude Desktop"

    check_prerequisites
    setup_ssh_config

    # Get version
    local version=$(get_current_version)
    log_info "Deploying version: $version"

    # Prepare repository
    local repo_dir=$(prepare_aur_repo)

    # Update files
    update_pkgbuild "$repo_dir" "$version"

    # Deploy
    read -p "Ready to deploy to AUR. Continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_to_aur "$repo_dir" "$version"
        verify_deployment "$version"
    else
        log_info "Deployment cancelled"
    fi

    log_info "Done!"
}

# Parse arguments
case "${1:-}" in
    --help|-h)
        cat << EOF
AUR Deployment Script for Claude Desktop

Usage: $0 [OPTIONS]

This script deploys the Claude Desktop package to the Arch User Repository (AUR).

Prerequisites:
1. AUR account with SSH key configured
2. Package built with build2.sh
3. PKGBUILD.template in current directory

Setup SSH for AUR:
1. Generate SSH key: ssh-keygen -f ~/.ssh/aur
2. Add public key to AUR: https://aur.archlinux.org/account
3. Run this script

Options:
  -h, --help    Show this help message

EOF
        exit 0
        ;;
esac

main