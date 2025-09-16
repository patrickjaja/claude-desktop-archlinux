#!/bin/bash

# Test script to verify AUR deployment locally
# This simulates what the GitHub Action does

set -e

echo "=== Testing AUR Deployment Setup ==="

# Set credentials (same as GitHub secrets)
export AUR_USERNAME="patrickjaja"
export AUR_EMAIL="patrickjajaa@gmail.com"
export AUR_SSH_KEY_PATH="/home/patrickjaja/.ssh/aur_private_key"

# Create temp directory for testing
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
echo "Working in: $TEMP_DIR"

# Setup SSH for AUR
echo "=== Setting up SSH ==="
mkdir -p ~/.ssh

# Copy the key to test location
cp "$AUR_SSH_KEY_PATH" ~/.ssh/aur_test
chmod 600 ~/.ssh/aur_test

# Add AUR host key if not already present
ssh-keyscan -t rsa,ecdsa,ed25519 aur.archlinux.org >> ~/.ssh/known_hosts 2>/dev/null

# Create SSH config for this test
cat > ~/.ssh/config_aur_test <<EOF
Host aur-test
  HostName aur.archlinux.org
  User aur
  IdentityFile ~/.ssh/aur_test
  StrictHostKeyChecking no
  IdentitiesOnly yes
  PubkeyAuthentication yes
  PasswordAuthentication no
EOF

# Test SSH connection
echo "=== Testing SSH connection ==="
ssh -F ~/.ssh/config_aur_test -T aur-test 2>&1 | head -5 || true

# Test git access
echo "=== Testing git ls-remote ==="
GIT_SSH_COMMAND="ssh -F ~/.ssh/config_aur_test -i ~/.ssh/aur_test" git ls-remote ssh://aur@aur.archlinux.org/claude-desktop-bin.git 2>&1 | head -10 || true

# Configure git
git config --global user.name "$AUR_USERNAME"
git config --global user.email "$AUR_EMAIL"

# Try to clone the repository
echo "=== Testing clone ==="
export GIT_SSH_COMMAND="ssh -i ~/.ssh/aur_test -o StrictHostKeyChecking=no"
if git clone ssh://aur@aur.archlinux.org/claude-desktop-bin.git aur-test-repo 2>&1; then
    echo "✓ Clone successful!"
    cd aur-test-repo
    echo "Current files in repo:"
    ls -la

    # Test if we can fetch
    echo "=== Testing fetch ==="
    if git fetch 2>&1; then
        echo "✓ Fetch successful!"
    else
        echo "✗ Fetch failed"
    fi
else
    echo "✗ Clone failed - repository may not exist yet or SSH key not authorized"

    # Try creating a new repo
    echo "=== Testing new repo creation ==="
    mkdir aur-test-repo
    cd aur-test-repo
    git init
    git remote add origin ssh://aur@aur.archlinux.org/claude-desktop-bin.git

    # Create test files
    echo "# Test PKGBUILD" > PKGBUILD
    echo "# Test .SRCINFO" > .SRCINFO

    git add PKGBUILD .SRCINFO
    git commit -m "Test commit"

    echo "=== Testing push (dry-run) ==="
    if git push --dry-run origin master 2>&1; then
        echo "✓ Push dry-run successful - SSH key is working!"
    else
        echo "✗ Push dry-run failed - check SSH key authorization"
    fi
fi

# Cleanup
echo "=== Cleanup ==="
rm -f ~/.ssh/aur_test
rm -f ~/.ssh/config_aur_test
echo "Test directory: $TEMP_DIR (not removed for inspection)"

echo "=== Test Complete ==="
echo "If all tests passed, the GitHub Action should work."
echo "If any test failed, please check:"
echo "1. SSH key is added to AUR account: https://aur.archlinux.org/account/"
echo "2. SSH key has correct permissions (600)"
echo "3. AUR username matches: $AUR_USERNAME"