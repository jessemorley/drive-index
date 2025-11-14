# DriveIndex

Fast, offline searching of external drives for macOS using SQLite FTS5.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

A macOS app with a Spotlight-like floating search window that automatically indexes external drives when connected, storing file metadata in a shared SQLite database, providing sub-100ms full-text search across all indexed files, even when drives are offline.

**Architecture:** Swift floating panel app → SQLite FTS5 database

## License

MIT License - See [LICENSE](LICENSE) for details