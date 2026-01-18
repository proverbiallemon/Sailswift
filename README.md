# Sailswift

Native macOS mod manager for **Ship of Harkinian** - built with Swift and SwiftUI.

> **Built on the logic of [Saildeck-macOS](https://github.com/proverbiallemon/Saildeck-macOS)** - rewritten from Python/tkinter to native Swift for optimal Mac performance.

**Why Sailswift over Saildeck?** Sailswift is the actively maintained version with more features and faster updates. As a native Swift app, it offers better performance, a more polished UI, and will continue to receive new features that may not be backported to the Python version.

## Features

### Core Functionality
- **Mod Management** - View, enable, disable, and delete mods with a native interface
- **Folder Hierarchy** - Navigate mods organized in folders with collapsible tree view
- **One-Click Launch** - Start the game with proper AltAssets configuration
- **Mod Profiles** - Save and load different mod configurations (data models implemented)
- **Custom URL Scheme** - One-click mod installation from GameBanana using `shipofharkinian://` links

### GameBanana Integration
- Browse mods directly from the app
- Search by name and filter by category
- Download with progress tracking
- Automatic ZIP extraction using native tools
- One-click install from GameBanana website via custom URL scheme

### Native Mac Experience
- **Instant Startup** - No interpreter overhead
- **Native Look & Feel** - Built with SwiftUI
- **Light/Dark Mode** - Follows system appearance
- **Full File Access** - App Sandbox disabled for direct mod directory access
- **Keyboard Shortcuts** - Full keyboard navigation

## Requirements

- macOS 13.0 (Ventura) or later
- [Ship of Harkinian](https://www.shipofharkinian.com/) installed

## Installation

### Download
Download the latest release from the [Releases](https://github.com/proverbiallemon/Sailswift/releases) page.

### Build from Source
1. Clone the repository
   ```bash
   git clone https://github.com/proverbiallemon/Sailswift.git
   ```
2. Open `Sailswift.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Usage

### Managing Mods
- Mods are stored at `~/Library/Application Support/com.shipofharkinian.soh/mods/`
- Enable/disable mods by clicking on them in the mod list
- Folder controls allow toggling all mods within a folder
- Delete mods using the context menu or keyboard shortcuts

### Launching the Game
1. Set your Ship of Harkinian installation path in Settings
2. Enable/disable desired mods
3. Click "Launch Game" - AltAssets will be automatically configured if needed
4. The app will close after launching the game

### Installing Mods from GameBanana
#### Method 1: In-App Browser
1. Click the "Browse" tab
2. Search or browse available mods
3. Click on a mod to view details and download files
4. Select a file and click "Download"

#### Method 2: One-Click Install (URL Scheme)
Sailswift registers the `shipofharkinian://` URL scheme for seamless mod installation:

- **URL Format**: `shipofharkinian://https//gamebanana.com/mmdl/{itemId},{itemType},{fileId}`
- **Usage**: Click a compatible link on GameBanana or other websites
- **Example**: `shipofharkinian://https//gamebanana.com/mmdl/1593301,Mod,640119`

When you click a `shipofharkinian://` link:
1. Sailswift will automatically open (if not already running)
2. The mod file will be downloaded in the background
3. ZIP files are automatically extracted to the mods directory
4. You'll receive a notification when installation completes

### Mod Profiles
Save and restore mod configurations for different playthroughs. Profile data models are implemented and can be managed programmatically through the `ModProfileManager` class.

## Project Structure

```
Sailswift/
├── App/
│   ├── SailswiftApp.swift      # Entry point + URL scheme handler
│   └── AppState.swift          # Global state management
├── Models/
│   ├── Mod.swift               # Mod data model
│   ├── ModProfile.swift        # Profile data + manager
│   └── GameBananaMod.swift     # API response models
├── Views/
│   ├── MainView.swift          # Main window
│   ├── ModListView.swift       # Mod tree/list
│   ├── ModRowView.swift        # Individual mod row
│   ├── ModBrowserView.swift    # GameBanana browser
│   ├── ModCardView.swift       # Mod card in browser
│   ├── SettingsView.swift      # Preferences window
│   └── AboutView.swift         # About window
├── ViewModels/
│   ├── ModManager.swift        # Mod CRUD operations
│   ├── GameBananaAPI.swift     # GameBanana API client
│   └── DownloadManager.swift   # Download + URL scheme handling
├── Services/
│   ├── FileService.swift       # File system operations
│   └── GameConfigService.swift # shipofharkinian.json config
└── Utilities/
    ├── PathConstants.swift     # Standard macOS paths
    └── Extensions.swift        # Swift extensions
```

### Key Implementation Notes
- **App Sandbox**: Disabled (`com.apple.security.app-sandbox = false`) to allow full access to `~/Library/Application Support/com.shipofharkinian.soh/mods/`
- **Archive Extraction**: Uses native `/usr/bin/ditto` command for ZIP extraction
- **URL Scheme**: Registered in `Info.plist` and handled in `SailswiftApp.swift`
- **Async/Await**: All I/O operations use modern Swift concurrency
- **No External Dependencies**: Pure Swift/SwiftUI implementation

## Technology Stack

| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI |
| Networking | URLSession + async/await |
| Data Persistence | UserDefaults + JSON (profiles.json) |
| Archive Extraction | `/usr/bin/ditto` (native macOS tool) |
| File Management | FileManager + FileService wrapper |
| Configuration | GameConfigService (shipofharkinian.json) |
| API Integration | GameBanana API v11 |

## Development Status

### Implemented Features
- Core mod management (enable/disable/delete)
- Hierarchical folder tree view with state tracking
- GameBanana API integration (browse, search, download)
- Custom URL scheme handler (`shipofharkinian://`)
- Game launcher with AltAssets auto-configuration
- Mod profile data models and persistence
- ZIP archive extraction
- Settings management with auto-detection

### Not Yet Implemented
- Modpack export/import UI
- Drag & drop file installation
- Quick Look preview integration
- Update checking service
- Mod profile UI (data layer exists)
- 7z archive support (only ZIP currently)
- MD5 verification during downloads

## Technical Details

### File Locations
- **Mods Directory**: `~/Library/Application Support/com.shipofharkinian.soh/mods/`
- **Game Config**: `~/Library/Application Support/com.shipofharkinian.soh/shipofharkinian.json`
- **Profiles**: `~/Library/Application Support/Sailswift/profiles.json`

### Mod File Extensions
- `.otr` - Enabled OTR mod (OoT Redux)
- `.o2r` - Enabled O2R mod (OoT 2.0)
- `.disabled` - Disabled OTR mod
- `.di2abled` - Disabled O2R mod

### URL Scheme Handler
The `shipofharkinian://` URL scheme allows external applications and websites to trigger mod downloads:

1. **Registration**: Defined in `Info.plist` under `CFBundleURLTypes`
2. **Handler**: Implemented in `SailswiftApp.swift` using `.onOpenURL()`
3. **Parser**: Extracts itemId, itemType, and fileId from the URL
4. **Downloader**: Calls `GameBananaAPI.fetchFileInfo()` then `DownloadManager.downloadFile()`

**URL Structure Breakdown**:
```
shipofharkinian://https//gamebanana.com/mmdl/{itemId},{itemType},{fileId}
                  ^^^^^-- Note: Double slash is intentional for URL parsing
```

### App Sandbox Consideration
This app disables the App Sandbox to access the Ship of Harkinian mods directory directly. While this reduces security isolation, it's necessary for seamless mod management without requiring user file selection for every operation.

If distributing through the Mac App Store, this would need to be refactored to use security-scoped bookmarks or move to a sandboxed mods directory.

## Related Projects

- [Saildeck-macOS](https://github.com/proverbiallemon/Saildeck-macOS) - Python/tkinter version (cross-platform compatible)
- [Ship of Harkinian](https://www.shipofharkinian.com/) - The game itself

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- The Ship of Harkinian team for their incredible work
- GameBanana for hosting the mod community
- The Saildeck project for the original Python implementation
