//
//  SimulationPresets.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/23.
//

import Foundation
import GotenxCore

/// Built-in configuration presets for common simulation scenarios
enum ConfigurationPreset: String, CaseIterable, Identifiable {
    case constant = "Constant Transport"
    case bohmGyroBohm = "Bohm-GyroBohm (Empirical)"
    case turbulenceTransition = "Turbulence Transition (Advanced)"
    case qlknn = "QLKNN (Neural Network)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .constant: return "equal.circle"
        case .bohmGyroBohm: return "waveform.path"
        case .turbulenceTransition: return "wind"
        case .qlknn: return "brain"
        }
    }

    var description: String {
        switch self {
        case .constant:
            return "Simple constant diffusivity model. Fast and stable for testing."
        case .bohmGyroBohm:
            return "Empirical transport model with Bohm and GyroBohm scaling. Good for general scenarios."
        case .turbulenceTransition:
            return "Advanced density-dependent ITG↔RI transition. Based on 2024 experimental discovery."
        case .qlknn:
            return "Neural network-based transport model. High accuracy, macOS only."
        }
    }

    var configuration: SimulationConfiguration {
        switch self {
        case .constant:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1e-3

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .constant,
                    parameters: [:]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 100.0,
                    electronTemperature: 100.0,
                    density: 2.0e19
                )

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }

        case .bohmGyroBohm:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1e-3

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .bohmGyrobohm,
                    parameters: [
                        "bohm_coeff": 1.0,
                        "gyrobohm_coeff": 1.0,
                        "ion_mass_number": 2.0
                    ]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 100.0,
                    electronTemperature: 100.0,
                    density: 2.0e19
                )

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }

        case .turbulenceTransition:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1e-3

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .densityTransition,
                    parameters: [
                        "transition_density": 2.5e19,
                        "transition_width": 0.5e19,
                        "ion_mass_number": 2.0,
                        "ri_coefficient": 0.5
                    ]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 100.0,
                    electronTemperature: 100.0,
                    density: 2.0e19
                )

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }

        case .qlknn:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1e-3

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .qlknn,
                    parameters: [:]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 100.0,
                    electronTemperature: 100.0,
                    density: 2.0e19
                )

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }
        }
    }
}
