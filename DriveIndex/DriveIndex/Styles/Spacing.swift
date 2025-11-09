//
//  Spacing.swift
//  DriveIndex
//
//  Spacing constants for consistent layout
//

import SwiftUI

enum Spacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
    static let xxLarge: CGFloat = 24

    enum Container {
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let headerPadding = EdgeInsets(
            top: 12,
            leading: 16,
            bottom: 12,
            trailing: 16
        )
    }
}
