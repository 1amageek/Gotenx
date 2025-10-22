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
            return
        }

        guard let configData = simulation.configurationData else {
            logger.error("No configuration data")
            errorMessage = "Simulation has no configuration"
            return
        }

        logger.info("Starting simulation: \(simulation.name)")

        simulationTask = Task {
            do {
                // Decode configuration
                let config = try JSONDecoder().decode(SimulationConfiguration.self, from: configData)

                isSimulationRunning = true
                isPaused = false
                simulationProgress = 0.0
                simulation.status = .running(progress: 0.0)
                totalSimulationTime = config.time.end
                lastUpdateTime = .distantPast

                // Get data store
                let store = try getDataStore()

                // Create default initial profiles
                // Note: This is a simplified version - in production, you would:
                // 1. Convert SimulationConfiguration to RuntimeParams (requires swift-gotenx updates)
                // 2. Get proper initial conditions
                let initialProfiles = createDefaultProfiles(nCells: 100)

                // For now, we'll create a minimal result since we can't actually run the orchestrator
                // without the proper RuntimeParams conversion
                logger.warning("Simulation execution not yet implemented - creating placeholder result")

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

                // Save results
                await MainActor.run {
                    saveResults(simulation: simulation, result: result, store: store)
                }

            } catch is CancellationError {
                await MainActor.run {
                    simulation.status = .cancelled
                    logger.info("Simulation cancelled: \(simulation.name)")
                }
            } catch {
                await MainActor.run {
                    simulation.status = .failed(error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    logger.error("Simulation failed: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isSimulationRunning = false
                simulationTask = nil
            }
        }
    }

    /// Pause simulation
    func pauseSimulation() {
        guard isSimulationRunning, !isPaused else { return }

        isPaused = true
        isSimulationRunning = false

        if let simulation = selectedSimulation {
            simulation.status = .paused(at: simulationProgress)
        }

        logger.info("Simulation paused")
    }

    /// Resume simulation
    func resumeSimulation() {
        guard isPaused, let simulation = selectedSimulation else { return }

        isPaused = false
        isSimulationRunning = true
        simulation.status = .running(progress: simulationProgress)

        logger.info("Simulation resumed")
    }

    /// Stop simulation
    func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        isPaused = false
        isSimulationRunning = false

        if let simulation = selectedSimulation {
            simulation.status = .cancelled
        }

        logger.info("Simulation stopped")
    }

    /// Delete simulation and associated data
    func deleteSimulation(_ simulation: Simulation) async {
        do {
            // Delete file data
            let store = try getDataStore()
            try store.deleteSimulation(simulation.id)

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

    @MainActor
    private func saveResults(simulation: Simulation, result: SimulationResult, store: SimulationDataStore) {
        do {
            // Save complete result to file
            try store.saveSimulationResult(result, simulationID: simulation.id)

            // Update simulation metadata
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

            // Save to SwiftData
            if let context = modelContext {
                try context.save()
            }

            logger.notice("Saved simulation result: \(simulation.name)")

        } catch {
            logger.error("Failed to save results: \(error)")
            errorMessage = "Failed to save results: \(error.localizedDescription)"
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
