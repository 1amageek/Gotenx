//
//  ScalarPlotType.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import SwiftUI
import GotenxUI

/// Time series scalar plot types
enum ScalarPlotType: String, CaseIterable, Identifiable {
    // Performance metrics
    case fusionGain = "Fusion Gain (Q)"
    case plasmaCurrent = "Plasma Current (Ip)"
    case bootstrapCurrent = "Bootstrap Current"

    // Power balance
    case auxiliaryPower = "Auxiliary Power"
    case ohmicPower = "Ohmic Power"
    case alphaPower = "Alpha Heating Power"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fusionGain:
            return "flame.fill"
        case .plasmaCurrent, .bootstrapCurrent:
            return "bolt.fill"
        case .auxiliaryPower, .ohmicPower, .alphaPower:
            return "sun.max.fill"
        }
    }

    var yAxisLabel: String {
        switch self {
        case .fusionGain:
            return "Q (dimensionless)"
        case .plasmaCurrent, .bootstrapCurrent:
            return "Current [MA]"
        case .auxiliaryPower, .ohmicPower, .alphaPower:
            return "Power [MW]"
        }
    }

    var color: Color {
        switch self {
        case .fusionGain:
            return Color(red: 1.0, green: 0.2, blue: 0.4)
        case .plasmaCurrent:
            return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .bootstrapCurrent:
            return Color(red: 0.5, green: 0.7, blue: 1.0)
        case .auxiliaryPower:
            return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .ohmicPower:
            return Color(red: 1.0, green: 0.4, blue: 0.2)
        case .alphaPower:
            return Color(red: 1.0, green: 0.3, blue: 0.5)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(0.2),
                color.opacity(0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Extract scalar data from PlotData
    func extractData(from plotData: PlotData) -> [Float] {
        switch self {
        case .fusionGain:
            return plotData.qFusion
        case .plasmaCurrent:
            return plotData.IpProfile
        case .bootstrapCurrent:
            return plotData.IBootstrap
        case .auxiliaryPower:
            return plotData.pAuxiliary
        case .ohmicPower:
            return plotData.pOhmicE
        case .alphaPower:
            return plotData.pAlphaTotal
        }
    }
}
