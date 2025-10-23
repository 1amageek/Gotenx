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

    /// Create default ITER-like configuration
    func createDefaultConfiguration() -> Data? {
        let config = SimulationConfiguration.build { builder in
            builder.time.start = 0.0
            builder.time.end = 2.0
            builder.time.initialDt = 1e-3

            builder.runtime.static.mesh.nCells = 100
            builder.runtime.static.mesh.majorRadius = 3.0
            builder.runtime.static.mesh.minorRadius = 1.0
            builder.runtime.static.mesh.toroidalField = 2.5

            builder.output.saveInterval = 0.1
            builder.output.directory = "/tmp/gotenx_results"
        }

        return try? JSONEncoder().encode(config)
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
