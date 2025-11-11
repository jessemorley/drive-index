import React, { useState, useMemo, useRef } from "react";
import { List, Action, ActionPanel, Icon, Color, showToast, Toast, Keyboard, getPreferenceValues, open } from "@raycast/api";
import { useSQL } from "@raycast/utils";
import {
  getDatabasePath,
  SearchResult,
  isDriveMounted,
  getFullPath,
  recordFileAccess,
} from "./driveindexer";

interface Preferences {
  showDriveStatus: boolean;
  maxResults: string;
}

interface FileRow {
  id: number;
  drive_uuid: string;
  name: string;
  relative_path: string;
  drive_name: string;
}

interface DriveRow {
  uuid: string;
  name: string;
}

export default function Command() {
  const [searchText, setSearchText] = useState("");
  const [lastCompletedSearch, setLastCompletedSearch] = useState("");
  const previousResultsRef = useRef<SearchResult[]>([]);
  const preferences = getPreferenceValues<Preferences>();

  const DB_PATH = getDatabasePath();
  const maxResults = parseInt(preferences.maxResults || "100");

  // Query for drives to map UUIDs to names
  const { data: drives, isLoading: drivesLoading } = useSQL<DriveRow>(
    DB_PATH,
    "SELECT uuid, name FROM drives"
  );

  // Create a map of drive UUIDs to names
  const driveMap = new Map<string, string>();
  if (drives) {
    drives.forEach((drive) => driveMap.set(drive.uuid, drive.name));
  }

  // Main search query using FTS5 - use useMemo to stabilize values
  const { safeQuery, shouldExecute } = useMemo(() => {
    const trimmedSearch = searchText.trim();
    const hasValidSearch = trimmedSearch.length > 0;

    if (!hasValidSearch) {
      return {
        safeQuery: "SELECT 1 WHERE 0",
        shouldExecute: false,
      };
    }

    // Build query with embedded search term instead of using parameters
    // Escape single quotes for SQL string literal
    const escapedTerm = trimmedSearch.replace(/'/g, "''");
    // Remove special FTS5 characters that could cause syntax errors
    const cleanedTerm = escapedTerm.replace(/[":.]/g, '');
    // Add wildcard for prefix matching to find partial words
    const fts5Term = cleanedTerm + '*';

    const searchQuery = `
      SELECT
        f.id,
        f.drive_uuid,
        f.name,
        f.relative_path,
        d.name as drive_name
      FROM files_fts
      JOIN files f ON f.id = files_fts.rowid
      JOIN drives d ON d.uuid = f.drive_uuid
      WHERE files_fts MATCH 'name:${fts5Term}'
      ORDER BY bm25(files_fts)
      LIMIT ${maxResults}
    `;

    return {
      safeQuery: searchQuery,
      shouldExecute: true,
    };
  }, [searchText, maxResults]);

  const {
    data: searchResults,
    isLoading: searchLoading,
    permissionView,
  } = useSQL<FileRow>(DB_PATH, safeQuery, {
    execute: shouldExecute,
  });

  // If we need permission, show the permission view
  if (permissionView) return permissionView;

  // Update lastCompletedSearch when loading finishes
  React.useEffect(() => {
    if (!searchLoading && shouldExecute && searchResults !== undefined) {
      setLastCompletedSearch(searchText.trim());
    }
  }, [searchLoading, shouldExecute, searchText, searchResults]);

  // Clear previous results when search text changes significantly
  React.useEffect(() => {
    const currentSearch = searchText.trim();
    const lastSearch = lastCompletedSearch;

    // If current search doesn't start with last search, it's a new search - clear cache
    if (currentSearch && lastSearch && !currentSearch.startsWith(lastSearch) && !lastSearch.startsWith(currentSearch)) {
      previousResultsRef.current = [];
    }
  }, [searchText, lastCompletedSearch]);

  // Convert database rows to SearchResult format - compute directly, don't use state
  const results = useMemo(() => {
    // Don't show results if:
    // 1. No search text
    // 2. No search results from database
    if (!searchText.trim() || !searchResults) {
      previousResultsRef.current = [];
      return [];
    }

    // If loading and we have previous results, keep showing them
    if (searchLoading && previousResultsRef.current.length > 0) {
      return previousResultsRef.current;
    }

    // Only show results if they match the current search OR if we're still loading
    // This keeps previous results visible while new query runs
    if (lastCompletedSearch !== searchText.trim() && !searchLoading) {
      return previousResultsRef.current;
    }

    const newResults = searchResults.map((row) => ({
      entry: {
        name: row.name,
        relativePath: row.relative_path,
      },
      driveUUID: row.drive_uuid,
      driveName: row.drive_name,
      matchScore: 100, // SQLite FTS5 provides ranked results
      isConnected: isDriveMounted(row.drive_name),
    }));

    // Store results for next time
    previousResultsRef.current = newResults;
    return newResults;
  }, [searchText, searchResults, searchLoading, lastCompletedSearch]);

  const isLoading = drivesLoading || (shouldExecute && searchLoading);

  // Track whether we have received search results for the current query
  const hasSearchResults = shouldExecute && searchResults !== undefined && !searchLoading &&
    (!lastCompletedSearch || lastCompletedSearch === searchText.trim());

  const getSubtitle = (result: SearchResult): string => {
    // Get the parent directory path (everything except the filename)
    const pathParts = result.entry.relativePath.split("/");
    const parentPath = pathParts.slice(0, -1).join("/");

    return parentPath || "/";
  };

  const getAccessories = (result: SearchResult) => {
    const accessories = [];

    // Add drive name
    accessories.push({
      text: result.driveName,
    });

    // Show drive status icon
    if (preferences.showDriveStatus) {
      const mounted = result.isConnected;
      accessories.push({
        icon: {
          source: mounted ? Icon.CircleFilled : Icon.Circle,
          tintColor: mounted ? Color.Green : Color.SecondaryText,
        },
        tooltip: mounted ? "Drive Connected" : "Drive Offline",
      });
    }

    return accessories;
  };

  const handleRevealInFinder = async (result: SearchResult, fullPath: string) => {
    recordFileAccess(result.driveUUID, result.entry.relativePath);
    await open(fullPath, "Finder");
  };

  const handleOpenFile = async (result: SearchResult, fullPath: string) => {
    recordFileAccess(result.driveUUID, result.entry.relativePath);
    await open(fullPath);
  };

  return (
    <List
      isLoading={isLoading}
      onSearchTextChange={setSearchText}
      searchBarPlaceholder="Search files and folders across all drives..."
      throttle
      searchText={searchText}
    >
      {/* Show empty state when no search text and not loading */}
      {!searchText && !isLoading && (
        <List.EmptyView
          icon={Icon.MagnifyingGlass}
          title="Search Your Drives"
          description="Start typing to search files and folders across all indexed drives"
        />
      )}

      {/* Only show placeholder when we have search text */}
      {searchText && results.length === 0 && (
        <>
          {hasSearchResults && !isLoading ? (
            <List.EmptyView
              icon={Icon.MagnifyingGlass}
              title="No Results"
              description={`No files or folders matching "${searchText}"`}
            />
          ) : (
            <List.Item
              title=""
              subtitle=""
              accessories={[]}
            />
          )}
        </>
      )}

      {/* Show search results when available */}
      {results.map((result) => {
          const fullPath = getFullPath(result.driveName, result.entry.relativePath);
          const mounted = result.isConnected;

          return (
            <List.Item
              key={`${result.driveUUID}-${result.entry.relativePath}`}
              title={result.entry.name}
              subtitle={getSubtitle(result)}
              accessories={getAccessories(result)}
              icon={{
                source: Icon.Document,
                tintColor: Color.Blue,
              }}
              actions={
                <ActionPanel>
                  {mounted ? (
                    <>
                      <ActionPanel.Section title="File Actions">
                        <Action
                          title="Reveal in Finder"
                          icon={Icon.Finder}
                          onAction={() => handleRevealInFinder(result, fullPath)}
                        />
                        <Action
                          title="Open File"
                          icon={Icon.Document}
                          shortcut={Keyboard.Shortcut.Common.Open}
                          onAction={() => handleOpenFile(result, fullPath)}
                        />
                      </ActionPanel.Section>
                      <ActionPanel.Section title="Copy">
                        <Action.CopyToClipboard
                          title="Copy Full Path"
                          content={fullPath}
                          shortcut={Keyboard.Shortcut.Common.Copy}
                        />
                        <Action.CopyToClipboard
                          title="Copy Relative Path"
                          content={result.entry.relativePath}
                          shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
                        />
                        <Action.CopyToClipboard
                          title="Copy Filename"
                          content={result.entry.name}
                          shortcut={{ modifiers: ["cmd", "opt"], key: "c" }}
                        />
                      </ActionPanel.Section>
                    </>
                  ) : (
                    <ActionPanel.Section title="Copy">
                      <Action.CopyToClipboard
                        title="Copy Full Path"
                        content={fullPath}
                        shortcut={Keyboard.Shortcut.Common.Copy}
                      />
                      <Action.CopyToClipboard
                        title="Copy Relative Path"
                        content={result.entry.relativePath}
                        shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
                      />
                      <Action.CopyToClipboard
                        title="Copy Filename"
                        content={result.entry.name}
                        shortcut={{ modifiers: ["cmd", "opt"], key: "c" }}
                      />
                    </ActionPanel.Section>
                  )}

                  <ActionPanel.Section title="Info">
                    <Action
                      title={mounted ? "Drive Connected" : "Drive Offline"}
                      icon={mounted ? Icon.CircleFilled : Icon.Circle}
                      onAction={() =>
                        showToast({
                          style: mounted ? Toast.Style.Success : Toast.Style.Animated,
                          title: mounted
                            ? `${result.driveName} is connected`
                            : `${result.driveName} is offline`,
                          message: mounted ? `Available at /Volumes/${result.driveName}` : "Connect the drive to access files",
                        })
                      }
                    />
                  </ActionPanel.Section>
                </ActionPanel>
              }
            />
          );
        })}
    </List>
  );
}
