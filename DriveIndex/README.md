# DriveIndex

A lightweight macOS menu bar application that indexes external drives and provides fast, efficient file searching through a Raycast extension.

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

## Building the Menu Bar App

1. Open `DriveIndex.xcodeproj` in Xcode
2. Build and run the project (⌘R)
3. Grant Full Disk Access when prompted (needed for indexing all directories)
4. The app will appear in your menu bar

### Granting Full Disk Access

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button and add DriveIndex.app
3. This allows the app to index all files on your external drives

## Installing the Raycast Extension

1. Navigate to the `raycast-extension` directory
2. Run `npm install`
3. Run `npm run dev` to load the extension in Raycast dev mode
4. Search for "Drive Indexer" in Raycast

## Usage

### First Time Setup

1. **Launch DriveIndex**: The menu bar icon will appear
2. **Connect an external drive**: The app will automatically begin indexing
3. **Monitor progress**: Click the menu bar icon to see indexing status
4. **Configure exclusions** (optional): Click the gear icon to set exclusion patterns

### Searching Files

1. **Open Raycast** (default: ⌥Space)
2. **Type "Drive Indexer"** or use the configured hotkey
3. **Enter search query**: Results appear instantly
4. **Recent files**: Leave the search empty to see recently accessed files

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

## Database Schema

### Files Table
```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drive_uuid TEXT NOT NULL,
    name TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    size INTEGER,
    created_at INTEGER,
    modified_at INTEGER,
    is_directory BOOLEAN,
    UNIQUE(drive_uuid, relative_path)
);
```

### FTS5 Virtual Table (for search)
```sql
CREATE VIRTUAL TABLE files_fts USING fts5(
    name,
    relative_path,
    content='files',
    content_rowid='id',
    tokenize='porter unicode61'
);
```

### Drives Table
```sql
CREATE TABLE drives (
    uuid TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    last_seen INTEGER,
    total_capacity INTEGER,
    last_scan_date INTEGER,
    file_count INTEGER
);
```

## Performance

- **Indexing speed**: ~10,000 files/second (depends on drive speed)
- **Search speed**: <100ms for most queries (FTS5 with index)
- **Memory usage**: ~50-100 MB (menu bar app)
- **Database size**: ~100 KB per 1,000 files indexed

## Troubleshooting

### Menu bar app won't index drives
- Ensure Full Disk Access is granted in System Settings
- Check that the drive is mounted at `/Volumes/[DriveName]`
- Look for errors in Console.app (filter by "DriveIndex")

### Raycast extension shows "No Results"
- Verify the database exists: `~/Library/Application Support/DriveIndex/index.db`
- Check that drives have been indexed (menu bar app should show file counts)
- Grant Raycast permission to access the database when prompted

### Indexing is slow
- Reduce the number of files by adding exclusion patterns
- Check drive connection (USB 2.0 is slower than USB 3.0/Thunderbolt)
- Ensure the drive isn't being heavily used by other apps

### Search returns irrelevant results
- FTS5 uses tokenization and stemming for search
- Use quotes for exact matches: `"exact filename"`
- Use Boolean operators: `vacation AND photos`, `document NOT draft`

## Development

### Project Structure
```
DriveIndex/
├── DriveIndex/
│   ├── DriveIndexApp.swift         # App entry point
│   ├── Models/
│   │   ├── DatabaseManager.swift   # SQLite operations
│   │   ├── DriveMonitor.swift      # NSWorkspace integration
│   │   ├── FileIndexer.swift       # Async file scanning
│   │   └── IndexManager.swift      # Indexing coordinator
│   ├── Views/
│   │   ├── ContentView.swift       # Main popover view
│   │   ├── DriveListView.swift     # Drive list + capacity bars
│   │   └── SettingsView.swift      # Exclusion settings
│   └── Info.plist                  # LSUIElement = true
└── DriveIndex.xcodeproj

raycast-extension/
├── src/
│   ├── driveindexer.ts            # Core utilities
│   └── search-new.tsx             # Main search command
└── package.json
```

### Key Technologies
- **Swift Concurrency** (async/await, actors) for safe parallel processing
- **SwiftUI + MenuBarExtra** for native macOS UI
- **SQLite FTS5** for full-text search
- **NSWorkspace** for drive monitoring
- **Raycast useSQL hook** for database access

## License

MIT License - see LICENSE file

## Credits

Built to replace DriveBuddy with a faster, more efficient indexing solution.
