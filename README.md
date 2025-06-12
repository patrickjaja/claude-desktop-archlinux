# Claude Desktop for Arch Linux

This repository provides a build script to create Claude Desktop packages for Arch Linux.

## Prerequisites

The build script will automatically install required dependencies via pacman:
- `p7zip` - For extracting Windows installer files
- `wget` - For downloading Claude installer
- `icoutils` - For extracting and converting icons
- `imagemagick` - For image processing
- `npm` - For Node.js package management
- `dpkg` - For building .deb packages (optional)

## Building

Clone the repository and run the build script:

```bash
git clone https://github.com/yourusername/claude-desktop-archlinux.git
cd claude-desktop-archlinux
./build.sh --build pkgbuild --clean yes
```

### Build Options

- `--build FORMAT`: Choose build format
  - `pkgbuild` - Native Arch Linux package (recommended)
  - `appimage` - Universal Linux AppImage
  - `deb` - Debian package (requires conversion with debtap)
- `--clean yes/no`: Clean intermediate build files after completion (default: yes)
- `--help`: Show help message

### Examples

Build native Arch package:
```bash
./build.sh --build pkgbuild
```

Build AppImage:
```bash
./build.sh --build appimage
```

Keep build files for debugging:
```bash
./build.sh --build pkgbuild --clean no
```

## Installation

After building, install the package:

### For PKGBUILD (recommended):
```bash
sudo pacman -U claude-desktop-*.pkg.tar.*
```

### For AppImage:
```bash
chmod +x claude-desktop-*.AppImage
./claude-desktop-*.AppImage
```

For desktop integration with AppImage:
```bash
yay -S appimagelauncher
```

### For .deb (requires conversion):
```bash
yay -S debtap
sudo debtap -u
debtap -q claude-desktop_*.deb
sudo pacman -U claude-desktop-*.pkg.tar.*
```

## Architecture Support

The build script automatically detects your system architecture and downloads the appropriate Claude installer:
- x86_64 (amd64)
- aarch64 (arm64)

## License

This project is dual-licensed under MIT and Apache 2.0 licenses. See LICENSE-MIT and LICENSE-APACHE files for details.

## Disclaimer

This is an unofficial build script for Claude Desktop. Claude is a trademark of Anthropic.