# DriveIndex

Fast, offline searching of external drives for macOS using SQLite FTS5.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

A macOS menu bar app that automatically indexes external drives when connected, storing file metadata in a shared SQLite database. A Raycast extension provides sub-100ms full-text search across all indexed files, even when drives are offline.

**Architecture:** Swift menu bar app → SQLite FTS5 database → TypeScript Raycast extension

## License

MIT License - See [LICENSE](LICENSE) for details
