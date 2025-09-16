#!/bin/bash
set -euo pipefail

# Simplified Arch Linux Claude Desktop Build Script
# Optimized for AUR packaging and CI/CD automation

# --- Configuration ---
readonly PACKAGE_NAME="claude-desktop"
readonly PROJECT_ROOT="$(pwd)"
readonly WORK_DIR="${PROJECT_ROOT}/build"
readonly CACHE_DIR="${PROJECT_ROOT}/.cache"

# --- Color output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# --- Architecture Detection ---
detect_architecture() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            ARCH="x86_64"
            ELECTRON_ARCH="x64"
            CLAUDE_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
            ;;
        aarch64)
            ARCH="aarch64"
            ELECTRON_ARCH="arm64"
            CLAUDE_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-arm64/Claude-Setup-arm64.exe"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            ;;
    esac
    log_info "Detected architecture: $ARCH"
}

# --- Dependency Check ---
check_dependencies() {
    local missing_cmds=()
    local missing_pkgs=()

    # Check command availability and map to packages
    command -v 7z &>/dev/null || { missing_cmds+=("7z"); missing_pkgs+=("p7zip"); }
    command -v wget &>/dev/null || { missing_cmds+=("wget"); missing_pkgs+=("wget"); }
    command -v npm &>/dev/null || { missing_cmds+=("npm"); missing_pkgs+=("npm"); }
    command -v makepkg &>/dev/null || { missing_cmds+=("makepkg"); missing_pkgs+=("base-devel"); }
    command -v convert &>/dev/null || { missing_cmds+=("convert"); missing_pkgs+=("imagemagick"); }

    # Check for asar
    if ! command -v asar &>/dev/null; then
        log_warn "asar not found, installing via npm..."
        npm install -g asar 2>/dev/null || log_error "Failed to install asar. Try: sudo npm install -g asar"
    fi

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        # Remove duplicates
        local unique_pkgs=($(printf "%s\n" "${missing_pkgs[@]}" | sort -u))
        log_error "Missing dependencies. Please install with:\n  sudo pacman -S ${unique_pkgs[*]}"
    fi

    log_info "All dependencies satisfied"
}

# --- Download Claude ---
download_claude() {
    local exe_file="${CACHE_DIR}/Claude-Setup-${ELECTRON_ARCH}.exe"
    mkdir -p "${CACHE_DIR}"

    if [ -f "$exe_file" ]; then
        log_info "Using cached Claude installer"
    else
        log_info "Downloading Claude Desktop installer..."
        wget -q --show-progress -O "$exe_file" "$CLAUDE_URL" || log_error "Failed to download Claude"
    fi

    echo "$exe_file"
}

# --- Extract Version ---
extract_version() {
    local extract_dir="$1"
    local nupkg=$(find "$extract_dir" -maxdepth 1 -name "AnthropicClaude-*.nupkg" | head -1)

    [ -z "$nupkg" ] && log_error "Cannot find AnthropicClaude nupkg"

    local version=$(basename "$nupkg" | grep -oP '\d+\.\d+\.\d+' | head -1)
    [ -z "$version" ] && log_error "Cannot extract version from nupkg"

    echo "$version"
}

