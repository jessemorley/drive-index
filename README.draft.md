# DriveIndex

Fast, offline searching and housekeeping for external drives on macOS, built on SQLite FTS5.

![macOS](https://img.shields.io/badge/macOS-27%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

A lightweight native macOS app that lives in your menu bar and indexes the contents of your external drives. File metadata lives in a local SQLite database, allowing you to search, browse and inspect duplicate files even when they’re disconnected.

## Screenshots

<!-- Add screenshots to docs/screenshots/ and reference them here -->
<!-- ![Search](docs/screenshots/search.png) -->

## Features

### Indexing

- Automatic indexing on mount and on file change (FSEvents), with an adjustable buffer delay
- Incremental re-scans of modified directories only, to reduce drive wear
- Exclusion of specific drives, directories and file extensions
- PRAGMA optimize after 50+ file changes

### Search & Browse

- Full-text file search in under 100ms across all drives, online or offline
- Per-drive file browser and macOS-style storage breakdown

### Duplicates & Folder Compare

- Duplicate file detection across drives, with a configurable minimum file size
- Side-by-side folder comparison between two drives, with missing, changed and moved files highlighted, copying of missing files and trashing of extras
- Capture One cleanup of files that can be removed without losing edits (mask backups, superseded Settings folders, stray CaptureOne folders, session Trash), plus session sync between copies

## Raycast Extension

A companion Raycast extension (not yet published) searches the DriveIndex database straight from Raycast, so you can find files on any drive without opening the app.
