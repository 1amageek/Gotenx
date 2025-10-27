//
//  ConfigViewModel.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import Observation
import GotenxCore
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "config")

@MainActor
@Observable
final class ConfigViewModel {
    var selectedSavedPreset: SavedPreset?
    var isEditingConfiguration: Bool = false

    // MARK: - Editable Mesh Parameters

    /// Number of radial cells (resolution)
    /// Default: 50 cells (Jacobian: 200×200)
    /// Recommended range: 25-100 for interactive use, 100-200 for production
    var nCells: Int = 50 {
        didSet {
            validateMeshParameters()
        }
    }

    /// Major radius [m]
    var majorRadius: Double = 6.2

    /// Minor radius [m]
    var minorRadius: Double = 2.0

    /// Toroidal field [T]
    var toroidalField: Double = 5.3

    // MARK: - Solver Parameters

    /// Newton-Raphson maximum iterations
    /// Default: 100 (sufficient for most cases)
    /// Recommended range: 50-200
    var maxIterations: Int = 100 {
        didSet {
            validateSolverParameters()
        }
    }

    // Note: Solver tolerance is not user-configurable.
    // The system uses NumericalTolerances.iterScale (physically optimized values):
    // - Ion/Electron Temperature: 10 eV absolute, 0.01% relative
    // - Electron Density: 1e17 m⁻³ absolute, 0.01% relative
    // - Poloidal Flux: 1 mWb absolute, 0.001% relative

    // MARK: - Validation

    var meshValidationError: String?
    var solverValidationError: String?

    private func validateMeshParameters() {
        // nCells validation
        if nCells < 10 {
            meshValidationError = "nCells must be at least 10 (current: \(nCells))"
        } else if nCells > 500 {
            meshValidationError = "nCells too large (max 500, current: \(nCells)). High resolution increases computation time significantly."
        } else if nCells > 200 {
            meshValidationError = "Warning: nCells > 200 may be slow. Jacobian size: \(nCells*4)×\(nCells*4)"
        } else {
            meshValidationError = nil
        }
    }

    private func validateSolverParameters() {
        // maxIterations validation
        if maxIterations < 10 {
            solverValidationError = "maxIterations must be at least 10 (current: \(maxIterations))"
        } else if maxIterations > 500 {
            solverValidationError = "maxIterations too large (max 500, current: \(maxIterations)). May cause excessive computation time."
        } else if maxIterations > 200 {
            solverValidationError = "Warning: maxIterations > 200 may be slow. Each iteration computes Jacobian (vjp × \(nCells*4))"
        } else {
            solverValidationError = nil
        }
    }

    /// Estimated Jacobian computation time
    var estimatedJacobianTime: String {
        let baseTime: Double = 0.06  // seconds per vjp at nCells=100
        let n = nCells * 4  // Total variables
        let scalingFactor = Double(n) / 400.0  // Relative to 100 cells
        let estimatedTime = baseTime * scalingFactor * Double(n)

        if estimatedTime < 60 {
            return String(format: "~%.0f sec", estimatedTime)
        } else {
            return String(format: "~%.1f min", estimatedTime / 60.0)
        }
    }

    /// Create configuration from current settings
    func createConfiguration() -> Data? {
        // Calculate CFL-safe timestep for current mesh
        // CFL = chi * dt / (cellSpacing^2) < 0.5
        // cellSpacing = minorRadius / nCells
        // dt_safe = 0.45 * (minorRadius / nCells)^2 / chi_max
        let cellSpacing = Float(self.minorRadius) / Float(self.nCells)
        let chi_max: Float = 1.0  // Assume maximum chi for safety
        let dt_safe = 0.45 * (cellSpacing * cellSpacing) / chi_max

        let config = SimulationConfiguration.build { builder in
            builder.time.start = 0.0
            builder.time.end = 2.0
            builder.time.initialDt = dt_safe  // ✅ CFL-SAFE: Auto-calculated based on mesh

            // Use user-configurable mesh parameters
            builder.runtime.static.mesh.nCells = self.nCells
            builder.runtime.static.mesh.majorRadius = Float(self.majorRadius)
            builder.runtime.static.mesh.minorRadius = Float(self.minorRadius)
            builder.runtime.static.mesh.toroidalField = Float(self.toroidalField)

            // Use user-configurable solver parameters (static config)
            // Tolerance uses system default (NumericalTolerances.iterScale)
            builder.runtime.static.solver = SolverConfig(
                type: "newtonRaphson",
                tolerance: nil,  // Use tolerances instead
                tolerances: .iterScale,  // Physically optimized per-equation tolerances
                physicalThresholds: .default,
                maxIterations: self.maxIterations,
                lineSearchEnabled: true,
                lineSearchMaxAlpha: 1.0
            )

            builder.output.saveInterval = 0.1
            builder.output.directory = "/tmp/gotenx_results"
        }

        return try? JSONEncoder().encode(config)
    }

    /// Create default ITER-like configuration (deprecated - use createConfiguration)
    func createDefaultConfiguration() -> Data? {
        return createConfiguration()
    }

    /// Validate configuration
    func validateConfiguration(_ data: Data) -> Bool {
        do {
            _ = try JSONDecoder().decode(SimulationConfiguration.self, from: data)
            return true
        } catch {
            logger.error("Configuration validation failed: \(error)")
            return false
        }
    }
}
