# Release Guide for DriveIndex

This document explains how to create and distribute test builds of DriveIndex using GitHub Actions.

## Quick Start

To create a new test release:

```bash
# Create and push a tag
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```

GitHub Actions will automatically build the app and create a release within ~5-10 minutes.

## Release Workflow

### 1. Prepare Your Changes

Ensure all changes are committed and pushed to the main branch:

```bash
git add .
git commit -m "Your changes"
git push origin main
```

### 2. Create a Version Tag

Choose a version number following semantic versioning:

- **Beta releases**: `v1.0.0-beta.1`, `v1.0.0-beta.2`, etc.
- **Alpha releases**: `v1.0.0-alpha.1`, `v1.0.0-alpha.2`, etc.
- **Release candidates**: `v1.0.0-rc.1`, `v1.0.0-rc.2`, etc.
- **Production releases**: `v1.0.0`, `v1.1.0`, `v2.0.0`, etc.

Create and push the tag:

```bash
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```

### 3. Monitor the Build

1. Go to your GitHub repository
2. Click on the "Actions" tab
3. Watch the "Release" workflow progress
4. The workflow takes ~5-10 minutes to complete

### 4. Release is Published

Once complete:
- A new release appears in the "Releases" section
- The release includes `DriveIndex.zip` for download
- Beta/alpha releases are marked as "Pre-release"
- Production releases are marked as "Latest"

## Distributing to Testers

### Share the Release

Send testers the link to your releases page:
```
https://github.com/YOUR_USERNAME/drive-index/releases
```

Or share the direct download link from the specific release.

### Installation Instructions for Testers

Include these instructions when sharing test builds:

```
Installation Instructions:

1. Download DriveIndex.zip from the release
2. Unzip the file (usually automatic on macOS)
3. Remove quarantine attribute - Open Terminal and run:
   xattr -cr ~/Downloads/DriveIndex.app
   (Replace path if you downloaded elsewhere)
4. Move DriveIndex.app to your Applications folder
5. FIRST LAUNCH: Right-click DriveIndex.app and select "Open"
6. Click "Open" in the security dialog
7. The app will run normally for all future launches

Why these steps?
This is an ad-hoc signed test build. macOS:
- Adds a "quarantine" flag to downloaded files (causes "damaged" error)
- Requires right-click to open unsigned apps on first launch

The 'xattr -cr' command removes the quarantine flag. This is safe
and standard for developer test builds.
```

## Version Numbering Guide

Follow [Semantic Versioning](https://semver.org/):

- `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
- **MAJOR**: Breaking changes or major new features
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, small improvements

### Pre-release Suffixes

- `-alpha.N`: Early testing, unstable
- `-beta.N`: Feature complete, testing for bugs
- `-rc.N`: Release candidate, final testing

Examples:
- `v1.0.0-alpha.1` → First alpha of version 1.0.0
- `v1.0.0-beta.1` → First beta of version 1.0.0
- `v1.0.0-rc.1` → First release candidate
- `v1.0.0` → Production release

## Automated Workflows

### Build Workflow (`.github/workflows/build.yml`)

**Triggers**: Push to `main` or `develop` branches, or pull requests

**Purpose**: Validates that the app builds successfully

**Does not**: Create releases or artifacts

### Release Workflow (`.github/workflows/release.yml`)

**Triggers**: Push of any tag starting with `v` (e.g., `v1.0.0-beta.1`)

**Actions**:
1. Builds DriveIndex in Release configuration
2. Creates a ZIP archive
3. Creates a GitHub Release
4. Uploads DriveIndex.zip to the release
5. Marks beta/alpha as pre-release automatically

## Troubleshooting

### Build Fails

Check the Actions tab for error logs. Common issues:
- Xcode version mismatch (workflow uses Xcode 15.4)
- Build errors in code
- Missing dependencies

### Tag Already Exists

If you need to re-release the same version:

```bash
# Delete local tag
git tag -d v1.0.0-beta.1

# Delete remote tag
git push origin :refs/tags/v1.0.0-beta.1

# Create and push new tag
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```

### Release Not Appearing

- Ensure tag starts with `v` (e.g., `v1.0.0`, not `1.0.0`)
- Check GitHub Actions for workflow errors
- Verify you pushed the tag: `git push origin v1.0.0-beta.1`

## Future Enhancements

### Add Notarization (Requires Apple Developer Account)

When you have an Apple Developer Program membership ($99/year):

1. Generate Developer ID Application certificate
2. Add secrets to GitHub:
   - `APPLE_CERTIFICATE_BASE64`
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_ID`
   - `APPLE_ID_PASSWORD`
   - `APPLE_TEAM_ID`
3. Update workflow to notarize and staple
4. Testers can double-click to open (no security dialog)

### Create DMG Instead of ZIP

Replace the ZIP creation with a DMG for more professional distribution:
- Custom background image
- Applications folder shortcut
- Drag-to-install interface

## Questions?

Check the GitHub Actions documentation:
- [GitHub Actions for macOS](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
- [Xcode Build Actions](https://github.com/marketplace?type=actions&query=xcode)
