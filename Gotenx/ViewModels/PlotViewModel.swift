//
//  PlotViewModel.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import Observation
import GotenxUI
import GotenxCore
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "plotting")

@MainActor
@Observable
final class PlotViewModel {
    var plotData: PlotData?
    var currentTimeIndex: Int = 0

    // Animation
    var isAnimating: Bool = false
    var animationSpeed: Double = 1.0
    private var animationTask: Task<Void, Never>?

    // Plot settings
    var showLegend: Bool = true
    var showGrid: Bool = true
    var lineWidth: Double = 2.0

    // Cache
    private var cachedPlotData: [UUID: PlotData] = [:]
    private let cacheLimit = 3

    /// Load plot data for a simulation
    func loadPlotData(for simulation: Simulation) async {
        logger.info("Loading plot data for simulation: \(simulation.name)")

        // Check cache
        if let cached = cachedPlotData[simulation.id] {
            self.plotData = cached
            logger.debug("Using cached plot data")
            return
        }

        do {
            // Load SimulationResult from storage
            let dataStore = try SimulationDataStore()
            let result = try dataStore.loadSimulationResult(simulationID: simulation.id)

            // Use GotenxUI's built-in conversion
            let plotData = try PlotData(from: result)

            // Update cache
            if cachedPlotData.count >= cacheLimit {
                // Remove oldest entry (simple: remove first)
                if let oldestKey = cachedPlotData.keys.first {
                    cachedPlotData.removeValue(forKey: oldestKey)
                }
            }

            cachedPlotData[simulation.id] = plotData
            self.plotData = plotData

            logger.info("Loaded plot data with \(plotData.nTime) time points")

        } catch {
            logger.error("Failed to load plot data: \(error)")
        }
    }

    /// Start animation
    func startAnimation() {
        guard let plotData = plotData, !isAnimating else { return }

        logger.debug("Starting animation")
        isAnimating = true

        animationTask = Task {
            while isAnimating && !Task.isCancelled {
                let frameDelay = Int(100 / animationSpeed)  // Base: 100ms
                try? await Task.sleep(for: .milliseconds(frameDelay))

                await MainActor.run {
                    currentTimeIndex += 1
                    if currentTimeIndex >= plotData.nTime {
                        currentTimeIndex = 0
                    }
                }
            }
        }
    }

    /// Stop animation
    func stopAnimation() {
        isAnimating = false
        animationTask?.cancel()
        animationTask = nil
        logger.debug("Stopped animation")
    }

    /// Clear cache
    func clearCache() {
        cachedPlotData.removeAll()
        logger.debug("Cleared plot data cache")
    }
}

enum PlotError: LocalizedError {
    case noData
    case exportFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noData:
            return "No plot data available"
        case .exportFailed(let error):
            return "Failed to export plot: \(error.localizedDescription)"
        }
    }
}
