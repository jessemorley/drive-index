# New Files to Add to Xcode Project

The following new files have been created and need to be added to the Xcode project:

1. **DriveIndex/DriveIndex/Models/AppSearchState.swift**
   - Observable class for shared search state between main toolbar and FilesView

2. **DriveIndex/DriveIndex/Windows/SettingsWindow.swift**
   - Custom NSWindow subclass for the Settings window

3. **DriveIndex/DriveIndex/Views/SettingsWindowView.swift**
   - SwiftUI view with tabbed settings interface

## How to Add Files

1. Open DriveIndex.xcodeproj in Xcode
2. Right-click on the appropriate group (Models, Windows, or Views)
3. Select "Add Files to DriveIndex..."
4. Navigate to and select the corresponding file
5. Ensure "Copy items if needed" is unchecked (files are already in place)
6. Ensure the DriveIndex target is checked
7. Click "Add"

Repeat for all three files.

## Alternative

If Xcode shows these files with a red/missing reference, you can:
1. Delete the reference (select and press Delete, choose "Remove Reference")
2. Re-add the file using the steps above

After adding all files, the project should build successfully.