# --- Build Package ---
build_package() {
    local exe_file="$1"

    # Clean and create work directory
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"

    # Extract Claude installer
    log_info "Extracting Claude installer..."
    local extract_dir="${WORK_DIR}/extract"
    mkdir -p "$extract_dir"

    # Extract installer
    7z x -y "$exe_file" -o"$extract_dir" >/dev/null 2>&1 || log_error "Failed to extract installer"

    # Get version
    VERSION=$(extract_version "$extract_dir")
    log_info "Claude version: $VERSION"

    # Extract nupkg
    local nupkg=$(find "$extract_dir" -maxdepth 1 -name "AnthropicClaude-*.nupkg" | head -1)
    7z x -y "$nupkg" -o"$extract_dir" >/dev/null 2>&1 || log_error "Failed to extract nupkg"

    # Prepare app resources
    log_info "Preparing application resources..."
    local app_dir="${WORK_DIR}/app"
    mkdir -p "$app_dir"

    # Copy core files
    cp "$extract_dir/lib/net45/resources/app.asar" "$app_dir/"
    cp -r "$extract_dir/lib/net45/resources/app.asar.unpacked" "$app_dir/" 2>/dev/null || true

    # Extract and patch app.asar
    log_info "Patching application..."
    cd "$app_dir"
    asar extract app.asar app.asar.contents

    # Create Linux-compatible native module
    mkdir -p app.asar.contents/node_modules/claude-native
    cat > app.asar.contents/node_modules/claude-native/index.js << 'EOF'
const { app, Tray, Menu, nativeImage, Notification } = require('electron');
const path = require('path');

const KeyboardKey = {
    Backspace: 43, Tab: 280, Enter: 261, Shift: 272, Control: 61,
    Alt: 40, CapsLock: 56, Escape: 85, Space: 276, PageUp: 251,
    PageDown: 250, End: 83, Home: 154, LeftArrow: 175, UpArrow: 282,
    RightArrow: 262, DownArrow: 81, Delete: 79, Meta: 187
};
Object.freeze(KeyboardKey);

let tray = null;

function createTray() {
    if (tray) return tray;
    try {
        const iconPath = path.join(process.resourcesPath || __dirname, 'tray-icon.png');
        if (require('fs').existsSync(iconPath)) {
            tray = new Tray(nativeImage.createFromPath(iconPath));
            tray.setToolTip('Claude Desktop');
            const menu = Menu.buildFromTemplate([
                { label: 'Show', click: () => app.focus() },
                { type: 'separator' },
                { label: 'Quit', click: () => app.quit() }
            ]);
            tray.setContextMenu(menu);
        }
    } catch (e) {
        console.warn('Tray creation failed:', e);
    }
    return tray;
}

module.exports = {
    getWindowsVersion: () => "10.0.0",
    setWindowEffect: () => {},
    removeWindowEffect: () => {},
    getIsMaximized: () => false,
    flashFrame: () => {},
    clearFlashFrame: () => {},
    showNotification: (title, body) => {
        if (Notification.isSupported()) {
            new Notification({ title, body }).show();
        }
    },
    setProgressBar: () => {},
    clearProgressBar: () => {},
    setOverlayIcon: () => {},
    clearOverlayIcon: () => {},
    createTray,
    getTray: () => tray,
    KeyboardKey
};
EOF

    # Fix title bar detection
    local js_file=$(find app.asar.contents -name "MainWindowPage-*.js" 2>/dev/null | head -1)
    if [ -n "$js_file" ]; then
        sed -i -E 's/if\(!([a-zA-Z]+)[[:space:]]*&&[[:space:]]*([a-zA-Z]+)\)/if(\1 \&\& \2)/g' "$js_file"
    fi

    # Fix translation file paths
    log_info "Patching translation file paths..."
    if [ -f "app.asar.contents/.vite/build/index.js" ]; then
        sed -i 's|process\.resourcesPath|"/usr/lib/claude-desktop/resources"|g' "app.asar.contents/.vite/build/index.js"
    fi

    # Repack app.asar
    asar pack app.asar.contents app.asar
    rm -rf app.asar.contents

    # Copy translation files
    mkdir -p "$app_dir/resources" "$app_dir/locales"
    cp "$extract_dir/lib/net45/resources/"*.json "$app_dir/resources/" 2>/dev/null || true
    cp "$extract_dir/lib/net45/resources/"*.json "$app_dir/locales/" 2>/dev/null || true

    # Extract or create icon
    local icon_file="${WORK_DIR}/claude.png"
    if [ -f "$extract_dir/lib/net45/resources/TrayIconTemplate.png" ]; then
        cp "$extract_dir/lib/net45/resources/TrayIconTemplate.png" "$icon_file"
    else
        convert -size 256x256 xc:blue -fill white -gravity center -pointsize 72 -annotate +0+0 'C' "$icon_file"
    fi

    cd "$PROJECT_ROOT"

    # Generate PKGBUILD
    log_info "Generating PKGBUILD..."
    generate_pkgbuild "$VERSION" "$app_dir" "$icon_file"

    # Build the package
    log_info "Building Arch package..."
    cd "${WORK_DIR}/pkgbuild"
    makepkg -f --noconfirm || log_error "Package build failed"

    # Move package to project root
    local pkg_file=$(find . -maxdepth 1 -name "*.pkg.tar.*" | head -1)
    if [ -n "$pkg_file" ]; then
        mv "$pkg_file" "${PROJECT_ROOT}/"
        log_info "Package created: $(basename "$pkg_file")"

        # Generate .SRCINFO for AUR
        makepkg --printsrcinfo > "${PROJECT_ROOT}/.SRCINFO"
        log_info "Generated .SRCINFO for AUR"
    else
        log_error "No package file generated"
    fi

    cd "$PROJECT_ROOT"
}

