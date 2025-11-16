//
//  FilesView.swift
//  DriveIndex
//
//  View for recently indexed files
//

import SwiftUI

struct FilesView: View {
    var body: some View {
        VStack {
            Text("Files")
                .font(DesignSystem.Typography.largeTitle)

            Text("Recently indexed files will appear here")
                .secondaryText()
        }
        .placeholderView()
        .navigationTitle("Files")
    }
}

#Preview {
    FilesView()
}
