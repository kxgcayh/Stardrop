# StardropMac

A native macOS mod manager for [Stardew Valley](https://www.stardewvalley.net/) built in Swift and SwiftUI, compatible with macOS 14 (Sonoma) and macOS 15 (Sequoia).

---

## Features

### Native Architecture
- Built with Swift and SwiftUI for macOS.
- Native binary for Apple Silicon (arm64) and Intel (x86_64).
- Operates independently without requiring .NET, Mono, or third-party runtime frameworks.

### Mod Separators
- Visual separator banners inspired by Mod Organizer 2 to group mods into logical categories.
- Collapsible and expandable sections.
- Reorder separators and move mods between separators.
- Bulk enable and disable mods within a specific separator.
- Auto-generate separators based on mod folder structure (e.g. `[MODS] - Core`).

### Mod Table & Quick Toggling
- Unified mod list with status checkboxes and status indicator badges.
- Clickable checkbox or status badge to toggle individual mods.
- Spacebar shortcut to toggle the selected mod on or off.
- Arrow key navigation (Up/Down) through visible mods in display order.
- Intelligent focus management: search bar and text field typing do not trigger mod toggle shortcuts.

### SMAPI Core Component Protection
- Automatic detection and case-insensitive manifest parsing for bundled SMAPI mods (`ConsoleCommands`, `SaveBackup`, and `ErrorHandler`).
- Prevents core SMAPI components from being disabled during bulk operations or accidental clicks.

### Mod Updates
- Checks for updates via the official SMAPI mod update registry (`smapi.io`).
- Displays available version updates with direct download links.
- Filter category to view only mods with updates available.

### Mod Archive Installation (.zip, .7z, .rar, .tar.gz)
- Drag and drop archives (`.zip`, `.7z`, `.rar`, `.tar.gz`) or uncompressed mod folders directly into the app window.
- Manual file selection via `⌘O`, toolbar `+` button, mod table context menu, or the empty-state button.
- Automatic decompression, nested SMAPI manifest discovery, and clean installation into the active Mods directory.
- Preserves existing user `config.json` files when upgrading existing mods.
- Displays an installation summary with warnings, errors, and updated mod statuses.

### Mod Deletion & Dependency Safety
- Delete mods directly from the right-click context menu or the inspector sidebar (`Delete Mod...`).
- **Dependency Warning System**: Automatically detects if the mod to be deleted is a required dependency (`isRequired: true` or `contentPackFor`) of any currently enabled mods. If so, displays a detailed warning confirmation modal listing all dependent enabled mods before deletion.
- Moves deleted mod folders safely to the macOS Trash Bin.
- Automatically cleans up references across profiles and separators, and selects an adjacent mod.
- Core SMAPI components (`ConsoleCommands`, `SaveBackup`, `ErrorHandler`) are protected against accidental deletion.

### Nexus Mods Integration & Endorsements
- Optional personal API key validation with Nexus Mods.
- Displays account details and membership tier (Free / Premium).
- Full encryption/decryption compatibility with C# Stardrop (`Settings.json` and AES-256-CBC obscurity keys in `Cache/Notion.json`).
- View endorsement status and endorse or abstain directly from the mod list or inspector panel.
- Direct links to Nexus mod pages.

### Profile Management
- Multiple profiles with independent mod selections and separator arrangements.
- Real-time profile switching, duplication, and creation.
- Seamless SMAPI launching: stages active mods into `Selected Mods/` via symlinks without duplicating game files.

### In-App Config Editor
- Edit `config.json` files directly within the application.
- JSON syntax validation before saving.

### Diagnostic Tools
- About dialog with environment diagnostics: detected game version, SMAPI version, and file paths.
- One-click shortcuts to open the mod directory, SMAPI logs, and configuration directories in Finder.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Space` | Toggle selected mod enabled/disabled |
| `↑` / `↓` | Navigate through mod list |
| `⌘O` | Install mod archive (.zip, .7z, .rar, .tar.gz) or folder |
| `⌘R` | Launch Stardew Valley with SMAPI |
| `⌘U` | Check for mod updates |
| `⌘,` | Open Preferences / Settings |
| `⇧⌘N` | Open Nexus Mods Account |
| `⇧⌘S` | Create new separator |
| `Escape` | Dismiss active modal or sheet |

---

## Data Storage & Compatibility

StardropMac shares the standard Stardrop data format and stores configuration files at:

```
~/Library/Application Support/Stardrop/
├── Data/
│   ├── Settings.json        # Preferences, configured paths, Nexus credentials
│   ├── Profiles/            # Profile configurations (*.json)
│   │   ├── Default.json
│   │   └── Small.json
│   └── Separators/          # Separator structures per profile (*.json)
│       ├── Default.json
│       └── Small.json
└── Logs/
    └── Stardrop.log
```

---

## Building from Source

### Prerequisites
- macOS 14.0 or newer
- Xcode Command Line Tools (`xcode-select --install`) or Swift 5.9+ toolchain

### Build Application Bundle
Run the build script from the `StardropMac/` directory:
```bash
./build-mac-app.sh
```
The output bundle will be located at `StardropMac/build/Stardrop.app`.

### Package Disk Image (DMG)
To build a compressed, distributable `.dmg` with an `/Applications` drag-and-drop link:
```bash
./build-dmg.sh
```

Available flags:
- `./build-dmg.sh --skip-build`: Package an existing `Stardrop.app` without recompiling.
- `./build-dmg.sh --open`: Mount and open the resulting DMG in Finder.
- `./build-dmg.sh -v <version>`: Specify a release version string.

Outputs generated in `StardropMac/build/`:
- `Stardrop-<version>-macOS.dmg`
- `Stardrop.dmg`
- `Stardrop-<version>-macOS.dmg.sha256`

### Development Mode
To run directly via Swift Package Manager:
```bash
swift run
```

---

## Project Structure

```
StardropMac/
├── Package.swift                    # Swift Package Manager manifest
├── build-mac-app.sh                 # Application bundle build script
├── build-dmg.sh                     # Disk image (DMG) packaging script
├── Sources/
│   └── StardropMac/
│       ├── StardropMacApp.swift     # App entrypoint and menu commands
│       ├── Models/
│       │   ├── Manifest.swift       # Mod manifest parsing and dependency models
│       │   ├── Mod.swift            # Mod representation and metadata
│       │   ├── ModSeparator.swift   # Separator group model
│       │   ├── Profile.swift        # Profile configuration model
│       │   └── Settings.swift       # Application settings model
│       ├── Services/
│       │   ├── ModScannerService.swift      # Directory scanner and manifest reader
│       │   ├── ModUpdateService.swift       # SMAPI mod update registry client
│       │   ├── NexusService.swift           # Nexus Mods API client
│       │   ├── PathingService.swift         # Directory and executable path resolver
│       │   ├── ProfileService.swift         # Profile disk persistence
│       │   ├── SeparatorService.swift       # Separator disk persistence
│       │   ├── SettingsService.swift        # Settings disk persistence
│       │   └── SMAPILauncherService.swift   # Symlink manager and process launcher
│       ├── ViewModels/
│       │   └── AppState.swift               # Application state and business logic
│       └── Views/
│           ├── AboutSheet.swift             # About and system diagnostics dialog
│           ├── ConfigEditorSheet.swift      # In-app config.json editor
│           ├── InspectorView.swift          # Right sidebar mod inspector
│           ├── MainView.swift               # Root navigation split view and toolbar
│           ├── ModTableView.swift           # Main mod table and separator sections
│           ├── NewProfileSheet.swift        # Profile creation sheet
│           ├── NexusAccountSheet.swift      # Nexus account connection modal
│           ├── SeparatorSheets.swift        # Separator creation and rename sheets
│           ├── SettingsSheet.swift          # Configuration and paths modal
│           └── SidebarView.swift            # Left sidebar categories and profile list
└── build/
    ├── Stardrop.app                         # Built application bundle
    └── Stardrop.dmg                         # Distributable disk image
```

---

## Credits & Attribution

- **Original Project**: [Floogen/Stardrop](https://github.com/Floogen/Stardrop)
- **SMAPI**: [Pathoschild](https://github.com/Pathoschild) and the Stardew Valley modding community
- **Stardew Valley**: [Eric "ConcernedApe" Barone](https://www.stardewvalley.net/)

---

## License

Licensed under the **GNU General Public License v3.0 (GPLv3)**, in full compliance with the parent repository [Floogen/Stardrop](https://github.com/Floogen/Stardrop). See [LICENSE](../LICENSE).
