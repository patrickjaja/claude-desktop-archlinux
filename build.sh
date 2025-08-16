#!/bin/bash
set -euo pipefail

# Arch Linux Claude Desktop Build Script

# --- System Checks ---
if [ ! -f "/etc/arch-release" ]; then
    echo "❌ This script is designed for Arch Linux"
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
   echo "❌ This script should not be run using sudo or as the root user."
   echo "   It will prompt for sudo password when needed for specific actions."
   exit 1
fi

# --- Configuration ---
PACKAGE_NAME="claude-desktop"
MAINTAINER="Claude Desktop Linux Maintainers"
DESCRIPTION="Claude Desktop for Linux"
PROJECT_ROOT="$(pwd)"
WORK_DIR="$PROJECT_ROOT/build"
APP_STAGING_DIR="$WORK_DIR/electron-app"

# --- Architecture Detection ---
echo "⚙️ Detecting system architecture..."
MACHINE_ARCH=$(uname -m)
case "$MACHINE_ARCH" in
    x86_64)
        HOST_ARCH="amd64"
        CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
        CLAUDE_EXE_FILENAME="Claude-Setup-x64.exe"
        ;;
    aarch64)
        HOST_ARCH="arm64"
        CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-arm64/Claude-Setup-arm64.exe"
        CLAUDE_EXE_FILENAME="Claude-Setup-arm64.exe"
        ;;
    *)
        echo "❌ Unsupported architecture: $MACHINE_ARCH"
        exit 1
        ;;
esac
echo "✓ Detected architecture: $MACHINE_ARCH ($HOST_ARCH)"

# --- Argument Parsing ---
CLEANUP_ACTION="yes"
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "❌ Error: Argument for $1 is missing" >&2
                exit 1
            fi
            CLEANUP_ACTION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--clean yes|no]"
            echo "  --clean: Specify whether to clean intermediate build files (yes or no). Default: yes"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Use -h or --help for usage information."
            exit 1
            ;;
    esac
done

CLEANUP_ACTION=$(echo "$CLEANUP_ACTION" | tr '[:upper:]' '[:lower:]')
if [[ "$CLEANUP_ACTION" != "yes" && "$CLEANUP_ACTION" != "no" ]]; then
    echo "❌ Invalid cleanup option: '$CLEANUP_ACTION'. Must be 'yes' or 'no'."
    exit 1
fi

# --- Node.js Check ---
echo "Checking Node.js installation..."
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install nodejs package."
    exit 1
fi
NODE_VERSION=$(node --version)
echo "✓ Node.js found: $NODE_VERSION"

# --- Dependency Check ---
echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Required commands and their Arch packages
declare -A REQUIRED_DEPS=(
    ["7z"]="p7zip"
    ["wget"]="wget"
    ["wrestool"]="icoutils"
    ["icotool"]="icoutils"
    ["convert"]="imagemagick"
    ["npm"]="npm"
    ["makepkg"]="pacman"
)

for cmd in "${!REQUIRED_DEPS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL ${REQUIRED_DEPS[$cmd]}"
    fi
done

