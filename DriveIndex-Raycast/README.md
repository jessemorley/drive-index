# Drive Indexer - Raycast Extension

A fast Raycast extension that searches indexed external drives using SQLite FTS5.

## Overview

This extension provides lightning-fast file search across all your indexed drives, even when they're disconnected. It uses the SQLite database created by the DriveIndexer menu bar app.

## Features

- ⚡ **Sub-100ms search** with SQLite FTS5
- 🔍 **Full-text search** with ranking
- 📝 **Recent files** when search is empty
- 💿 **Offline support** - search disconnected drives
- 🟢 **Drive status** indicators (green = connected, gray = offline)
- 📋 **Quick actions** - Reveal in Finder, open files, copy paths

## Installation

### Prerequisites

1. **DriveIndexer menu bar app** must be built and running
2. **At least one drive indexed** by DriveIndexer
3. **Raycast** installed

### Setup

1. Navigate to this directory:
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

1. **Open Raycast** (default: ⌥Space)
2. **Type "Search Drives"** or start typing your query
3. **Results appear instantly** as you type

### Actions

- **Enter** or **⌘O**: Open file
- **⌘R**: Reveal in Finder
- **⌘C**: Copy full path
- **⌘⇧C**: Copy relative path
- **⌘⌥C**: Copy filename only

### Recent Files

When the search is empty, you'll see up to 20 recently accessed files. This makes it easy to quickly return to files you've opened before.

## Configuration

### Preferences

Access preferences via Raycast settings:

- **Show Drive Status**: Display connection status indicators (default: true)
- **Maximum Results**: Limit number of search results (default: 100)

## How It Works

### Database Location

The extension reads the SQLite database created by DriveIndexer:
```
~/Library/Application Support/DriveIndexer/index.db
```

### Search Query

Uses SQLite FTS5 for fast full-text search:
```sql
SELECT f.*, d.name as drive_name
FROM files_fts
JOIN files f ON f.id = files_fts.rowid
JOIN drives d ON d.uuid = f.drive_uuid
WHERE files_fts MATCH ?
ORDER BY bm25(files_fts)
LIMIT ?
```

### Click History

Tracks recently accessed files in:
```
~/Library/Application Support/DriveIndexer/click-history.json
```

## File Structure

```
raycast-extension/
├── src/
│   ├── driveindexer.ts      # Core utilities (database path, click history)
│   ├── search-new.tsx       # Main search command (SQLite)
│   ├── search.tsx           # Legacy DriveBuddy search (kept for reference)
│   └── drivebuddy.ts        # Legacy utilities (kept for reference)
├── assets/
│   ├── command-icon.png     # Extension icon
│   └── command-icon.svg
├── package.json             # Extension manifest
├── tsconfig.json            # TypeScript config
└── README.md               # This file
```

## Technical Details

### Search Algorithm

1. User types query
2. `useSQL` hook queries SQLite FTS5 virtual table
3. FTS5 uses BM25 ranking algorithm
4. Results sorted by relevance
5. Drive names and connection status added
6. Results rendered in Raycast UI

### Performance

- **Query time**: <100ms for most searches
- **Database reads**: Direct SQLite access (no WASM overhead)
- **Memory usage**: Minimal (React hooks + Raycast API)

### Dependencies

- `@raycast/api` - Raycast extension API
- `@raycast/utils` - Utilities including `useSQL` hook
- ~~`fastest-levenshtein`~~ - No longer needed (legacy DriveBuddy)

Note: The `fastest-levenshtein` dependency can be removed if you delete the legacy `drivebuddy.ts` and `search.tsx` files.

## Troubleshooting

### "Permission Denied" Error

**Problem:** Raycast can't access the database

**Solution:** Grant permission when prompted, or reset in:
- System Settings → Privacy & Security → Files and Folders

### No Results Returned

**Problem:** Search returns empty

**Solutions:**
1. Verify database exists: `ls -lh ~/Library/Application\ Support/DriveIndexer/index.db`
2. Check drives are indexed in menu bar app
3. Try searching for a file you know exists
4. Check console for errors: View → Toggle Developer Tools

### Slow Search

**Problem:** Search takes >1 second

**Solutions:**
1. Check database size: `du -h ~/Library/Application\ Support/DriveIndexer/index.db`
2. If >500MB, consider adding exclusion patterns in menu bar app
3. Restart Raycast: Quit and relaunch

## Development

### Making Changes

1. Edit files in `src/`
2. Raycast will automatically reload
3. Check logs: View → Toggle Developer Tools

### Adding New Features

Example: Add file size to search results

1. Update SQL query in `search-new.tsx`:
   ```typescript
   const searchQuery = `
     SELECT f.id, f.drive_uuid, f.name, f.relative_path,
            f.size, d.name as drive_name
     FROM files_fts ...
   `;
   ```

2. Update `FileRow` interface:
   ```typescript
   interface FileRow {
     id: number;
     drive_uuid: string;
     name: string;
     relative_path: string;
     size: number;  // Add this
     drive_name: string;
   }
   ```

3. Display in UI:
   ```tsx
   <List.Item
     accessories={[
       { text: formatFileSize(row.size) },
       ...getAccessories(result)
     ]}
   />
   ```

### Testing

Test with various queries:
- Single word: `vacation`
- Multiple words: `vacation photos`
- Prefix: `doc*`
- Boolean: `vacation AND photos`
- Exact: `"vacation.jpg"`

## Migration from DriveBuddy

If you were using the old DriveBuddy extension:

1. **Backup click history** (if you want to keep it):
   ```bash
   cp ~/Library/Application\ Support/DriveBuddy/click-history.json \
      ~/Library/Application\ Support/DriveIndexer/click-history.json
   ```

2. **Update package.json** (already done):
   - Changed `"main": "src/search.tsx"` to `"main": "src/search-new.tsx"`

3. **Rebuild indexes**:
   - Use DriveIndexer menu bar app to index your drives
   - Old JSON indexes are no longer used

## License

MIT

## Credits

- Built with [Raycast Extensions API](https://developers.raycast.com)
- Inspired by DriveBuddy
- Uses SQLite FTS5 for search
