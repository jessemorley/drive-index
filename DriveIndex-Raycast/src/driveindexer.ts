import { homedir } from "os";
import { readFileSync, existsSync, writeFileSync } from "fs";
import { join } from "path";

export interface SearchEntry {
  name: string;
  relativePath: string;
}

export interface DriveInfo {
  uuid: string;
  name: string;
  totalCapacity: number;
  lastSeen: Date;
  lastScanDate?: Date;
  fileCount: number;
}

export interface SearchResult {
  entry: SearchEntry;
  driveUUID: string;
  driveName: string;
  matchScore: number;
  isConnected: boolean;
}

export interface AccessHistory {
  driveUUID: string;
  relativePath: string;
  lastAccessed: number; // Timestamp
  accessCount: number;
}

export interface ClickHistory {
  files: AccessHistory[];
}

/**
 * Gets the path to the DriveIndexer SQLite database
 */
export function getDatabasePath(): string {
  return join(homedir(), "Library/Application Support/DriveIndexer/index.db");
}

/**
 * Gets the path to the click history file
 */
function getClickHistoryPath(): string {
  return join(homedir(), "Library/Application Support/DriveIndexer/click-history.json");
}

/**
 * Loads the click history from disk
 */
export function loadClickHistory(): ClickHistory {
  try {
    const historyPath = getClickHistoryPath();
    if (!existsSync(historyPath)) {
      return { files: [] };
    }
    const content = readFileSync(historyPath, "utf8");
    return JSON.parse(content) as ClickHistory;
  } catch (error) {
    console.error("Failed to load click history:", error);
    return { files: [] };
  }
}

/**
 * Saves the click history to disk
 */
function saveClickHistory(history: ClickHistory): void {
  try {
    const historyPath = getClickHistoryPath();
    writeFileSync(historyPath, JSON.stringify(history, null, 2), "utf8");
  } catch (error) {
    console.error("Failed to save click history:", error);
  }
}

/**
 * Records a file access in the click history
 */
export function recordFileAccess(driveUUID: string, relativePath: string): void {
  const history = loadClickHistory();
  const now = Date.now();

  // Find existing entry
  const existingIndex = history.files.findIndex(
    (f) => f.driveUUID === driveUUID && f.relativePath === relativePath
  );

  if (existingIndex >= 0) {
    // Update existing entry
    history.files[existingIndex].lastAccessed = now;
    history.files[existingIndex].accessCount++;
  } else {
    // Add new entry
    history.files.push({
      driveUUID,
      relativePath,
      lastAccessed: now,
      accessCount: 1,
    });
  }

  // Keep only the most recent 100 files
  history.files.sort((a, b) => b.lastAccessed - a.lastAccessed);
  history.files = history.files.slice(0, 100);

  saveClickHistory(history);
}

/**
 * Checks if a drive is currently mounted by checking /Volumes/
 */
export function isDriveMounted(driveName: string): boolean {
  try {
    const volumesPath = `/Volumes/${driveName}`;
    return existsSync(volumesPath);
  } catch {
    return false;
  }
}

/**
 * Gets the full path for a file on a drive
 */
export function getFullPath(driveName: string, relativePath: string): string {
  return `/Volumes/${driveName}/${relativePath}`;
}