if [ -n "$DEPS_TO_INSTALL" ]; then
    # Remove duplicates
    DEPS_TO_INSTALL=$(echo "$DEPS_TO_INSTALL" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    echo "Installing dependencies: $DEPS_TO_INSTALL"
    if ! sudo pacman -S --needed --noconfirm $DEPS_TO_INSTALL; then
        echo "❌ Failed to install dependencies"
        exit 1
    fi
fi
echo "✓ All dependencies satisfied"

# --- Setup Build Directory ---
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$APP_STAGING_DIR"

# --- Install Electron and Asar ---
echo "Installing Electron and Asar..."
cd "$WORK_DIR"
echo '{"name":"claude-desktop-build","version":"0.0.1","private":true}' > package.json

if ! npm install --no-save electron @electron/asar; then
    echo "❌ Failed to install Electron and Asar"
    exit 1
fi

ELECTRON_DIST_PATH="$WORK_DIR/node_modules/electron/dist"
ASAR_EXEC="$(realpath "$WORK_DIR/node_modules/.bin/asar")"

if [ ! -d "$ELECTRON_DIST_PATH" ] || [ ! -f "$ASAR_EXEC" ]; then
    echo "❌ Electron or Asar installation incomplete"
    exit 1
fi
echo "✓ Electron and Asar installed"

# --- Download Claude Installer ---
echo "📥 Downloading Claude Desktop installer..."
CLAUDE_EXE_PATH="$WORK_DIR/$CLAUDE_EXE_FILENAME"
if ! wget -O "$CLAUDE_EXE_PATH" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi

# --- Extract Resources ---
echo "📦 Extracting resources..."
CLAUDE_EXTRACT_DIR="$WORK_DIR/claude-extract"
mkdir -p "$CLAUDE_EXTRACT_DIR"
if ! 7z x -y "$CLAUDE_EXE_PATH" -o"$CLAUDE_EXTRACT_DIR"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

cd "$CLAUDE_EXTRACT_DIR"
NUPKG_PATH=$(find . -maxdepth 1 -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG_PATH" ]; then
    echo "❌ Could not find AnthropicClaude nupkg file"
    exit 1
fi

# Extract version
VERSION=$(echo "$NUPKG_PATH" | grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full|-arm64-full)')
if [ -z "$VERSION" ]; then
    echo "❌ Could not extract version from nupkg filename"
    exit 1
fi
echo "✓ Detected Claude version: $VERSION"

# Extract nupkg
if ! 7z x -y "$NUPKG_PATH"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi

# --- Process Icons ---
echo "🎨 Processing icons..."
EXE_PATH="lib/net45/claude.exe"
if [ ! -f "$EXE_PATH" ]; then
    echo "❌ Cannot find claude.exe"
    exit 1
fi

wrestool -x -t 14 "$EXE_PATH" -o claude.ico
icotool -x claude.ico
cp claude_*.png "$WORK_DIR/"

# --- Process app.asar ---
echo "⚙️ Processing app.asar..."
cp "lib/net45/resources/app.asar" "$APP_STAGING_DIR/"
cp -a "lib/net45/resources/app.asar.unpacked" "$APP_STAGING_DIR/"

cd "$APP_STAGING_DIR"
"$ASAR_EXEC" extract app.asar app.asar.contents

# Create stub native module with better Linux tray support
cat > app.asar.contents/node_modules/claude-native/index.js << 'EOF'
// Stub implementation of claude-native using KeyboardKey enum values
const { app, Tray, Menu, nativeImage, Notification } = require('electron');
const path = require('path');

const KeyboardKey = { Backspace: 43, Tab: 280, Enter: 261, Shift: 272, Control: 61, Alt: 40, CapsLock: 56, Escape: 85, Space: 276, PageUp: 251, PageDown: 250, End: 83, Home: 154, LeftArrow: 175, UpArrow: 282, RightArrow: 262, DownArrow: 81, Delete: 79, Meta: 187 };
Object.freeze(KeyboardKey);

let tray = null;

function createTray() {
  if (tray) return tray;
  
  try {
    // Try different tray icon paths
    const iconPaths = [
      path.join(__dirname, '../../resources/TrayIconTemplate.png'),
      path.join(__dirname, '../../resources/TrayIconTemplate-Dark.png'),
      path.join(process.resourcesPath || '', 'TrayIconTemplate.png'),
      path.join(app.getAppPath(), 'resources', 'TrayIconTemplate.png')
    ];
    
    let iconPath = null;
    for (const p of iconPaths) {
      try {
        if (require('fs').existsSync(p)) {
          iconPath = p;
          break;
        }
      } catch (e) {
        // Continue to next path
      }
    }
    
    if (iconPath) {
      const icon = nativeImage.createFromPath(iconPath);
      if (!icon.isEmpty()) {
        tray = new Tray(icon);
        tray.setToolTip('Claude Desktop');
        
        const contextMenu = Menu.buildFromTemplate([
          { label: 'Show Claude', click: () => {
            const windows = require('electron').BrowserWindow.getAllWindows();
            if (windows.length > 0) {
              windows[0].show();
            }
          }},
          { type: 'separator' },
          { label: 'Quit', click: () => app.quit() }
        ]);
        
        tray.setContextMenu(contextMenu);
        tray.on('click', () => {
          const windows = require('electron').BrowserWindow.getAllWindows();
          if (windows.length > 0) {
            windows[0].isVisible() ? windows[0].hide() : windows[0].show();
          }
        });
      }
    }
  } catch (error) {
    console.warn('Failed to create tray icon:', error);
  }
  
  return tray;
}

// Enhanced notification support
function showNotification(title, body, options = {}) {
  try {
    if (Notification.isSupported()) {
      const notification = new Notification({
        title: title || 'Claude Desktop',
        body: body || '',
        icon: options.icon,
        silent: options.silent || false
      });
      notification.show();
      return true;
    }
  } catch (error) {
    console.warn('Failed to show notification:', error);
  }
  return false;
}

module.exports = { 
  getWindowsVersion: () => "10.0.0", 
  setWindowEffect: () => {}, 
  removeWindowEffect: () => {}, 
  getIsMaximized: () => false, 
  flashFrame: () => {}, 
  clearFlashFrame: () => {}, 
  showNotification, 
  setProgressBar: () => {}, 
  clearProgressBar: () => {}, 
  setOverlayIcon: () => {}, 
  clearOverlayIcon: () => {}, 
  createTray,
  getTray: () => tray,
  KeyboardKey 
};

// Auto-create tray when app is ready if not in packaged mode
if (app && app.whenReady) {
  app.whenReady().then(() => {
    if (!app.isPackaged) {
      setTimeout(createTray, 1000);
    }
  });
}
EOF

# Copy resources
mkdir -p app.asar.contents/resources/i18n
cp "$CLAUDE_EXTRACT_DIR/lib/net45/resources/Tray"* app.asar.contents/resources/
cp "$CLAUDE_EXTRACT_DIR/lib/net45/resources/"*-*.json app.asar.contents/resources/i18n/

# Fix title bar detection
echo "Fixing title bar detection..."
TARGET_FILE=$(find app.asar.contents/.vite/renderer/main_window/assets -type f -name "MainWindowPage-*.js")
if [ -z "$TARGET_FILE" ]; then
    echo "❌ Could not find MainWindowPage JS file"
    exit 1
fi
sed -i -E 's/if\(!([a-zA-Z]+)[[:space:]]*&&[[:space:]]*([a-zA-Z]+)\)/if(\1 \&\& \2)/g' "$TARGET_FILE"

# Repack asar
"$ASAR_EXEC" pack app.asar.contents app.asar

# Create unpacked native module
mkdir -p "$APP_STAGING_DIR/app.asar.unpacked/node_modules/claude-native"
cp app.asar.contents/node_modules/claude-native/index.js "$APP_STAGING_DIR/app.asar.unpacked/node_modules/claude-native/"

# Copy Electron
echo "Copying Electron distribution..."
mkdir -p "$APP_STAGING_DIR/node_modules/electron"
cp -a "$WORK_DIR/node_modules/electron"/* "$APP_STAGING_DIR/node_modules/electron/"
chmod +x "$APP_STAGING_DIR/node_modules/electron/dist/electron"

# Copy translation files to staging directory
echo "Copying translation files..."
mkdir -p "$APP_STAGING_DIR/locales"
cp "$CLAUDE_EXTRACT_DIR/lib/net45/resources/"*.json "$APP_STAGING_DIR/locales/"

cd "$PROJECT_ROOT"

# --- Build Arch Package ---
echo "📦 Building Arch Linux package..."
PKGBUILD_DIR="$WORK_DIR/pkgbuild"
mkdir -p "$PKGBUILD_DIR"

# Copy necessary files to PKGBUILD directory for makepkg to access
cp -r "$APP_STAGING_DIR" "$PKGBUILD_DIR/electron-app"
cp "$WORK_DIR/claude_6_256x256x32.png" "$PKGBUILD_DIR/claude_6_256x256x32.png"

cat > "$PKGBUILD_DIR/PKGBUILD" << EOF
# Maintainer: $MAINTAINER
pkgname=$PACKAGE_NAME
pkgver=$VERSION
pkgrel=1
pkgdesc="$DESCRIPTION"
arch=('$MACHINE_ARCH')
url="https://claude.ai"
license=('custom')
depends=('electron' 'nodejs')
makedepends=('npm' 'asar')
source=()
sha256sums=()

package() {
    # Create directories
    install -dm755 "\$pkgdir/usr/lib/\$pkgname"
    install -dm755 "\$pkgdir/usr/bin"
    install -dm755 "\$pkgdir/usr/share/applications"
    install -dm755 "\$pkgdir/usr/share/icons/hicolor/256x256/apps"
    
    # Copy application files from the build directory
    cp -r "$PKGBUILD_DIR/electron-app"/* "\$pkgdir/usr/lib/\$pkgname/"
    
    # Copy translation files to all Electron installation paths
    # Include all electron versions including the current one (electron37)
    for electron_dir in /usr/lib/electron*; do
        # Check if it's a directory (real or symlink target)
        if [ -d "\$electron_dir" ]; then
            # Get the real directory if it's a symlink
            real_electron_dir=\$(realpath "\$electron_dir" 2>/dev/null || echo "\$electron_dir")
            if [ -d "\$real_electron_dir" ]; then
                install -dm755 "\$pkgdir\$real_electron_dir/resources"
                for json_file in "\$pkgdir/usr/lib/\$pkgname/locales/"*.json; do
                    if [ -f "\$json_file" ]; then
                        install -m644 "\$json_file" "\$pkgdir\$real_electron_dir/resources/"
                    fi
                done
            fi
        fi
    done
    
    # Create launcher script
    cat > "\$pkgdir/usr/bin/\$pkgname" << 'LAUNCHER'
#!/bin/bash
exec electron /usr/lib/$PACKAGE_NAME/app.asar "\$@"
LAUNCHER
    chmod +x "\$pkgdir/usr/bin/\$pkgname"
    
    # Install desktop file
    cat > "\$pkgdir/usr/share/applications/\$pkgname.desktop" << DESKTOP
[Desktop Entry]
Name=Claude
Comment=Claude Desktop
Exec=$PACKAGE_NAME %u
Icon=$PACKAGE_NAME
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
DESKTOP
    
    # Install icon
    install -Dm644 "$PKGBUILD_DIR/claude_6_256x256x32.png" "\$pkgdir/usr/share/icons/hicolor/256x256/apps/\$pkgname.png"
}
EOF

echo "Building package..."
cd "$PKGBUILD_DIR"
if makepkg -f; then
    PKG_FILE=$(find . -maxdepth 1 -name "*.pkg.tar.*" | head -n 1)
    if [ -n "$PKG_FILE" ] && [ -f "$PKG_FILE" ]; then
        FINAL_OUTPUT_PATH="$PROJECT_ROOT/$(basename "$PKG_FILE")"
        mv "$PKG_FILE" "$FINAL_OUTPUT_PATH"
        echo "✓ Package created: $FINAL_OUTPUT_PATH"
    fi
else
    echo "❌ Failed to build package"
    exit 1
fi

cd "$PROJECT_ROOT"

# --- Cleanup ---
if [ "$CLEANUP_ACTION" = "yes" ]; then
    echo "🧹 Cleaning up..."
#    rm -rf "$WORK_DIR"
fi

echo -e "\n✅ Build complete!"
echo -e "\nTo install the package, run:"
echo -e "  \033[1;32msudo pacman -U $FINAL_OUTPUT_PATH\033[0m"
