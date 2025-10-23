//
//  Color+Gotenx.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/23.
//

import SwiftUI

/// Centralized color constants for Gotenx UI
/// - Note: Reduces duplication and ensures consistent theming
extension Color {
    // Plot colors (matching existing MainCanvasView)
    static let gotenxRed = Color(red: 1.0, green: 0.3, blue: 0.3)      // Ion temperature
    static let gotenxBlue = Color(red: 0.3, green: 0.6, blue: 1.0)     // Electron temperature
    static let gotenxGreen = Color(red: 0.2, green: 0.8, blue: 0.4)    // Density
}
