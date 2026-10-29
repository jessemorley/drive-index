//
//  AppStyle.swift
//  DriveIndex
//
//  The few app-specific style values with no system equivalent. See docs/STYLE.md.
//

import SwiftUI

extension DriveInfo {
    /// Sidebar dot and drive header status.
    var connectionStatusColor: Color { isConnected ? .green : .secondary }
}
