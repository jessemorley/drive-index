# DriveIndex

A lightweight macOS menu bar application that indexes external drives and provides fast, efficient file searching through a Raycast extension.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Menu Bar App
- **Auto-indexing**: Automatically indexes external drives when connected
- **Visual capacity display**: Shows drive capacity with color-coded progress bars
- **Manual scanning**: Trigger indexing for specific drives on demand
- **Exclusion patterns**: Configure directories and file types to skip
- **Connection status**: See which drives are currently connected
- **Background operation**: Runs silently in the menu bar (no Dock icon)

### Raycast Extension
- **Fast SQLite FTS5 search**: Sub-100ms queries across millions of files
- **Recent files**: Quick access to recently opened files
- **Offline support**: Search files even when drives are disconnected
- **Drive status indicators**: See which drives are online/offline
- **Quick actions**: Reveal in Finder, open files, copy paths

## Architecture

```
┌─────────────────────────────────────┐
│   DriveIndex (Swift Menu Bar)       │
│   - Monitors drive connections      │
│   - Indexes file systems            │
│   - Writes to SQLite database       │
└─────────────────┬───────────────────┘
                  │
                  │ Shared SQLite DB
                  │ ~/Library/Application Support/DriveIndex/index.db
                  │
┌─────────────────▼───────────────────┐
│   Raycast Extension (TypeScript)    │
│   - Queries SQLite with FTS5        │
│   - Displays search results         │
│   - Tracks file access history      │
└─────────────────────────────────────┘
```

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (for building the menu bar app)
- Raycast (for the search extension)

## Installation

### Menu Bar App

1. Clone this repository:
   ```bash
   git clone https://github.com/jessemorley/drive-index.git
   cd drive-index
   ```

2. Open `DriveIndex/DriveIndex.xcodeproj` in Xcode

3. Build and run the project (⌘R)

4. Grant Full Disk Access when prompted:
   - Open **System Settings** → **Privacy & Security** → **Full Disk Access**
   - Click the **+** button and add DriveIndex.app
   - This allows the app to index all files on your external drives

5. The app will appear in your menu bar

### Raycast Extension

1. Navigate to the raycast-extension directory:
   ```bash
   cd raycast-extension
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Run in development mode:
   ```bash
   npm run dev
   ```

4. The extension will automatically load in Raycast

## Usage

### First Time Setup

1. **Launch DriveIndex**: The menu bar icon will appear
2. **Connect an external drive**: The app will automatically begin indexing
3. **Monitor progress**: Click the menu bar icon to see indexing status
4. **Configure exclusions** (optional): Click the gear icon to set exclusion patterns

### Searching Files

1. **Open Raycast** (default: ⌥Space)
2. **Type "Search Drives"** or start typing your query
3. **Results appear instantly** as you type
4. **Actions**:
   - **Enter** or **⌘O**: Open file
   - **⌘R**: Reveal in Finder
   - **⌘C**: Copy full path

### Managing Exclusions

Default exclusions include:
- **Directories**: `.git`, `node_modules`, `Library`, `.Trashes`, system folders
- **File types**: `.tmp`, `.cache`, `.DS_Store`, `.localized`

To customize:
1. Click the menu bar icon
2. Click the gear icon (⚙️)
3. Edit the comma-separated lists
4. Click "Save"
5. Rescan drives for changes to take effect

## Performance

- **Indexing speed**: ~10,000 files/second (depends on drive speed)
- **Search speed**: <100ms for most queries (FTS5 with index)
- **Memory usage**: ~50-100 MB (menu bar app)
- **Database size**: ~100 KB per 1,000 files indexed

## Development

See [CLAUDE.md](CLAUDE.md) for detailed development guidance including:
- Architecture details
- Common commands
- Testing workflows
- Database schema modifications
- FTS5 query debugging

## Troubleshooting

### Menu bar app won't index drives
- Ensure Full Disk Access is granted in System Settings
- Check that the drive is mounted at `/Volumes/[DriveName]`
- Look for errors in Console.app (filter by "DriveIndex")

### Raycast extension shows "No Results"
- Verify the database exists: `~/Library/Application Support/DriveIndex/index.db`
- Check that drives have been indexed (menu bar app should show file counts)
- Grant Raycast permission to access the database when prompted

### Search returns irrelevant results
- FTS5 uses tokenization and stemming for search
- Use quotes for exact matches: `"exact filename"`
- Use Boolean operators: `vacation AND photos`, `document NOT draft`

## License

MIT License - See [LICENSE](LICENSE) for details

## Credits

Built to replace DriveBuddy with a faster, more efficient indexing solution using native SQLite FTS5.
