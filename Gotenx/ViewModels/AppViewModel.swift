//
//  AppViewModel.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import SwiftData
import Observation
import GotenxCore
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "simulation")

@MainActor
@Observable
final class AppViewModel {
    // MARK: - Properties

    // Workspace
    var workspace: Workspace
    var selectedSimulation: Simulation?

    // Simulation execution
    private var simulationTask: Task<Void, Error>?
    private var dataStore: SimulationDataStore?
    var isSimulationRunning: Bool = false
    var isPaused: Bool = false
    var simulationProgress: Double = 0.0
    var currentSimulationTime: Float = 0.0
    var totalSimulationTime: Float = 1.0

    // Real-time data (throttled)
    var liveProfiles: SerializableProfiles?
    var liveDerived: DerivedQuantities?
    private var lastUpdateTime: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 0.1  // 100ms

    // UI state
    var showInspector: Bool = true
    var showSidebar: Bool = true
    var errorMessage: String?

    // Logging
    var logViewModel: LogViewModel = LogViewModel()

    // Model context (injected from view)
    weak var modelContext: ModelContext?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    // MARK: - Simulation Operations

    /// Create a new simulation
    func createSimulation(name: String, configData: Data) {
        guard let context = modelContext else {
            logger.error("ModelContext not available")
            return
        }

        let simulation = Simulation(name: name, configurationData: configData)
        simulation.workspace = workspace
        workspace.simulations.append(simulation)
        context.insert(simulation)

        do {
            try context.save()
            selectedSimulation = simulation
            logger.info("Created simulation: \(name)")
        } catch {
            logger.error("Failed to save simulation: \(error)")
            errorMessage = "Failed to create simulation: \(error.localizedDescription)"
        }
    }

