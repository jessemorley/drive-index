# CloudKit Sync Implementation Plan for iOS App Support

## Overview
Add CloudKit synchronization to enable a future iOS app to search files indexed on macOS, with macOS as the authoritative source and iOS as read-only.

## Current State Analysis

### Database Architecture
- **Location:** `~/Library/Application Support/DriveIndex/index.db` (42MB)
- **Current scale:** 56,934 files across 3 drives
- **Tables:** files, files_fts (FTS5), drives, settings
- **Concurrency:** WAL mode, actor-based architecture, async/await

### Key Constraints
- FTS5 virtual tables cannot be synced directly to CloudKit
- Raycast extension is read-only (demonstrates viable pattern for iOS)
- No existing sync infrastructure
- macOS is the only source of indexed data (drives only connect there)

## Phase 1: CloudKit Infrastructure Setup (macOS)

### 1.1 Project Configuration
- Add CloudKit capability to Xcode project
- Configure CloudKit container in Apple Developer Portal
- Set up private database schema with custom record types:
  - `File` (driveUUID, name, relativePath, size, timestamps, isDirectory)
  - `Drive` (uuid, name, lastSeen, totalCapacity, lastScanDate, fileCount)
  - `Settings` (key, value)
- Add indexes for efficient queries (driveUUID, name)

### 1.2 Create CloudKit Sync Manager
- New `CloudKitSyncManager.swift` actor for thread-safe operations
- Implement CKSyncEngine-based sync (iOS 17+/macOS 14+)
- Handle authentication state (iCloud account availability)
- Manage sync tokens for incremental updates

### 1.3 Data Mapping Layer
- Create extensions to convert between local models and CKRecords:
  - `FileEntry` ↔ `CKRecord(recordType: "File")`
  - `DriveMetadata` ↔ `CKRecord(recordType: "Drive")`
  - Settings dictionary ↔ `CKRecord(recordType: "Settings")`
- Handle CloudKit reserved field names and type conversions

## Phase 2: Sync Logic Implementation (macOS)

### 2.1 Upload Flow
- After successful drive scan, push changed files to CloudKit
- Batch operations (400 records per CKModifyRecordsOperation)
- Track upload progress and handle partial failures
- Queue changes when offline, sync when network available

### 2.2 Conflict Resolution
- Implement last-write-wins strategy (macOS is authoritative)
- Handle concurrent scan scenarios gracefully
- Use server change tokens to avoid re-uploading unchanged data

### 2.3 Deletion Handling
- When drive is cleared/rescanned, mark files as deleted in CloudKit
- Implement tombstone records or zone-based deletion
- Clean up orphaned records periodically

### 2.4 Settings Sync
- Sync exclusion patterns to CloudKit when changed
- Pull settings on app launch to enable multi-Mac scenarios

## Phase 3: Local Database Enhancements (macOS)

### 3.1 Sync State Tracking
- Add `sync_metadata` table to track:
  - Last sync timestamp per drive
  - CloudKit record IDs for each file/drive
  - Pending changes queue (for offline resilience)
- Add `cloudkit_record_id` column to files and drives tables

### 3.2 Change Detection
- Track which records changed since last sync
- Use timestamps and checksums to minimize uploads
- Implement dirty flag system for efficient sync triggers

## Phase 4: iOS App Foundation

### 4.1 iOS Project Setup
- Create new iOS app target with CloudKit capability
- Share CloudKit container with macOS app
- Set up SwiftUI-based search interface

### 4.2 iOS Database Manager
- Port DatabaseManager to iOS with read-only modifications
- Create identical SQLite schema (files, drives, settings)
- Implement FTS5 index with same tokenizer config (porter unicode61)
- Set up automatic triggers for FTS5 sync

### 4.3 iOS CloudKit Subscriber
- Subscribe to CloudKit changes (CKQuerySubscription)
- Download new/modified records on app launch and background fetch
- Write CloudKit records to local SQLite
- Rebuild FTS5 index incrementally as data arrives

### 4.4 Initial Sync Flow
- Show progress UI for first-time sync (potentially 50k+ files)
- Fetch all records using CKFetchRecordZoneChangesOperation with pagination
- Build FTS5 index after initial data load completes
- Handle interruptions and resume capability

## Phase 5: Search Interface (iOS)

### 5.1 Search View
- Port search logic from Raycast extension
- Use same FTS5 query patterns (`name:term*` prefix matching)
- Display results with drive context (show as "offline")
- Handle empty states (no data synced yet)

### 5.2 Drive Browser
- Show synced drives with metadata (capacity, file count, last scan)
- Display connection status (always "offline" on iOS)
- Allow filtering by drive

### 5.3 Settings Sync
- Pull exclusion patterns from CloudKit
- Display read-only (or sync changes back if needed)

## Phase 6: Performance & Polish

### 6.1 Optimization
- Implement smart batching for large syncs
- Add background fetch for periodic updates
- Minimize battery impact with scheduled sync windows
- Cache search results for instant UI response

### 6.2 Error Handling
- Network error recovery with exponential backoff
- iCloud account issues (signed out, quota exceeded)
- User notifications for sync failures
- Sync status indicators in UI

### 6.3 Data Management
- Allow selective drive sync (user chooses which drives)
- Clear local cache option
- Show storage usage statistics

## Phase 7: Testing & Deployment

### 7.1 Testing Strategy
- Unit tests with mock CloudKit container
- Test with large datasets (100k+ files)
- Conflict resolution scenarios
- Offline/online transition handling
- FTS5 index rebuild verification

