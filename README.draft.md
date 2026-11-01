# DriveIndex

Fast, offline searching and housekeeping for external drives on macOS, built on SQLite FTS5.

![macOS](https://img.shields.io/badge/macOS-27%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

A native macOS app built with SwiftUI, so it looks and behaves like part of the system. It lives in the menu bar, indexes external drives as they mount and keeps the index current as files change. File metadata lives in a local SQLite database, so you can search, browse and compare drives even when they're disconnected.

DriveIndex is lightweight and designed to stay running in the background, so drives are indexed without you having to open it.

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
- Raycast extension for quick search access (not yet published)

### Duplicates & Folder Compare

- Finds duplicate files across drives above a configurable size threshold
- Side-by-side folder comparison between two drives: shows missing, changed and moved files, copies missing files across, and moves extras to the Trash

### Capture One

- Syncs one copy of a Capture One session onto another
- Finds Capture One files that can be removed without losing edits: mask backups, superseded Settings folders, stray CaptureOne folders outside sessions, and session Trash

### App

- Launch at login, with a Dock icon only while a window is open
- Light, dark and auto appearance
