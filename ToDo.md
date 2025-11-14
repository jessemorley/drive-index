# To Do

## Features

### High

- [ ] Scan button always says "Rescan"
- [x] **FSEvents monitoring for indexing after file changes** ✅
- [x] Drive exclusion with track/exclude dialog on drive connect
- [ ] Phase 3: Directory Modification Caching (Advanced Optimization)
- [x] Excluded and un-indexed drives show under Indexed Drives
    - Change "Indexed Drives" to Drives
    - Change drive section colours:
        - Green with green 1px outline for connected and indexed
        - Grey with green outline for connected and unindexed
        - Grey for not connected and indexed
- [ ] Drive visual tweaks
    - Drive symbol before capacity symbol (like in the floating window)
    - 'Not Indexed' or 'Excluded' text next to capacity indicator (same style, but with orange text and outline) 
- [ ] Copy Drives styling to floating window
- [ ] Consider enabling PRAGMA optimize and occasionally running VACUUM for database size reduction


### Medium

- [ ] Keyboard navigation. (Pressing down from search highlights first result. Can move through and press enter to open in finder. Maybe an indication of what the action is going to be?)
- [ ] Settings window appear on top
- [ ] MacOS-style storage use summary
![image desc](/References/Screenshot%202025-11-13%20at%2010.48.41 am.png)

  
### Low

- [ ] Custom menubar icon
- [ ] Custom app icon

### Stretch

- [ ] Browse drives/file tree interface
- [ ] Implement Sparkle updates
- [ ] Cloud sync with CloudKit
- [ ] File exclusion sets (e.g. Capture One: cot, cof, cos, etc.)

## Bugs

- [ ] Database location button sizing
- [x] Drive window height doesn't match precisely
- [x] Popup occassionally doesn't appear where last moved to
- [x] Exclusions alphabetised on save (also error logged)
- [ ] Rejoin separate actions area for connected drives



### Phase 3: Directory Modification Caching (Advanced Optimization)

Core Strategy: Skip unchanged directory trees entirely
- Cache directory modified_at timestamps
- Compare directory mod dates before descending
- Skip entire subtrees when directory unchanged

Changes Required:

1. Schema addition:

`CREATE TABLE directory_cache (
    drive_uuid TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    modified_at INTEGER,
    PRIMARY KEY (drive_uuid, relative_path)
)`

2. FileIndexer.swift - Early directory skipping:
- Check directory_cache before calling enumerator.contentsOfDirectory
- Skip descendant enumeration if directory modified_at unchanged
- Update cache entries as directories are visited