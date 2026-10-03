# StardropMac

A 100% native macOS mod manager for [Stardew Valley](https://www.stardewvalley.net/) built with Swift 6 and SwiftUI, engineered specifically for Apple Silicon and modern macOS (macOS 14 Sonoma and macOS 15 Sequoia+).

---

## Features & Highlights

### ⚡️ 100% Native macOS Architecture
- Built with pure **SwiftUI** and **AppKit** — no Electron, Avalonia, or Skia pixel-drawing emulation.
- Fluid 120Hz ProMotion animations, native physics, and kinetic overscroll bounce.
- Translucent sidebar materials (`.sidebar`), native sheets, alerts, and system inspectors.

### 📋 Clean & Aligned Mod Table
- Direct, unified mod list with centered enabled/disabled toggles.
- Clean layout with author, version tags, update indicators, and direct action shortcuts.
- Smooth scrolling and instant selection of mods with zero overhead.

### 🌐 Official Nexus Mods API Integration
- Connect your Nexus Mods account directly via your Personal API Key.
- Live key validation against `https://api.nexusmods.com/v1/users/validate.json`.
- Automatic detection of **Nexus Premium** membership status.
- Accessible from the **Sidebar ("Services")**, **Top Toolbar** (globe icon), **App Settings (`⌘,`)**, and macOS Menu Bar (`⇧⌘N`).
- Secure local storage conforming to Stardrop's `Settings.json` schema.

### 🔄 Mod Update Engine (Nexus, GitHub, CurseForge)
- **Automatic Background Check**: Asynchronously checks for newer versions on startup using the official SMAPI mod update API (`smapi.io/api/v3.0/mods`).
- **Manual Check**: One-click check via the top toolbar button, macOS menu bar (`⌘U`), or the sidebar Tools section.
- **Visual Status**: Shows orange `Update [Version]` pills directly in the mod table and badges the **Updates** category in the sidebar.

### 👤 Profile Management
- Maintain distinct profiles for different farms, challenge runs, or multiplayer setups.
- Real-time switching, profile duplication, and custom profile creation.
- Seamless SMAPI launching: links only active profile mods into `Selected Mods/` with `SMAPI_MODS_PATH` injection.

### 🛠️ In-App Mod Config Editor
- Inspect and modify mod `config.json` files without leaving the app.
- Preserves formatting and writes changes safely to disk.

### ℹ️ Native About & System Diagnostics
- Integrated **About Stardrop** sheet displaying:
  - App identity and native build version
  - Host architecture (`Apple Silicon arm64` / `Intel x86_64`)
  - Live environment diagnostics: detected Stardew Valley version, SMAPI version, Game folder, and Mods folder paths
  - Attribution to Floogen, ConcernedApe, and Pathoschild
  - Quick links to GitHub repository, documentation, SMAPI.io, Nexus Mods, and Issue tracker.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘R` | **Launch Game** with SMAPI |
| `⌘U` | **Check for Mod Updates** |
| `⌘,` | Open **Settings** |
| `⇧⌘N` | Open **Nexus Mods Account** sheet |
| `⌘S` | Toggle Sidebar |
| `Escape` | Dismiss active sheet / modal |

---

## Data Storage & Compatibility

`StardropMac` is designed to be 100% compatible with existing Stardrop installations. It directly shares and preserves your settings and profiles at:

```
~/Library/Application Support/Stardrop/
├── Data/
│   ├── Settings.json        # User preferences, folder paths, Nexus details
│   └── Profiles/            # Profile configurations (*.json)
│       └── Default.json
└── Logs/
    └── Stardrop.log
```

---

## Building & Running

### Prerequisites
- macOS 14.0+ (Sonoma or Sequoia)
- Xcode Command Line Tools (`xcode-select --install`) or Swift 5.9+ toolchain

### Build Standalone `.app` Bundle
Run the build script from the `StardropMac/` directory:
```bash
./build-mac-app.sh
```
The optimized release application bundle will be created at:
```
StardropMac/build/Stardrop.app
```

### Package Distribution `.dmg` Disk Image
Create a styled, compressed `.dmg` installer with drag-and-drop installation to `/Applications`:
```bash
./build-dmg.sh
```
Options:
- `./build-dmg.sh --skip-build`: Package existing `Stardrop.app` without recompiling.
- `./build-dmg.sh --open`: Mount and reveal the resulting DMG in Finder.
- `./build-dmg.sh -v 1.10.4`: Specify custom version tag.

Artifacts produced in `build/`:
- `Stardrop-<version>-macOS.dmg` (compressed release installer)
- `Stardrop.dmg` (convenience alias)
- `Stardrop-<version>-macOS.dmg.sha256` (checksum file)

### Launching the Application
```bash
# Open standalone bundle
open build/Stardrop.app

# Or run directly in debug/development mode
swift run
```

---

## Project Structure

```
StardropMac/
├── Package.swift                    # Swift Package Manager manifest
├── build-mac-app.sh                 # Release compilation & bundle script
├── build-dmg.sh                     # Styled DMG disk image packaging script
├── Sources/
│   └── StardropMac/
│       ├── StardropMacApp.swift     # App entrypoint & macOS menu bar
│       ├── Models/                  # Data structures (Mod, Profile, Settings, Manifest)
│       ├── Services/
│       │   ├── ModScannerService.swift      # Manifest scanner & parser
│       │   ├── SMAPILauncherService.swift   # Symlink manager & process launcher
│       │   ├── NexusService.swift           # Nexus Mods REST API client
│       │   ├── ModUpdateService.swift       # SMAPI mod update engine
│       │   ├── PathingService.swift         # Path resolution (Steam, GOG, App Support)
│       │   ├── ProfileService.swift         # Profile load/save
│       │   └── SettingsService.swift        # Settings.json persistence
│       ├── ViewModels/
│       │   └── AppState.swift               # Observable app state & business logic
│       └── Views/
│           ├── MainView.swift               # Root NavigationSplitView & Toolbar
│           ├── SidebarView.swift            # Categories, Profiles, Tools, Services
│           ├── ModTableView.swift           # Center unified mod table
│           ├── InspectorView.swift          # Mod inspector & details pane
│           ├── NexusAccountSheet.swift      # Nexus API connection & status modal
│           ├── AboutSheet.swift             # Native About & diagnostics dialog
│           ├── SettingsSheet.swift          # Game paths & preferences sheet
│           ├── NewProfileSheet.swift        # Profile creator sheet
│           └── ConfigEditorSheet.swift      # In-app config.json editor
└── build/
    └── Stardrop.app                         # Built macOS Application Bundle
```

---

## Credits & Attribution

- **Original Project Creator**: [Floogen](https://github.com/Floogen) — creator and maintainer of Stardrop.
- **SMAPI**: [Pathoschild](https://github.com/Pathoschild) and the Stardew Valley modding community.
- **Stardew Valley**: [Eric "ConcernedApe" Barone](https://www.stardewvalley.net/).
- **Translators**: Stardrop translations generously contributed by community members worldwide.

---

## License

Licensed under the **GNU General Public License v3.0 (GPLv3)**, in full compliance with the parent repository [Floogen/Stardrop](https://github.com/Floogen/Stardrop). See [LICENSE](../LICENSE).
