//
//  Typography.swift
//  DriveIndex
//
//  Typography system for consistent font styling
//

import SwiftUI

enum AppTypography {
    // MARK: - Headers

    static let appTitle = Font.system(.title2, design: .monospaced)
        .weight(.bold)

    static let sectionHeader = Font.system(.headline, design: .default)
        .weight(.semibold)

    // MARK: - Technical/Numeric Data

    static let technicalData = Font.system(.caption, design: .monospaced)

    static let fileCount = Font.system(.caption, design: .monospaced)

    static let capacityInfo = Font.system(.caption2, design: .monospaced)

    // MARK: - Status Text

    static let statusText = Font.system(.caption, design: .monospaced)
        .weight(.semibold)

    // MARK: - Helper/Descriptive Text

    static let helperText = Font.system(.caption, design: .default)

    static let infoText = Font.caption.weight(.medium)
}
