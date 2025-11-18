# DriveIndex

Fast, offline searching of external drives for macOS using SQLite FTS5.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

A macOS app with a Spotlight-like floating search window that automatically indexes external drives when connected, storing file metadata in a shared SQLite database, providing sub-100ms full-text search across all indexed files, even when drives are offline.

## Features

- Auto drive index on file change (FSEvents) with customisable buffer interval
- Only re-scan modified directories (drive wear optimisation)
- File search in <100ms across drives, even when offline
- Global search shortcut
- Option to exclude specific extensions and directories
- Option to exclude or track drives
- Connected drive info at a glance
- PRAGMA optimise after 50+ file changes