//
//  DriveStatusBadge.swift
//  DriveIndex
//
//  Status badge for drive connection state
//

import SwiftUI

struct DriveStatusBadge: View {
    let isConnected: Bool
    let isIndexing: Bool

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(AppTypography.statusText)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall)
        .background(statusColor.opacity(0.1))
        .cornerRadius(4)
    }

    private var statusColor: Color {
        if isIndexing { return .orange }
        if !isConnected { return .gray }
        return .green
    }

    private var statusText: String {
        if isIndexing { return "INDEXING" }
        if !isConnected { return "OFFLINE" }
        return "ONLINE"
    }
}

#Preview {
    VStack(spacing: 12) {
        DriveStatusBadge(isConnected: true, isIndexing: false)
        DriveStatusBadge(isConnected: true, isIndexing: true)
        DriveStatusBadge(isConnected: false, isIndexing: false)
    }
    .padding()
}
