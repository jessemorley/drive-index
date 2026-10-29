# Golden Gate Plan

Branch: `golden-gate` (off `main` @ `c1ec11c`). Target: macOS 27.

Goals:
1. Simplify the interface: remove the popup search bar and anything left over or unused.
2. Cut unnecessary bloat so the app can always be running in the background.

The app is already event-driven: no polling timers, and duplicate hashing only starts when the user asks. Running cost comes from what it keeps in memory after the window closes and how much work each file change triggers.

Commit each step separately, with a before/after memory number.

## Phase 0: Baseline

Measure with one drive mounted, in three states: just launched, window closed for 5 minutes, and while copying a folder onto the drive.

- Memory: `footprint -p <pid>`
- CPU/energy: `ps -o %cpu,rss -p <pid>`, Activity Monitor Energy tab

Reference: the installed build (`/Applications/DriveIndex.app`) measured 64 MB footprint and 0% CPU at idle. Quit it before running a dev build, because both share the same database.

## Phase 1: Remove the popup search and the global hotkey

Decision: remove the hotkey entirely (no repurposing).

Delete (all are only used by the popup):
- `Windows/FloatingPanel.swift`
- `Views/ContentView.swift` (also holds `EmptyStateView`, `PendingChangesView`, `CompletionView`, `ActiveIndexingView`, `StatusBarContainer`)
- `Views/SearchResultsView.swift`, `Views/Components/SearchBar.swift`
- `Views/DriveListView.swift`, `Views/Components/DriveStatusBadge.swift`
- `Models/HotkeyManager.swift`, `Models/KeyboardShortcut.swift`, `Views/ShortcutView.swift`, `Views/Components/ShortcutRecorder.swift`

`AppDelegate.swift`:
- Remove `floatingPanel`, `setupHotkey()`, `togglePanel`/`showPanel`/`closePanel`/`createPanel`, `windowDidResignKey`, the `FloatingPanelDelegate` extension, and the `searchWindowDidShow` / `openMainWindow` notifications and observer.
- Remove "Quick Search" from the status menu.

Settings: remove `.shortcuts` from `SettingsNavigationItem` and `SettingsWindowView`.

Things to know before you start:
- `CapacityBar` is defined in `DriveListView.swift` but used by `DrivesView.swift`. Move it into `DrivesView.swift` before deleting.
- The Xcode project lists files explicitly (objectVersion 56). Each Swift file has 4 single-line entries matching `/* Name.swift`. Remove them, then run `plutil -lint` on the project file.
- ContentView's `driveIndexingComplete` listener is redundant because `DriveMonitor` already reloads drives on that notification.
- Build: `xcodebuild -project DriveIndex/DriveIndex.xcodeproj -scheme DriveIndex -configuration Debug build`

## Phase 2: Simplify the interface

- Sidebar (`NavigationItem` / `MainWindowView`): remove `.indexingTest` ("Temporary test"). Keep `IndexingView`, because Settings uses it. Remove the `.settings` nav item, which shows an `EmptyView`; there's a separate Settings window.
- Settings: remove `.raycast` and `Views/RaycastView.swift` (placeholder). That leaves Appearance, Indexing, Duplicates and Advanced.
- Unused code:
  - `Styles/MacOSDesign.swift` is never referenced.
  - The `FilesView` struct is unused, but `SearchView` uses `FileRow` and `FileDisplayItem` from that file. Move those two into `Views/Components/FileRow.swift` and delete the rest.
  - `Views/FileBrowserContainerView.swift` is untracked, isn't in the project, and nothing references it. Decide whether to keep it.
- Result: the sidebar shows Search, Drives and Duplicates, and the status menu has Show Main Window and Quit.

## Phase 3: Lower the cost of running in the background

1. **Free the windows when they close.** Both windows set `isReleasedWhenClosed = false`, and `AppDelegate` keeps them, so the SwiftUI view tree and its state stay in memory. In `windowWillClose`, set `mainWindow` / `settingsWindow` to nil and clear `StorageCache.shared` and `FileBrowserCache.shared`.
2. **Show the Dock icon only while a window is open.** `LSUIElement = YES`, but `applicationDidFinishLaunching` forces `.regular` and opens the main window on every launch. Switch to `.regular` when a window opens and to `.accessory` when the last one closes, and don't open the window at launch. Optional: add "Launch at Login" with `SMAppService.mainApp`.
3. **Use folder-level file events.** `FSEventsMonitor` sets `kFSEventStreamCreateFlagFileEvents`, which sends one event per file, delivered on the main queue. The delta scan only uses parent folders anyway (`FileIndexer.indexDriveDelta`). Remove the flag, treat each event path as the folder itself rather than taking its parent, and remove the per-file flag filter in `fsEventsCallback`.
4. **Avoid loading every file on a drive for each small change.** `DatabaseManager.getExistingFiles` loads every `id, relative_path, modified_at` row for the drive on every delta scan. When FSEvents supplies the changed folders, query only the files in those folders. Keep the full load for the scan when a drive is mounted.
5. **Shrink the SQLite cache.** Delete `PRAGMA cache_size = 10000` (about 40 MB) to fall back to SQLite's default of about 2 MB, then check that search speed holds.
6. **Raise the deployment target.** Change `MACOSX_DEPLOYMENT_TARGET` from 14.0 to 27.0 in both configurations. There are no `#available` checks to clean up. Check whether the `.safeAreaInset` toolbar-transparency workaround is still needed.