# --- Generate PKGBUILD ---
generate_pkgbuild() {
    local version="$1"
    local app_dir="$2"
    local icon_file="$3"

    local pkgbuild_dir="${WORK_DIR}/pkgbuild"
    mkdir -p "$pkgbuild_dir"

    # Copy resources to pkgbuild directory
    cp -r "$app_dir" "$pkgbuild_dir/app"
    cp "$icon_file" "$pkgbuild_dir/claude.png"

    cat > "$pkgbuild_dir/PKGBUILD" << EOF
# Maintainer: Claude Desktop Linux Community
pkgname=claude-desktop
pkgver=${version}
pkgrel=1
pkgdesc="Claude AI Desktop Application"
arch=('${ARCH}')
url="https://claude.ai"
license=('custom')
depends=('electron' 'nodejs')
makedepends=()
source=()
sha256sums=()

package() {
    cd "\$srcdir"

    # Install application files
    install -dm755 "\$pkgdir/usr/lib/\$pkgname"
    cp -r "${pkgbuild_dir}/app"/* "\$pkgdir/usr/lib/\$pkgname/"

    # Install launcher
    install -dm755 "\$pkgdir/usr/bin"
    cat > "\$pkgdir/usr/bin/\$pkgname" << 'LAUNCHER'
#!/bin/bash
exec electron /usr/lib/claude-desktop/app.asar "\\\$@"
LAUNCHER
    chmod +x "\$pkgdir/usr/bin/\$pkgname"

    # Install desktop entry
    install -dm755 "\$pkgdir/usr/share/applications"
    cat > "\$pkgdir/usr/share/applications/\$pkgname.desktop" << DESKTOP
[Desktop Entry]
Name=Claude
Comment=Claude AI Desktop
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
DESKTOP

    # Install icon
    install -Dm644 "${pkgbuild_dir}/claude.png" "\$pkgdir/usr/share/icons/hicolor/256x256/apps/\$pkgname.png"
}
EOF
}

# --- Cleanup ---
cleanup() {
    if [ "${KEEP_BUILD:-no}" != "yes" ]; then
        log_info "Cleaning build directory..."
        rm -rf "${WORK_DIR}"
    fi
}

# --- Main ---
main() {
    log_info "Starting Claude Desktop build for Arch Linux"

    detect_architecture
    check_dependencies

    local exe_file=$(download_claude)
    build_package "$exe_file"

    cleanup

    log_info "Build complete! Install with: sudo pacman -U claude-desktop-*.pkg.tar.*"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-build)
            KEEP_BUILD="yes"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--keep-build]"
            echo "  --keep-build: Keep build directory after completion"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

main