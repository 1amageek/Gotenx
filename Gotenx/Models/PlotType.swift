//
//  PlotType.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import SwiftUI

/// Available plot types for profile visualization
enum PlotType: String, CaseIterable, Identifiable {
    // Phase 1a: Core profiles (already implemented)
    case temperature = "Temperature"
    case density = "Density"

    // Phase 1b: Magnetic field profiles
    case safetyFactor = "Safety Factor (q)"
    case magneticShear = "Magnetic Shear"
    case poloidalFlux = "Poloidal Flux"

    // Phase 1c: Transport coefficients
    case heatConductivityIon = "Ion Heat Conductivity"
    case heatConductivityElectron = "Electron Heat Conductivity"
    case particleDiffusivity = "Particle Diffusivity"

    // Phase 1d: Current density
    case currentDensity = "Current Density"

    // Phase 1e: Source terms
    case heatingSources = "Heating Sources"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .temperature:
            return "thermometer"
        case .density:
            return "circle.grid.cross"
        case .safetyFactor:
            return "waveform.path.ecg"
        case .magneticShear:
            return "arrow.triangle.swap"
        case .poloidalFlux:
            return "arrow.clockwise.circle"
        case .heatConductivityIon, .heatConductivityElectron:
            return "flame"
        case .particleDiffusivity:
            return "drop.triangle"
        case .currentDensity:
            return "bolt"
        case .heatingSources:
            return "sun.max"
        }
    }

    var yAxisLabel: String {
        switch self {
        case .temperature:
            return "Temperature [keV]"
        case .density:
            return "Density [10²⁰ m⁻³]"
        case .safetyFactor:
            return "Safety Factor q"
        case .magneticShear:
            return "Magnetic Shear"
        case .poloidalFlux:
            return "Poloidal Flux [Wb]"
        case .heatConductivityIon, .heatConductivityElectron:
            return "Heat Conductivity [m²/s]"
        case .particleDiffusivity:
            return "Diffusivity [m²/s]"
        case .currentDensity:
            return "Current Density [MA/m²]"
        case .heatingSources:
            return "Power Density [MW/m³]"
        }
    }

    var dataFields: [PlotDataField] {
        switch self {
        case .temperature:
            return [.Ti, .Te]
        case .density:
            return [.ne]
        case .safetyFactor:
            return [.q]
        case .magneticShear:
            return [.magneticShear]
        case .poloidalFlux:
            return [.psi]
        case .heatConductivityIon:
            return [.chiTotalIon, .chiTurbIon]
        case .heatConductivityElectron:
            return [.chiTotalElectron, .chiTurbElectron]
        case .particleDiffusivity:
            return [.dFace]
        case .currentDensity:
            return [.jTotal, .jOhmic, .jBootstrap, .jECRH]
        case .heatingSources:
            return [.ohmicHeatSource, .fusionHeatSource, .pICRHIon, .pECRHElectron]
        }
    }

    var legendItems: [(String, Color)] {
        dataFields.map { ($0.label, $0.color) }
    }
}
