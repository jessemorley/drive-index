//
//  RaycastView.swift
//  DriveIndex
//
//  Raycast integration view
//

import SwiftUI

struct RaycastView: View {
    var body: some View {
        VStack {
            Text("Raycast")
                .font(DesignSystem.Typography.largeTitle)

            Text("Raycast integration settings will appear here")
                .secondaryText()
        }
        .placeholderView()
        .navigationTitle("Raycast")
    }
}

#Preview {
    RaycastView()
}
