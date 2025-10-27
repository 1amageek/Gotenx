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
    var yAxisScale: AxisScale = .linear

    // Plot selection
    var selectedPlotTypes: Set<PlotType> = [.temperature, .density]
    var selectedScalarPlots: Set<ScalarPlotType> = []
    var showTimeSeriesPlots: Bool = false

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
            let result = try await dataStore.loadSimulationResult(simulationID: simulation.id)

            // 🐛 DEBUG: Log loaded result
            print("[DEBUG-PlotViewModel] Loaded result: timeSeries=\(result.timeSeries?.count ?? 0) points")

            // Use GotenxUI's built-in conversion
            let plotData = try PlotData(from: result)

            // 🐛 DEBUG: Log plotData
            print("[DEBUG-PlotViewModel] PlotData created: nTime=\(plotData.nTime), nCells=\(plotData.nCells)")

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

    // MARK: - Live Plotting (Phase 1b)

    /// Update plots with live profiles during simulation
    /// Note: This is a placeholder for future implementation
    /// Currently, live profiles are stored in AppViewModel.liveProfiles
    /// and can be accessed directly from views
    func updateLiveProfiles(_ profiles: SerializableProfiles) {
        // TODO: Implement live plot updates
        // This would require extending PlotData to support incremental updates
        // or creating a separate LivePlotData structure

        // For now, live profiles are accessible via AppViewModel.liveProfiles
        logger.debug("Live profiles update received (placeholder)")
    }

    /// Update derived quantities during simulation
    /// Note: This is a placeholder for future implementation
    /// Currently, derived quantities are stored in AppViewModel.liveDerived
    /// and can be accessed directly from views
    func updateDerivedQuantities(_ derived: DerivedQuantities) {
        // TODO: Implement live metrics updates
        // This could update a separate metrics panel or overlay

        // For now, derived quantities are accessible via AppViewModel.liveDerived
        logger.debug("Derived quantities update received (placeholder)")
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
