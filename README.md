# Sift

A lightweight, resource-friendly Spotlight replacement for macOS with granular indexing control.

> **Status:** Early development — not yet stable for daily use.

## Why Sift?

Spotlight can peg your CPU with a dozen indexing processes and re-index files you'll never search for. Sift puts you in control:

- You choose exactly which directories are indexed, with per-directory settings.
- Indexing runs at background priority and yields CPU time between batches.
- Built-in rate limiting detects and pauses runaway directories before they affect system performance.
- A clean, Spotlight-inspired UI that stays out of your way.

## Features

| Feature | Detail |
|---|---|
| **Global hotkey** | Configurable (default `⌥Space`); in-app guide if you pick a system-reserved shortcut |
| **Type-filter prefixes** | `pdf: report`, `app: xcode`, `image: screenshot`, `code: main`, … |
| **Per-directory rules** | Recursive, hidden files, allowed extensions |
| **Large-index warning** | Warns before saving a rule that would index > 1 000 files |
| **File watchers** | FSEvents-based; re-indexes changed files automatically |
| **Runaway detection** | Alerts and pauses directories generating excessive events |
| **Signed & notarized** | Released as a Developer ID-signed DMG via GitHub Releases |

## Requirements

- macOS 15 Sequoia or later
- Xcode 16+ (to build from source)

## Getting started (from source)

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Clone
git clone https://github.com/sift-app/sift.git
cd sift

# 3. Generate the Xcode project and open it
make generate
open Sift.xcodeproj
```

Run the **Sift** scheme in Xcode. The app will appear in your menu bar.

## Usage

1. Press **⌥Space** (or your configured shortcut) to open the search bar.
2. Start typing a file name. Use `type:` prefixes to narrow results:
   - `pdf: budget` — only PDFs
   - `app: notion` — only applications
   - `image: logo` — images (jpg, png, heic, …)
   - `code: parser` — source files
3. Arrow keys navigate results; **Return** or a click opens the file. **Esc** closes.

## Configuration

Open **Sift → Settings…** (or press **⌘,** from the menu bar):

- **General** — Change the global shortcut.
- **Indexing** — Add directories to index. Each directory supports:
  - Recursive indexing (off by default)
  - Hidden-file inclusion (off by default)
  - Extension allow-list (blank = all types)

## Releasing

Releases are managed by [release-please](https://github.com/googleapis/release-please).
Merging a conventional-commit PR into `main` triggers:

1. release-please opens/updates a Release PR with a generated CHANGELOG.
2. Merging the Release PR creates a tag and fires the GitHub Actions build.
3. The workflow archives, signs, notarizes, and uploads a DMG to the GitHub Release.

### Required repository secrets

| Secret | Description |
|---|---|
| `CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application `.p12` certificate |
| `CERTIFICATE_P12_PASSWORD` | Password for the `.p12` file |
| `KEYCHAIN_PASSWORD` | Temporary keychain password (any random string) |
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID |
| `NOTARIZE_APPLE_ID` | Apple ID used for notarization |
| `NOTARIZE_TEAM_ID` | Same as `DEVELOPMENT_TEAM` |
| `NOTARIZE_APP_PASSWORD` | App-specific password for notarytool |

## Architecture

```
Sift/
├── SiftApp.swift                     – @main entry, Settings scene
├── AppDelegate.swift                 – menu bar, global hotkey, focus restoration
├── Search/
│   ├── SearchWindowController.swift  – NSPanel lifecycle
│   ├── SearchView.swift              – SwiftUI search UI
│   └── ResultRowView.swift           – result row
├── Indexing/
│   ├── IndexManager.swift            – actor; orchestrates all indexing
│   ├── SearchIndex.swift             – GRDB + FTS5 database
│   ├── FileWatcher.swift             – FSEvents wrapper
│   └── IndexWorker.swift             – background file scanning
├── Settings/
│   ├── SettingsView.swift
│   ├── GeneralSettingsView.swift     – hotkey + about
│   ├── IndexingSettingsView.swift    – rule list
│   └── AddRuleView.swift             – add / edit rule sheet
├── Models/
│   ├── IndexRule.swift
│   ├── SearchResult.swift
│   └── AppSettings.swift
└── Utilities/
    ├── FileTypeFilter.swift          – query parsing, FTS5 helpers
    └── ResourceMonitor.swift         – event-rate tracking
```

## Contributing

Pull requests are welcome. Please use [Conventional Commits](https://www.conventionalcommits.org/) so release-please can generate the CHANGELOG automatically.

## License

MIT — see [LICENSE](LICENSE).
