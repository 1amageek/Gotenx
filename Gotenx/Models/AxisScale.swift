//
//  AxisScale.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import SwiftUI

/// Y-axis scale type
enum AxisScale: String, CaseIterable, Identifiable {
    case linear = "Linear"
    case logarithmic = "Log"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .linear: return "chart.line.uptrend.xyaxis"
        case .logarithmic: return "function"
        }
    }
}
