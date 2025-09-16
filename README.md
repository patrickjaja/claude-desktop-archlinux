# Claude Desktop for Arch Linux

This repository provides an automated build script to create Claude Desktop packages for Arch Linux.

## Quick Install

Download the latest release from [GitHub Releases](https://github.com/patrickjaja/claude-desktop-archlinux/releases) and install:
```bash
sudo pacman -U claude-desktop-*.pkg.tar.zst
```

## Build From Source

```bash
git clone https://github.com/patrickjaja/claude-desktop-archlinux.git
cd claude-desktop-archlinux
./build.sh
```

## Prerequisites

The build script will check and prompt to install required dependencies:
- `p7zip` - For extracting Windows installer files
- `wget` - For downloading Claude installer
- `imagemagick` - For icon processing
- `npm` - For Node.js package management
- `base-devel` - For makepkg

The build script will also automatically install `asar` via npm if not present.

## Build Options

```bash
./build.sh [OPTIONS]
```

Options:
- `--keep-build`: Keep build directory after completion (useful for debugging)
- `--help`: Show help message

Example - keep build files for debugging:
```bash
./build.sh --keep-build
```

## Installation

After building, install the package:
```bash
sudo pacman -U claude-desktop-*.pkg.tar.zst
```

## Architecture Support

The build script automatically detects your system architecture and downloads the appropriate Claude installer:
- `x86_64` (Intel/AMD 64-bit)
- `aarch64` (ARM 64-bit)

## CI/CD

GitHub Actions automatically builds and releases new packages when changes are pushed. The workflow:
1. Builds the package using the latest Claude version
2. Creates a GitHub release with the `.pkg.tar.zst` file
3. Updates the AUR package (if configured)

## License

This build script is provided as-is for the Arch Linux community.

## Disclaimer

This is an unofficial build script for Claude Desktop. Claude is a trademark of Anthropic.
