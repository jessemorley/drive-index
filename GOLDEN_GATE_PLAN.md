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

## Deferred until the numbers say otherwise

- Reading FSEvents changes since the last saved event ID when a drive is mounted, instead of rescanning the whole drive.
- Removing the ~122 `print` calls.
- Moving to Swift 6 / `@Observable`.

## Verification

- The build has no errors.
- Launch: the status menu has no Quick Search, the old hotkey does nothing, and Search, Drives and Duplicates work.
- Mounting a drive still re-indexes it and the drive list updates.
- Memory after the window closes is clearly lower than the Phase 0 baseline.
