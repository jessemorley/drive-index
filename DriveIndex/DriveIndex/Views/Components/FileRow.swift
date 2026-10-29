//
//  FileRow.swift
//  DriveIndex
//
//  Search result display model, used by SearchView
//

import SwiftUI

struct FileDisplayItem: Identifiable {
    let id: Int64
    let name: String
    let relativePath: String
    let size: Int64
    let driveUUID: String
    let driveName: String
    let modifiedAt: Date?
    let createdAt: Date?
    let isConnected: Bool
    let isDirectory: Bool

    var kind: String {
        // Folders are always "Folder"
        if isDirectory {
            return "Folder"
        }

        let ext = (name as NSString).pathExtension.lowercased()

        // Common file type mappings
        switch ext {
        case "pdf": return "PDF Document"
        case "doc", "docx": return "Word Document"
        case "xls", "xlsx": return "Excel Spreadsheet"
        case "ppt", "pptx": return "PowerPoint Presentation"
        case "txt": return "Plain Text"
        case "rtf": return "Rich Text Document"
        case "jpg", "jpeg": return "JPEG Image"
        case "png": return "PNG Image"
        case "gif": return "GIF Image"
        case "svg": return "SVG Image"
        case "heic", "heif": return "HEIC Image"
        case "tiff", "tif": return "TIFF Image"
        case "bmp": return "BMP Image"
        case "webp": return "WebP Image"
        // Raw image formats
        case "nef": return "Nikon RAW Image"
        case "cr2", "cr3": return "Canon RAW Image"
        case "arw": return "Sony RAW Image"
        case "dng": return "Digital Negative"
        case "raf": return "Fujifilm RAW Image"
        case "orf": return "Olympus RAW Image"
        case "rw2": return "Panasonic RAW Image"
        case "pef": return "Pentax RAW Image"
        case "srw": return "Samsung RAW Image"
        case "raw": return "RAW Image"
        case "mp4", "mov": return "Video"
        case "mp3", "m4a", "wav": return "Audio"
        case "zip", "tar", "gz": return "Archive"
        case "dmg": return "Disk Image"
        case "app": return "Application"
        case "pkg": return "Installer Package"
        case "swift": return "Swift Source"
        case "py": return "Python Script"
        case "js": return "JavaScript"
        case "html": return "HTML Document"
        case "css": return "CSS Stylesheet"
        case "json": return "JSON File"
        case "md": return "Markdown Document"
        default:
            if ext.isEmpty {
                return "Document"
            }
            return ext.uppercased() + " File"
        }
    }

    var formattedSize: String {
        if isDirectory {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modifiedAt ?? createdAt else {
            return "—" // Em dash for search results without dates
        }

        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today, " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday, " + formatter.string(from: date)
        } else if calendar.dateComponents([.day], from: date, to: Date()).day ?? 0 < 7 {
            formatter.dateFormat = "EEEE, h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}
