//
//  ThumbnailGenerator.swift
//  DriveIndex
//
//  Generates thumbnails for images and videos
//

import Foundation
import AppKit
import AVFoundation
import ImageIO
import QuickLookThumbnailing

enum ThumbnailError: Error {
    case unsupportedFileType
    case generationFailed(String)
    case fileNotFound
}

actor ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    private let thumbnailSize: CGFloat = 512
    private let jpegQuality: CGFloat = 0.8

    private init() {}

    // MARK: - Public API

    /// Generate thumbnail for a file
    func generateThumbnail(for fileURL: URL) async throws -> NSImage {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ThumbnailError.fileNotFound
        }

        let ext = fileURL.pathExtension.lowercased()

        // Determine file type and use appropriate generator
        if isImageFile(ext) {
            return try await generateImageThumbnail(for: fileURL)
        } else if isVideoFile(ext) {
            // Skip video thumbnails for now due to memory pressure issues
            throw ThumbnailError.unsupportedFileType
        } else if isPDFFile(ext) {
            return try await generateQuickLookThumbnail(for: fileURL)
        } else {
            throw ThumbnailError.unsupportedFileType
        }
    }

    /// Save thumbnail as JPEG to disk
    func saveThumbnail(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(
                using: .jpeg,
                properties: [.compressionFactor: jpegQuality]
              ) else {
            throw ThumbnailError.generationFailed("Failed to convert image to JPEG")
        }

        try jpegData.write(to: url)
    }

    /// Load thumbnail from disk
    func loadThumbnail(from url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    // MARK: - File Type Detection

    private func isImageFile(_ ext: String) -> Bool {
        let imageExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp",
            // RAW formats
            "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw"
        ]
        return imageExtensions.contains(ext)
    }

    private func isVideoFile(_ ext: String) -> Bool {
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi"]
        return videoExtensions.contains(ext)
    }

    private func isPDFFile(_ ext: String) -> Bool {
        return ext == "pdf"
    }

    // MARK: - Image Thumbnail Generation

    private func generateImageThumbnail(for url: URL) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // Use autoreleasepool to ensure IOSurface and other temporary objects are released immediately
                autoreleasepool {
                    guard let self = self else {
                        continuation.resume(throwing: ThumbnailError.generationFailed("Generator deallocated"))
                        return
                    }

                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                        continuation.resume(throwing: ThumbnailError.generationFailed("Failed to create image source for \(url.lastPathComponent)"))
                        return
                    }

                    // For RAW files, try to extract embedded thumbnail first (faster)
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,  // Create from full image if no embedded thumbnail
                        kCGImageSourceThumbnailMaxPixelSize: self.thumbnailSize,
                        kCGImageSourceShouldCache: false  // Don't cache, we're saving to disk
                    ]

                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                        // Log more detail about failure
                        let type = CGImageSourceGetType(imageSource)
                        let typeString = type.map { String($0 as String) } ?? "unknown"
                        continuation.resume(throwing: ThumbnailError.generationFailed("Failed to create thumbnail for \(url.lastPathComponent) (type: \(typeString))"))
                        return
                    }

                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    let image = NSImage(cgImage: cgImage, size: size)

                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Video Thumbnail Generation

    private func generateVideoThumbnail(for url: URL) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                // Use autoreleasepool to ensure VTPixelTransferSession and IOSurface objects are released
                autoreleasepool {
                    let asset = AVAsset(url: url)
                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                    imageGenerator.appliesPreferredTrackTransform = true
                    imageGenerator.maximumSize = CGSize(width: self.thumbnailSize, height: self.thumbnailSize)

                    Task {
                        do {
                            // Generate thumbnail at 1 second, or at 0 if video is shorter
                            let duration = try await asset.load(.duration)
                            let time = min(CMTime(seconds: 1, preferredTimescale: 60), duration)

                            let (cgImage, _) = try await imageGenerator.image(at: time)
                            let size = NSSize(width: cgImage.width, height: cgImage.height)
                            let image = NSImage(cgImage: cgImage, size: size)
                            continuation.resume(returning: image)
                        } catch {
                            continuation.resume(throwing: ThumbnailError.generationFailed("Failed to generate video thumbnail: \(error.localizedDescription)"))
                        }
                    }
                }
            }
        }
    }

    // MARK: - QuickLook Thumbnail Generation

    private func generateQuickLookThumbnail(for url: URL) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            let size = CGSize(width: thumbnailSize, height: thumbnailSize)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0

            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                if let error = error {
                    continuation.resume(throwing: ThumbnailError.generationFailed("QuickLook error: \(error.localizedDescription)"))
                    return
                }

                guard let thumbnail = thumbnail else {
                    continuation.resume(throwing: ThumbnailError.generationFailed("QuickLook returned nil thumbnail"))
                    return
                }

                let size = NSSize(width: thumbnail.cgImage.width, height: thumbnail.cgImage.height)
                let image = NSImage(cgImage: thumbnail.cgImage, size: size)
                continuation.resume(returning: image)
            }
        }
    }
}