    /// Run simulation with proper actor isolation
    func runSimulation(_ simulation: Simulation) {
        guard simulationTask == nil else {
            logger.error("Simulation already running")
            errorMessage = "A simulation is already running"
            logViewModel.log("Cannot start: Another simulation is running", level: .warning, category: "Simulation")
            return
        }

        guard let configData = simulation.configurationData else {
            logger.error("No configuration data")
            errorMessage = "Simulation has no configuration"
            logViewModel.log("Cannot start: No configuration data", level: .error, category: "Simulation")
            return
        }

        logger.info("Starting simulation: \(simulation.name)")
        logViewModel.log("Starting simulation: \(simulation.name)", level: .info, category: "Simulation")

        simulationTask = Task {
            defer {
                // Always clean up task state (runs even if Task is cancelled)
                Task { @MainActor in
                    isSimulationRunning = false
                    simulationTask = nil
                    logViewModel.log("Simulation task cleanup completed", level: .debug, category: "Simulation")
                }
            }

            do {
                // Decode configuration
                logViewModel.log("Decoding configuration...", level: .debug, category: "Config")
                let config = try JSONDecoder().decode(SimulationConfiguration.self, from: configData)

                await MainActor.run {
                    isSimulationRunning = true
                    isPaused = false
                    simulationProgress = 0.0
                    simulation.status = .running(progress: 0.0)
                    totalSimulationTime = config.time.end
                    lastUpdateTime = .distantPast
                }

                logViewModel.log("Simulation initialized (duration: \(config.time.end)s, cells: 100)", level: .info, category: "Simulation")

                // Get data store
                logViewModel.log("Initializing data store...", level: .debug, category: "Storage")
                let store = try getDataStore()

                // Create default initial profiles
                // Note: This is a simplified version - in production, you would:
                // 1. Convert SimulationConfiguration to RuntimeParams (requires swift-gotenx updates)
                // 2. Get proper initial conditions
                logViewModel.log("Creating initial profiles...", level: .debug, category: "Simulation")
                let initialProfiles = createDefaultProfiles(nCells: 100)

                // For now, we'll create a minimal result since we can't actually run the orchestrator
                // without the proper RuntimeParams conversion
                logger.warning("Simulation execution not yet implemented - creating placeholder result")
                logViewModel.log("⚠ Using placeholder execution (orchestrator not yet integrated)", level: .warning, category: "Simulation")

                // Create placeholder result
                let result = SimulationResult(
                    finalProfiles: initialProfiles,
                    statistics: SimulationStatistics(
                        totalIterations: 0,
                        totalSteps: 0,
                        converged: true,
                        maxResidualNorm: 0.0,
                        wallTime: 0.0
                    ),
                    timeSeries: [
                        TimePoint(
                            time: 0.0,
                            profiles: initialProfiles,
                            derived: nil,
                            diagnostics: nil
                        )
                    ]
                )

                // Save results (now throws on error instead of catching)
                logViewModel.log("Saving simulation results...", level: .info, category: "Storage")
                try await saveResults(simulation: simulation, result: result, store: store)

                logViewModel.log("✓ Simulation completed successfully", level: .info, category: "Simulation")

            } catch is CancellationError {
                await MainActor.run {
                    simulation.status = .cancelled
                    logger.info("Simulation cancelled: \(simulation.name)")
                    logViewModel.log("⚠ Simulation cancelled by user", level: .warning, category: "Simulation")
                }
            } catch {
                await MainActor.run {
                    simulation.status = .failed(error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    logger.error("Simulation failed: \(error.localizedDescription)")
                    logViewModel.log("✗ Simulation failed: \(error.localizedDescription)", level: .error, category: "Simulation")
                }
            }
        }
    }

    /// Pause simulation
    /// Note: Currently not fully implemented - placeholder implementation only updates status
    /// TODO: Implement actual simulation pause when orchestrator integration is complete
    func pauseSimulation() {
        guard isSimulationRunning, !isPaused, simulationTask != nil else { return }

        isPaused = true

        if let simulation = selectedSimulation {
            simulation.status = .paused(at: simulationProgress)
        }

        logger.info("Simulation paused (status only - execution continues)")
    }

    /// Resume simulation
    /// Note: Currently not fully implemented - placeholder implementation only updates status
    /// TODO: Implement actual simulation resume when orchestrator integration is complete
    func resumeSimulation() {
        guard isPaused, let simulation = selectedSimulation, simulationTask != nil else { return }

        isPaused = false
        simulation.status = .running(progress: simulationProgress)

        logger.info("Simulation resumed (status only)")
    }

    /// Stop simulation
    func stopSimulation() {
        guard let task = simulationTask else { return }

        logViewModel.log("Stopping simulation...", level: .warning, category: "Simulation")

        // Cancel the task (defer block will clean up isSimulationRunning)
        task.cancel()

        // Immediately update UI state
        isPaused = false

        if let simulation = selectedSimulation {
            simulation.status = .cancelled
        }

        logger.info("Simulation stopped")
    }

    /// Delete simulation and associated data
    func deleteSimulation(_ simulation: Simulation) async {
        do {
            // Delete file data (actor boundary crossing)
            let store = try getDataStore()
            try await store.deleteSimulation(simulation.id)

            // Remove from workspace
            workspace.simulations.removeAll { $0.id == simulation.id }

            // Delete from SwiftData
            if let context = modelContext {
                context.delete(simulation)
                try context.save()
            }

            if selectedSimulation?.id == simulation.id {
                selectedSimulation = nil
            }

            logger.info("Deleted simulation: \(simulation.name)")

        } catch {
            logger.error("Failed to delete simulation: \(error)")
            errorMessage = "Failed to delete simulation: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func saveResults(simulation: Simulation, result: SimulationResult, store: SimulationDataStore) async throws {
        // Save complete result to file (actor boundary crossing)
        try await store.saveSimulationResult(result, simulationID: simulation.id)

        // Update simulation metadata (MainActor required for SwiftData)
        try await MainActor.run {
            simulation.finalProfiles = try? JSONEncoder().encode(result.finalProfiles)
            simulation.statistics = try? JSONEncoder().encode(result.statistics)
            simulation.status = .completed
            simulation.modifiedAt = Date()

            // Create lightweight metadata from timeSeries
            if let timeSeries = result.timeSeries {
                simulation.snapshotMetadata = timeSeries.enumerated().map { index, timePoint in
                    SnapshotMetadata(
                        time: timePoint.time,
                        index: index,
                        coreTi: (timePoint.profiles.ionTemperature.first ?? 0) / 1000.0,
                        edgeTi: (timePoint.profiles.ionTemperature.last ?? 0) / 1000.0,
                        avgNe: timePoint.profiles.electronDensity.reduce(0, +) / Float(timePoint.profiles.electronDensity.count) / 1e20,
                        peakNe: (timePoint.profiles.electronDensity.max() ?? 0) / 1e20,
                        plasmaCurrentMA: timePoint.derived?.I_plasma,
                        fusionGainQ: timePoint.derived.map { derived in
                            let P_input = derived.P_auxiliary + derived.P_ohmic + 1e-10
                            return derived.P_fusion / P_input
                        }
                    )
                }
            }

            // Save to SwiftData (throw error if fails)
            if let context = modelContext {
                try context.save()
            }

            logger.notice("Saved simulation result: \(simulation.name)")
        }
    }

    private func getDataStore() throws -> SimulationDataStore {
        if let existing = dataStore {
            return existing
        }

        let store = try SimulationDataStore()
        dataStore = store
        return store
    }

    private func createDefaultProfiles(nCells: Int) -> SerializableProfiles {
        let rho = (0..<nCells).map { Float($0) / Float(max(nCells - 1, 1)) }

        // Parabolic temperature profile: T = T0 * (1 - rho^2)
        let Ti = rho.map { 10000.0 * (1.0 - $0 * $0) }  // 10 keV peak
        let Te = rho.map { 10000.0 * (1.0 - $0 * $0) }

        // Parabolic density profile: n = n0 * (1 - rho^2)^0.5
        let ne = rho.map { 1e20 * pow(1.0 - $0 * $0, 0.5) }

        // Initial poloidal flux (placeholder)
        let psi = Array(repeating: Float(0.0), count: nCells)

        return SerializableProfiles(
            ionTemperature: Ti,
            electronTemperature: Te,
            electronDensity: ne,
            poloidalFlux: psi
        )
    }
}

// MARK: - Errors

enum AppError: LocalizedError {
    case invalidConfiguration
    case simulationAlreadyRunning
    case simulationFailed(String)
    case dataStoreError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid simulation configuration"
        case .simulationAlreadyRunning:
            return "A simulation is already running. Stop it before starting a new one."
        case .simulationFailed(let message):
            return "Simulation failed: \(message)"
        case .dataStoreError(let error):
            return "Data storage error: \(error.localizedDescription)"
        }
    }
}
