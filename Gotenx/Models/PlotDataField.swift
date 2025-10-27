//
//  PlotDataField.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import SwiftUI
import GotenxUI

/// Individual data fields that can be plotted
enum PlotDataField {
    // Temperature & Density
    case Ti, Te, ne

    // Magnetic
    case q, magneticShear, psi

    // Transport coefficients
    case chiTotalIon, chiTotalElectron
    case chiTurbIon, chiTurbElectron
    case dFace

    // Current density
    case jTotal, jOhmic, jBootstrap, jECRH

    // Source terms
    case ohmicHeatSource, fusionHeatSource
    case pICRHIon, pICRHElectron, pECRHElectron

    var label: String {
        switch self {
        case .Ti: return "Ion Temperature (Ti)"
        case .Te: return "Electron Temperature (Te)"
        case .ne: return "Electron Density (ne)"
        case .q: return "Safety Factor (q)"
        case .magneticShear: return "Magnetic Shear"
        case .psi: return "Poloidal Flux (ψ)"
        case .chiTotalIon: return "χ_total (ion)"
        case .chiTotalElectron: return "χ_total (electron)"
        case .chiTurbIon: return "χ_turb (ion)"
        case .chiTurbElectron: return "χ_turb (electron)"
        case .dFace: return "D (particle)"
        case .jTotal: return "j_total"
        case .jOhmic: return "j_ohmic"
        case .jBootstrap: return "j_bootstrap"
        case .jECRH: return "j_ECRH"
        case .ohmicHeatSource: return "Ohmic Heating"
        case .fusionHeatSource: return "Fusion Heating"
        case .pICRHIon: return "ICRH (ion)"
        case .pICRHElectron: return "ICRH (electron)"
        case .pECRHElectron: return "ECRH (electron)"
        }
    }

    var color: Color {
        switch self {
        // Temperature - red/blue
        case .Ti:
            return Color(red: 1.0, green: 0.3, blue: 0.3)
        case .Te:
            return Color(red: 0.3, green: 0.6, blue: 1.0)

        // Density - green
        case .ne:
            return Color(red: 0.2, green: 0.8, blue: 0.4)

        // Magnetic - purple/magenta
        case .q:
            return Color(red: 0.7, green: 0.3, blue: 0.9)
        case .magneticShear:
            return Color(red: 0.9, green: 0.3, blue: 0.7)
        case .psi:
            return Color(red: 0.5, green: 0.3, blue: 0.8)

        // Transport - orange/yellow
        case .chiTotalIon:
            return Color(red: 1.0, green: 0.5, blue: 0.2)
        case .chiTotalElectron:
            return Color(red: 0.2, green: 0.7, blue: 1.0)
        case .chiTurbIon:
            return Color(red: 1.0, green: 0.7, blue: 0.3)
        case .chiTurbElectron:
            return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .dFace:
            return Color(red: 0.8, green: 0.6, blue: 0.2)

        // Current - cyan/blue variants
        case .jTotal:
            return Color(red: 0.2, green: 0.8, blue: 0.8)
        case .jOhmic:
            return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .jBootstrap:
            return Color(red: 0.5, green: 0.7, blue: 1.0)
        case .jECRH:
            return Color(red: 0.4, green: 0.9, blue: 0.9)

        // Heating sources - warm colors
        case .ohmicHeatSource:
            return Color(red: 1.0, green: 0.4, blue: 0.2)
        case .fusionHeatSource:
            return Color(red: 1.0, green: 0.2, blue: 0.4)
        case .pICRHIon:
            return Color(red: 1.0, green: 0.6, blue: 0.3)
        case .pICRHElectron:
            return Color(red: 0.9, green: 0.5, blue: 0.5)
        case .pECRHElectron:
            return Color(red: 1.0, green: 0.7, blue: 0.4)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(0.3),
                color.opacity(0.1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Extract data for this field from PlotData at given time index
    func extractData(from plotData: PlotData, at timeIndex: Int) -> [Float] {
        guard timeIndex < plotData.nTime else {
            return Array(repeating: 0.0, count: plotData.nCells)
        }

        switch self {
        case .Ti: return plotData.Ti[timeIndex]
        case .Te: return plotData.Te[timeIndex]
        case .ne: return plotData.ne[timeIndex]
        case .q: return plotData.q[timeIndex]
        case .magneticShear: return plotData.magneticShear[timeIndex]
        case .psi: return plotData.psi[timeIndex]
        case .chiTotalIon: return plotData.chiTotalIon[timeIndex]
        case .chiTotalElectron: return plotData.chiTotalElectron[timeIndex]
        case .chiTurbIon: return plotData.chiTurbIon[timeIndex]
        case .chiTurbElectron: return plotData.chiTurbElectron[timeIndex]
        case .dFace: return plotData.dFace[timeIndex]
        case .jTotal: return plotData.jTotal[timeIndex]
        case .jOhmic: return plotData.jOhmic[timeIndex]
        case .jBootstrap: return plotData.jBootstrap[timeIndex]
        case .jECRH: return plotData.jECRH[timeIndex]
        case .ohmicHeatSource: return plotData.ohmicHeatSource[timeIndex]
        case .fusionHeatSource: return plotData.fusionHeatSource[timeIndex]
        case .pICRHIon: return plotData.pICRHIon[timeIndex]
        case .pICRHElectron: return plotData.pICRHElectron[timeIndex]
        case .pECRHElectron: return plotData.pECRHElectron[timeIndex]
        }
    }
}
