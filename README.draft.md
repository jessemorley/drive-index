# DriveIndex

Fast, offline searching and housekeeping for external drives on macOS, built on SQLite FTS5.

![macOS](https://img.shields.io/badge/macOS-27%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

A native macOS app built with SwiftUI, so it looks and behaves like part of the system. It lives in the menu bar, indexes external drives as they mount and keeps the index current as files change. File metadata lives in a local SQLite database, so you can search, browse and compare drives even when they're disconnected. It's lightweight and designed to stay running in the background, so drives are indexed without you having to open it.

## Screenshots

<!-- Add screenshots to docs/screenshots/ and reference them here -->
<!-- ![Search](docs/screenshots/search.png) -->

## Features

### Indexing

- Automatic indexing on mount and on file change (FSEvents), with an adjustable buffer delay
- Re-scans only modified directories to reduce drive wear
- Exclude specific drives, directories and file extensions
- PRAGMA optimize after 50+ file changes

### Search & Browse

- Full-text file search in under 100ms across all drives, online or offline
- Per-drive file browser and macOS-style storage breakdown

### Duplicates & Folder Compare

- Finds duplicate files across drives above a configurable size threshold
- Side-by-side folder comparison between two drives: shows missing, changed and moved files, copies missing files across, and moves extras to the Trash
- Capture One cleanup: finds files that can be removed without losing edits (mask backups, superseded Settings folders, stray CaptureOne folders, session Trash) and syncs one copy of a session onto another

## Raycast Extension

A companion Raycast extension (not yet published) searches the DriveIndex database straight from Raycast, so you can find files on any drive without opening the app.
