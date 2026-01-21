# Sailswift

<p align="center">
  <img src="docs/icon.png" alt="Sailswift Icon" width="128" height="128">
</p>

Native macOS mod manager for **Ship of Harkinian** - built with Swift and SwiftUI.

> **Built on the logic of [Saildeck-macOS](https://github.com/proverbiallemon/Saildeck-macOS)** (itself a fork of the original [Saildeck](https://github.com/Wolfeni/Saildeck) by Wolfeni) - rewritten from Python/tkinter to native Swift for optimal Mac performance.

## Features

- **Mod Profiles** - Save and load configurations with auto-download of missing mods
- **Modpack Sharing** - Export/import `.sailswiftpack` files to share with others
- **Update Checker** - Check installed mods for GameBanana updates
- **GameBanana Integration** - Browse, search, and download mods in-app
- **One-Click Install** - `shipofharkinian://` URL scheme for seamless installation

**[Full feature list →](https://github.com/proverbiallemon/Sailswift/wiki/Features)**

## Requirements

- macOS 13.0 (Ventura) or later
- [Ship of Harkinian](https://www.shipofharkinian.com/) installed
- **Optional**: [7-Zip](https://www.7-zip.org/) for `.7z` and `.rar` archives (`brew install 7zip`)
- **Optional**: [unar](https://theunarchiver.com/command-line) for RAR5 files (`brew install unar`)

## Installation

Download the latest release from the [Releases](https://github.com/proverbiallemon/Sailswift/releases) page.

**[Detailed installation guide →](https://github.com/proverbiallemon/Sailswift/wiki/Installation)**

### Build from Source

```bash
git clone https://github.com/proverbiallemon/Sailswift.git
cd Sailswift
open Sailswift.xcodeproj
# Build with Cmd+R
```

## Documentation

Full documentation is available on the **[Wiki](https://github.com/proverbiallemon/Sailswift/wiki)**:

- **[Features](https://github.com/proverbiallemon/Sailswift/wiki/Features)** - Complete feature list
- **[Installation](https://github.com/proverbiallemon/Sailswift/wiki/Installation)** - Setup and build instructions
- **[Usage](https://github.com/proverbiallemon/Sailswift/wiki/Usage)** - How to use Sailswift
- **[Technical Details](https://github.com/proverbiallemon/Sailswift/wiki/Technical-Details)** - Architecture and API docs
- **[Changelog](https://github.com/proverbiallemon/Sailswift/wiki/Changelog)** - Version history

## Quick Start

1. Download from [Releases](https://github.com/proverbiallemon/Sailswift/releases)
2. Move `Sailswift.app` to Applications
3. Open and set your Ship of Harkinian path in Settings
4. Browse mods or use `shipofharkinian://` links to install

## Related Projects

- [Saildeck-macOS](https://github.com/proverbiallemon/Saildeck-macOS) - Python/tkinter version (cross-platform)
- [Ship of Harkinian](https://www.shipofharkinian.com/) - The game itself

## License

GNU General Public License v3.0 - see [LICENSE](LICENSE)

## Acknowledgments

- The Ship of Harkinian team for their incredible work
- GameBanana for hosting the mod community
- The Saildeck project for the original Python implementation