Test items 3 and 4 with a real drive: copy, rename and delete files, then confirm search reflects the changes.

## Phase 4: Cleanup, cheaper mount scans, Swift 6

Phase 3 results (Debug build, Jesse T72 mounted): 18 MB after launching with no window, 44 MB with the main window open, 42 MB after the window has been closed for 5 minutes. A mount scan still loads all ~93k file rows and ~5.7k folder rows; memory 2 minutes after a remount measured 45–72 MB.

Same rules as Phase 3: commit each item separately with a before/after number, and get approval before each commit. Do the items in this order. Item 1 is quick; items 3 and 4 are the large ones.

1. **Loose ends from Phase 3.** Done in `d16171c` (build warnings 7 → 5).
   - The About text says "macOS 13+" in `DriveIndexApp.swift` and `Views/AboutWindow.swift`. Change it to "macOS 27+".
   - `.claude/CLAUDE.md` says the main window uses `.safeAreaInset` to keep the toolbar transparent. On macOS 27 a `ZStack` keeps it transparent too (checked by eye in Phase 3). The inset is kept so the indexing overlay pushes content up instead of covering the last rows. Update the note.
   - Delete the `toolbar?.showsBaselineSeparator = false` lines in `Windows/MainWindow.swift` and `Windows/SettingsWindow.swift`. The property was deprecated in macOS 15 ("No longer supported"), so the line does nothing. Check by eye that the toolbars look unchanged.
   - Re-check Phase 1 on the current build: the status menu has no Quick Search, the old hotkey does nothing, and Search, Drives and Duplicates work.
   - Delete the leftover test folder `/Volumes/Jesse T72/_dittest_offline`. This is done by hand, not by the agent.
   - Number for the commit: build warnings before → after.

2. **Replace the `print` calls with `os.Logger`.** There are 122 after item 3. Most are in `DatabaseManager` (33), `FSEventsMonitor` (18), `IndexManager` (17), `FileIndexer` (16), `DriveMonitor` (12) and `HashWorker` (12).
   - Add one `Logger(subsystem: "<bundle id>", category: "<type>")` per file, as a `private let` at file scope. Don't write a wrapper.
   - Errors and failed recovery → `.error`. Unexpected but handled → `.warning`. Mount, scan start and finish, and scan counts → `.info`. Per-event and per-batch noise ("Buffering N FSEvents", "upsertDriveMetadata called") → `.debug`, or delete it.
   - Delete prints that only repeat the line before them.
   - `.debug` messages are free when nobody is listening, so the testing logs stay available through `log stream --level debug --predicate 'subsystem == "<bundle id>"'`. Update the scratch test scripts, which read stdout, to use this.
   - Numbers for the commit: `print` count 119 → 0, and the binary size.