### 7.2 Deployment Preparation
- Update privacy policy for CloudKit usage
- Add iCloud entitlements
- Test on TestFlight with beta users
- Monitor CloudKit dashboard for errors

## Technical Considerations

### Data Model: What Syncs to iOS

**SHOULD sync:**
- Files metadata (name, path, size, timestamps, drive relationship) - enables search
- Drives metadata (uuid, name, capacity, last_scan_date, file_count) - shows available drives
- Settings (exclusion patterns) - consistent filtering across devices

**SHOULD NOT sync:**
- FTS5 virtual tables (files_fts) - cannot be synced, must rebuild locally on iOS
- Indexing operations state - macOS-specific
- Physical file paths - iOS cannot access macOS `/Volumes/`

**CLIENT-SPECIFIC:**
- Click history - each device tracks its own
- Drive connection status - computed dynamically (always offline on iOS)

### Challenges to Address

1. **FTS5 Rebuild**: iOS must recreate FTS5 virtual tables locally (cannot sync virtual tables)
   - Solution: Rebuild from synced files data with same triggers and tokenizer config

2. **Scale**: Current database has 57k files (42MB); initial sync will be significant
   - Solution: Progress UI, pagination, background fetch, resume capability

3. **CloudKit Limits**: Max 400 records per operation, 1MB per record (files are small, OK)
   - Solution: Batch operations appropriately

4. **Sync Conflicts**: Handle concurrent macOS scans while iOS is syncing
   - Solution: Last-write-wins (macOS authoritative), server change tokens

5. **Network Efficiency**: Minimize redundant uploads and battery impact
   - Solution: Change detection, dirty flags, scheduled sync windows

### Assumptions

- macOS 14+ / iOS 17+ for CKSyncEngine (or fallback to manual CKOperation-based sync)
- User has iCloud account with sufficient storage
- iOS app is read-only (no file scanning on mobile)
- macOS remains authoritative source for all indexed data

### Architecture Pattern

**macOS (Write-Primary):**
1. Keep existing local SQLite as source of truth
2. Add CloudKit sync layer that pushes changes after indexing
3. Sync on events: drive scan complete, settings changed
4. Use CKSyncEngine for automatic sync orchestration

**iOS (Read-Only with Local FTS5):**
1. Receive CloudKit changes → Write to local SQLite
2. Rebuild local FTS5 index from synced files
3. No drive scanning capability (display-only mode)
4. Show drives as "offline" but searchable

This follows the pattern already proven by the Raycast extension: read-only access to indexed data works well for search use cases.

### Sync Strategy

**Files Table:**
- CloudKit Record Type: `File`
- Key fields: driveUUID, name, relativePath, size, timestamps, isDirectory
- Sync strategy: Zone-based sync (consider one zone per drive or single shared zone)
- Conflict resolution: Last-write-wins (macOS is authoritative)
- Optimization: Use CKQueryOperation with cursors for pagination

**Drives Table:**
- CloudKit Record Type: `Drive`
- Key fields: uuid, name, lastSeen, totalCapacity, lastScanDate, fileCount
- Sync strategy: Small dataset, full sync acceptable
- Reference: Files reference their Drive record

**Settings Table:**
- CloudKit Record Type: `Settings`
- Sync strategy: Simple key-value sync
- Consideration: Settings affect indexing; changes should trigger re-index on macOS

**FTS5 Index:**
- Not synced directly
- iOS rebuilds from synced files:
  - On first launch
  - When significant file changes detected
  - Background rebuild for incremental updates
- Use same triggers and tokenizer config as macOS

### Performance Optimizations

- Batch CloudKit operations (max 400 records)
- Use CKFetchRecordZoneChangesOperation for incremental sync
- Show progress UI during initial sync (potentially 57k+ records)
- Track last sync timestamp per device
- Use CKServerChangeToken for efficient change fetching
- Handle deletions via tombstone records or zone sync

## Estimated Timeline

- **Phase 1-3** (macOS sync): ~2-3 weeks
- **Phase 4-5** (iOS app): ~2-3 weeks
- **Phase 6-7** (polish & testing): ~1-2 weeks
- **Total**: ~6-8 weeks for full implementation

## References

### Key Files to Modify/Create (macOS)
- NEW: `DriveIndex/DriveIndex/Models/CloudKitSyncManager.swift`
- MODIFY: `DriveIndex/DriveIndex/Models/DatabaseManager.swift` (add sync tracking)
- MODIFY: `DriveIndex/DriveIndex/Models/IndexManager.swift` (trigger sync after indexing)
- NEW: `DriveIndex/DriveIndex/Models/CloudKitRecordExtensions.swift` (mapping layer)

### Key Files to Create (iOS)
- NEW: iOS app target in Xcode project
- NEW: iOS version of DatabaseManager (read-only variant)
- NEW: iOS CloudKitSubscriber for receiving changes
- NEW: iOS search interface (SwiftUI views)

### Database Schema Reference
- Location: `DatabaseManager.swift:82-156` (createSchema method)
- Current tables: files, files_fts, drives, settings
- Indexes: idx_files_drive, idx_files_modified, idx_files_name

### Current Architecture
- Actors: DatabaseManager, FileIndexer (thread-safe)
- MainActor: IndexManager, DriveMonitor (UI coordination)
- Notifications: `.shouldIndexDrive` for coordination
- Concurrency: WAL mode, async/await throughout
- Batch inserts: 1,000 files at a time

---

*Plan created: 2025-11-10*
*Target: Enable iOS app to search files indexed on macOS via CloudKit sync*
