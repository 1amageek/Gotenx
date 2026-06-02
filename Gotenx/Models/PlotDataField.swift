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
    case ionTemperature, electronTemperature, electronDensity

    // Magnetic
    case safetyFactor, magneticShear, poloidalFlux

    // Transport coefficients
    case totalIonHeatConductivity, totalElectronHeatConductivity
    case turbulentIonHeatConductivity, turbulentElectronHeatConductivity
    case particleDiffusivity

    // Current density
    case totalCurrentDensity, ohmicCurrentDensity, bootstrapCurrentDensity, ecrhCurrentDensity

    // Source terms
    case ohmicHeatSource, fusionHeatSource
    case icrhIonHeatingPowerDensity, icrhElectronHeatingPowerDensity, ecrhElectronHeatingPowerDensity

    var label: String {
        switch self {
        case .ionTemperature: return "Ion Temperature (Ti)"
        case .electronTemperature: return "Electron Temperature (Te)"
        case .electronDensity: return "Electron Density (ne)"
        case .safetyFactor: return "Safety Factor (q)"
        case .magneticShear: return "Magnetic Shear"
        case .poloidalFlux: return "Poloidal Flux (ψ)"
        case .totalIonHeatConductivity: return "χ_total (ion)"
        case .totalElectronHeatConductivity: return "χ_total (electron)"
        case .turbulentIonHeatConductivity: return "χ_turb (ion)"
        case .turbulentElectronHeatConductivity: return "χ_turb (electron)"
        case .particleDiffusivity: return "D (particle)"
        case .totalCurrentDensity: return "j_total"
        case .ohmicCurrentDensity: return "j_ohmic"
        case .bootstrapCurrentDensity: return "j_bootstrap"
        case .ecrhCurrentDensity: return "j_ECRH"
        case .ohmicHeatSource: return "Ohmic Heating"
        case .fusionHeatSource: return "Fusion Heating"
        case .icrhIonHeatingPowerDensity: return "ICRH (ion)"
        case .icrhElectronHeatingPowerDensity: return "ICRH (electron)"
        case .ecrhElectronHeatingPowerDensity: return "ECRH (electron)"
        }
    }

    var color: Color {
        switch self {
        // Temperature - red/blue
        case .ionTemperature:
            return Color(red: 1.0, green: 0.3, blue: 0.3)
        case .electronTemperature:
            return Color(red: 0.3, green: 0.6, blue: 1.0)

        // Density - green
        case .electronDensity:
            return Color(red: 0.2, green: 0.8, blue: 0.4)

        // Magnetic - purple/magenta
        case .safetyFactor:
            return Color(red: 0.7, green: 0.3, blue: 0.9)
        case .magneticShear:
            return Color(red: 0.9, green: 0.3, blue: 0.7)
        case .poloidalFlux:
            return Color(red: 0.5, green: 0.3, blue: 0.8)

        // Transport - orange/yellow
        case .totalIonHeatConductivity:
            return Color(red: 1.0, green: 0.5, blue: 0.2)
        case .totalElectronHeatConductivity:
            return Color(red: 0.2, green: 0.7, blue: 1.0)
        case .turbulentIonHeatConductivity:
            return Color(red: 1.0, green: 0.7, blue: 0.3)
        case .turbulentElectronHeatConductivity:
            return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .particleDiffusivity:
            return Color(red: 0.8, green: 0.6, blue: 0.2)

        // Current - cyan/blue variants
        case .totalCurrentDensity:
            return Color(red: 0.2, green: 0.8, blue: 0.8)
        case .ohmicCurrentDensity:
            return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .bootstrapCurrentDensity:
            return Color(red: 0.5, green: 0.7, blue: 1.0)
        case .ecrhCurrentDensity:
            return Color(red: 0.4, green: 0.9, blue: 0.9)

        // Heating sources - warm colors
        case .ohmicHeatSource:
            return Color(red: 1.0, green: 0.4, blue: 0.2)
        case .fusionHeatSource:
            return Color(red: 1.0, green: 0.2, blue: 0.4)
        case .icrhIonHeatingPowerDensity:
            return Color(red: 1.0, green: 0.6, blue: 0.3)
        case .icrhElectronHeatingPowerDensity:
            return Color(red: 0.9, green: 0.5, blue: 0.5)
        case .ecrhElectronHeatingPowerDensity:
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
        guard timeIndex < plotData.timeCount else {
            return Array(repeating: 0.0, count: plotData.cellCount)
        }

        switch self {
        case .ionTemperature: return plotData.ionTemperature[timeIndex]
        case .electronTemperature: return plotData.electronTemperature[timeIndex]
        case .electronDensity: return plotData.electronDensity[timeIndex]
        case .safetyFactor: return plotData.safetyFactor[timeIndex]
        case .magneticShear: return plotData.magneticShear[timeIndex]
        case .poloidalFlux: return plotData.poloidalFlux[timeIndex]
        case .totalIonHeatConductivity: return plotData.totalIonHeatConductivity[timeIndex]
        case .totalElectronHeatConductivity: return plotData.totalElectronHeatConductivity[timeIndex]
        case .turbulentIonHeatConductivity: return plotData.turbulentIonHeatConductivity[timeIndex]
        case .turbulentElectronHeatConductivity: return plotData.turbulentElectronHeatConductivity[timeIndex]
        case .particleDiffusivity: return plotData.particleDiffusivity[timeIndex]
        case .totalCurrentDensity: return plotData.totalCurrentDensity[timeIndex]
        case .ohmicCurrentDensity: return plotData.ohmicCurrentDensity[timeIndex]
        case .bootstrapCurrentDensity: return plotData.bootstrapCurrentDensity[timeIndex]
        case .ecrhCurrentDensity: return plotData.ecrhCurrentDensity[timeIndex]
        case .ohmicHeatSource: return plotData.ohmicHeatSource[timeIndex]
        case .fusionHeatSource: return plotData.fusionHeatSource[timeIndex]
        case .icrhIonHeatingPowerDensity: return plotData.icrhIonHeatingPowerDensity[timeIndex]
        case .icrhElectronHeatingPowerDensity: return plotData.icrhElectronHeatingPowerDensity[timeIndex]
        case .ecrhElectronHeatingPowerDensity: return plotData.ecrhElectronHeatingPowerDensity[timeIndex]
        }
    }
}