3. **Mount scans from FSEvents history.** Today, mounting a drive runs a delta scan that loads every file and folder row for the drive. It then compares each folder's modification time, even when nothing changed. Instead, ask FSEvents what changed since the last indexed event and scan only those folders.
   - **Store** `fsevents_last_id` and `fsevents_volume_uuid` as two new nullable columns on `drives`. Add them with `ALTER TABLE` in the existing schema setup, and leave old rows NULL.
   - **Stream setup:** create the stream with `FSEventStreamCreateRelativeToDevice` (device from `statfs` on the mount point). Use the event ID relative to that device, and get the volume's event-store UUID from `FSEventsCopyUUIDForDevice`.
   - **On mount:** if the saved UUID matches and a saved ID exists, start the stream with `sinceWhen` = the saved ID. Collect folders until an event has `kFSEventStreamEventFlagHistoryDone`. Then run the existing `changedPaths` delta scan on the union.
   - **Fall back** to today's mount scan when any of these is true:
     - No saved ID, or the UUID doesn't match.
     - `FSEventsCopyUUIDForDevice` returns nil (no event store, e.g. FAT/exFAT, or `.fseventsd/no_log`).
     - Any replayed event has `MustScanSubDirs`, `UserDropped`, `KernelDropped`, `EventIdsWrapped` or `RootChanged`.
   - **When to save the ID:** only after a scan finishes. Save the highest event ID whose folders that scan included, never the stream's latest ID. Saving earlier could skip events still sitting in the buffer. A cancelled scan saves nothing, which matches the cancellation fix (`90a86c0`).
   - **IndexManager:** a history scan replaces the full mount scan, so treat it as a mount scan in the rule that stops an FSEvents request from narrowing a mount scan (`indexingIsMountScan`). If live events arrive during a history scan, restart it with the union of both sets of folders rather than switching to a full scan.
   - **Known limit:** changes made by a computer that doesn't log FSEvents (Windows, Linux) leave no history, so they're missed until a full scan. The Drives view already has a Rescan button. Make Rescan force today's full mount scan. Add the following comment: `// ponytail: history can miss non-Mac writes; Rescan forces a full mount scan`.
   - **Check first:** confirm Jesse T72's file system with `diskutil info` and that it has `/.fseventsd`. Without it the whole item falls back, and the gain should be measured on a drive where it doesn't.
   - **Test on Jesse T72:**
     - Quit the app, change files (copy, rename, delete, including at the root) and remount. Search reflects each change, and the log shows a history scan, not a full one.
     - Clear `fsevents_last_id` and remount: the log shows a full mount scan, and nothing is lost.
     - Remount with no changes: rows loaded is about 0.
     - Before relaunching, compare the row count with the count before the test.
   - **Numbers:** rows loaded per mount (~93k → changed folders only); memory 2 minutes after a remount (45–72 MB →); time from mount until the scan finishes.
   - **Done** in PRs #2–#5, which form a stack on `golden-gate`. Results (Debug build, Jesse T72, before = the `golden-gate` build):
     - Rows loaded per remount: 92,987, loaded twice because an FSEvents event restarted the scan → 10–17.
     - Time from mount until the scan finishes: 19.2 s → about 1 s. Most of the second is spent waiting for fseventsd to open the drive's event store.
     - Memory 2 minutes after a remount: 40 MB → 41 MB, unchanged.
     - All the tests above pass. A launch with the drive connected also replays history.
   - **Found during the work:**
     - `upsertDriveMetadata` used `INSERT OR REPLACE`, which would have reset the cursor on every mount. It now uses `ON CONFLICT DO UPDATE`.
     - A newer FSEvents scan dropped the folders of the scan it cancelled. It now scans the union of both (#3).
     - Right after a mount, `FSEventsCopyUUIDForDevice` returns nil for 0.9–3.2 s. The app now waits up to 10 s when the drive has `/.fseventsd`.
     - `FSEventsGetLastEventIdForDeviceBeforeTime` takes a POSIX time. Passed a `CFAbsoluteTime`, it returns 0.
     - History isn't delivered in event-ID order and can include file paths. The cursor uses the highest ID, and file paths are mapped to their folders.
     - A data race on `visitedPaths` in `indexDriveDelta`, already on `golden-gate`, crashed a mount scan that found 512 changed folders (#5).
   - **By hand:** delete the test files `/Volumes/Jesse T72/_dittest_history/` and `/Volumes/Jesse T72/_dittest_root_new.txt`.

4. **Swift 6 and `@Observable`.** `SWIFT_VERSION = 5.0` in both configurations. Only two classes are `ObservableObject` (`DriveMonitor`, `IndexManager`), with 23 `@StateObject` / `@ObservedObject` / `@EnvironmentObject` uses across the views.
   - **4a. Strict concurrency, still on Swift 5.** Set `SWIFT_STRICT_CONCURRENCY = complete` and fix the warnings. Expect most of them in the FSEvents C callback, the `DispatchQueue` hops and the `[weak self]` captures already flagged (`IndexManager.swift:126`, `:267`). Don't use `@unchecked Sendable` or `nonisolated(unsafe)` unless a comment explains why it's safe. Commit with the warning count before → after.
   - **4b. Switch to Swift 6** (`SWIFT_VERSION = 6.0`) once 4a builds without warnings. Run `plutil -lint` on the project file afterwards.
   - **4c. Move to `@Observable`.**
     - `DriveMonitor` and `IndexManager` become `@Observable` and drop `@Published`.
     - `@StateObject` → `@State`.
     - `@EnvironmentObject` → `@Environment(Type.self)`.
     - `@ObservedObject` → a plain property, or `@Bindable` where a binding is needed.
     - `.environmentObject(x)` → `.environment(x)`.
     - Views then refresh only on the properties they read. Measure CPU with the main window open during a 150-file copy, which drives the indexing overlay. Note the number even if it doesn't change.
   - Repeat the Jesse T72 test from item 3 after 4c, since the indexing state and the overlay depend on these classes.

## Verification

- The build has no errors.
- Launch: the status menu has no Quick Search, the old hotkey does nothing, and Search, Drives and Duplicates work.
- Mounting a drive still re-indexes it and the drive list updates.
- Memory after the window closes is clearly lower than the Phase 0 baseline.
- Phase 4: no `print` calls left, and Swift 6 builds without warnings.
- Phase 4: on a drive with FSEvents history, a remount with no changes loads about no rows, and changes made while the app was quit appear in search after the remount.
- Phase 4: Rescan still runs a full mount scan.
