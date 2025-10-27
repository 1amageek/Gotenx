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
import GotenxPhysics  // ✅ FIXED: For SourceModelFactory, MHDModelFactory
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
    private var currentRunner: SimulationRunner?  // ✅ NEW: For pause/resume support
    private var pauseResumeTask: Task<Void, Never>?  // ✅ NEW: Track pause/resume operations
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
                    currentRunner = nil
                    simulationTask = nil
                    pauseResumeTask?.cancel()  // ✅ FIXED: Cancel any pending pause/resume
                    pauseResumeTask = nil
                    liveProfiles = nil  // ✅ FIXED: Clear live data
                    liveDerived = nil   // ✅ FIXED: Clear derived quantities
                    logViewModel.log("Simulation task cleanup completed", level: .debug, category: "Simulation")
                }
            }

            do {
                // Decode configuration
                logViewModel.log("Decoding configuration...", level: .debug, category: "Config")
                let config = try JSONDecoder().decode(SimulationConfiguration.self, from: configData)

                // ✅ NEW: Validate configuration before running simulation
                logViewModel.log("Validating configuration...", level: .debug, category: "Config")
                do {
                    try ConfigurationValidator.validate(config)
                    logViewModel.log("✓ Configuration validation passed", level: .info, category: "Config")
                } catch let error as ConfigurationValidationError {
                    // Critical error - abort simulation
                    logViewModel.log("✗ Configuration validation failed: \(error.localizedDescription)", level: .error, category: "Config")
                    throw error
                } catch {
                    // Unexpected error during validation
                    logViewModel.log("✗ Unexpected validation error: \(error.localizedDescription)", level: .error, category: "Config")
                    throw error
                }

                // Collect and display warnings
                let warnings = ConfigurationValidator.collectWarnings(config)
                if !warnings.isEmpty {
                    logViewModel.log("⚠️  Configuration has \(warnings.count) warning(s):", level: .warning, category: "Config")
                    for warning in warnings {
                        logViewModel.log("  • \(warning.localizedDescription)", level: .warning, category: "Config")
                    }
                }

                await MainActor.run {
                    isSimulationRunning = true
                    isPaused = false
                    simulationProgress = 0.0
                    simulation.status = .running(progress: 0.0)
                    totalSimulationTime = config.time.end
                    lastUpdateTime = .distantPast
                }

                logViewModel.log("Simulation initialized (duration: \(config.time.end)s)", level: .info, category: "Simulation")

                // ✅ NEW: Create SimulationRunner directly
                let runner = SimulationRunner(config: config)
                await MainActor.run {
                    self.currentRunner = runner  // Store for pause/resume
                }

                // ✅ NEW: Initialize models (with all required parameters)
                logViewModel.log("Initializing physics models...", level: .debug, category: "Simulation")

                let transportModel = try TransportModelFactory.create(
                    config: config.runtime.dynamic.transport
                )

                // ⚠️ Breaking Change: Now throws
                // Note: SourceModelFactory.create() returns a single composite model

                // 🐛 DEBUG: Check sources configuration
                let sourcesConfig = config.runtime.dynamic.sources
                print("[DEBUG-SOURCES] ohmicHeating: \(sourcesConfig.ohmicHeating)")
                print("[DEBUG-SOURCES] fusionPower: \(sourcesConfig.fusionPower)")
                print("[DEBUG-SOURCES] ionElectronExchange: \(sourcesConfig.ionElectronExchange)")
                print("[DEBUG-SOURCES] bremsstrahlung: \(sourcesConfig.bremsstrahlung)")
                print("[DEBUG-SOURCES] ecrh: \(sourcesConfig.ecrh != nil ? "YES (power=\(sourcesConfig.ecrh!.totalPower)W)" : "NO")")
                print("[DEBUG-SOURCES] gasPuff: \(sourcesConfig.gasPuff != nil ? "YES" : "NO")")

                let sourceModel = try SourceModelFactory.create(
                    config: config.runtime.dynamic.sources
                )

                let mhdModels = MHDModelFactory.createAllModels(
                    config: config.runtime.dynamic.mhd
                )

                // ✅ FIXED: Wrap sourceModel in array (initialize expects [any SourceModel])
                try await runner.initialize(
                    transportModel: transportModel,
                    sourceModels: [sourceModel],
                    mhdModels: mhdModels
                )

                logViewModel.log("Models initialized", level: .debug, category: "Simulation")

                // Get data store
                logViewModel.log("Initializing data store...", level: .debug, category: "Storage")
                let store = try getDataStore()

                // ✅ NEW: Run actual simulation with progress callback
                logViewModel.log("Starting physics calculation...", level: .info, category: "Simulation")

                let result = try await runner.run { [weak self] fraction, progressInfo in
                    guard let self = self else {
                        print("[DEBUG] progressCallback: self is nil")
                        return
                    }

                    // 🐛 DEBUG: Callback called
                    print("[DEBUG] progressCallback called: fraction=\(fraction), time=\(progressInfo.currentTime)s")

                    // Progress callback (already runs on background, hop to MainActor for UI)
                    // ✅ FIXED: Use Task with guard to prevent updates after simulation stops
                    Task { @MainActor in
                        // Guard against updates after simulation has stopped (prevents duplication after errors)
                        guard self.isSimulationRunning else {
                            print("[DEBUG] progressCallback: isSimulationRunning=false, skipping update")
                            return
                        }

                        print("[DEBUG] progressCallback: updating UI, fraction=\(fraction)")

                        self.simulationProgress = Double(fraction)
                        self.currentSimulationTime = progressInfo.currentTime

                        // ✅ NEW: Update live data (throttled)
                        let now = Date()
                        if now.timeIntervalSince(self.lastUpdateTime) >= self.minUpdateInterval {
                            if let profiles = progressInfo.profiles {
                                self.liveProfiles = profiles
                                print("[DEBUG-AppViewModel] liveProfiles updated: Ti=\(profiles.ionTemperature.first ?? -1)...\(profiles.ionTemperature.last ?? -1) eV, count=\(profiles.ionTemperature.count)")
                            }
                            if let derived = progressInfo.derived {
                                self.liveDerived = derived
                            }
                            self.lastUpdateTime = now
                        }

                        // Log every 10%
                        if fraction.truncatingRemainder(dividingBy: 0.1) < 0.01 {
                            self.logViewModel.log(
                                "Progress: \(Int(fraction * 100))% | t = \(String(format: "%.3f", progressInfo.currentTime))s | dt = \(String(format: "%.4f", progressInfo.lastDt))s",
                                level: .debug,
                                category: "Simulation"
                            )
                        }
                    }
                }

                // Save results
                logViewModel.log("Saving simulation results...", level: .info, category: "Storage")

                // 🐛 DEBUG: Log simulation result
                print("[DEBUG-AppViewModel] SimulationResult: timeSeries=\(result.timeSeries?.count ?? 0) points")

                try await saveResults(simulation: simulation, result: result, store: store)

                await MainActor.run {
                    logViewModel.log("✓ Simulation completed successfully", level: .info, category: "Simulation")
                    logger.notice("Simulation completed: \(simulation.name)")
                }

            } catch is CancellationError {
                await MainActor.run {
                    simulation.status = .cancelled
                    logger.info("Simulation cancelled: \(simulation.name)")
                    logViewModel.log("⚠ Simulation cancelled by user", level: .warning, category: "Simulation")
                }
            } catch let error as SimulationError {
                await MainActor.run {
                    simulation.status = .failed(error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    logger.error("Simulation failed: \(error.localizedDescription)")

                    logViewModel.log("✗ Simulation failed: \(error.localizedDescription)", level: .error, category: "Simulation")

                    // Show recovery suggestion if available
                    if let recovery = error.recoverySuggestion {
                        logViewModel.log("💡 Suggestion: \(recovery)", level: .info, category: "Simulation")
                    }
                }
            } catch let error as SolverError {
                // ✅ NEW: Handle SolverError (convergence failures, etc.)
                await MainActor.run {
                    let errorDescription = "Solver error: \(error)"
                    simulation.status = .failed(error: errorDescription)
                    errorMessage = errorDescription
                    logger.error("Solver error: \(error)")

                    logViewModel.log("✗ Solver error: \(error)", level: .error, category: "Simulation")
                    logViewModel.log("💡 Suggestion: Try reducing time step, increasing mesh resolution, or using a different solver", level: .info, category: "Simulation")
                }
            } catch {
                await MainActor.run {
                    simulation.status = .failed(error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    logger.error("Unexpected error: \(error.localizedDescription)")
                    logViewModel.log("✗ Unexpected error: \(error.localizedDescription)", level: .error, category: "Simulation")
                }
            }
        }
    }

    /// Pause simulation
    /// ✅ NEW: Fully functional with swift-gotenx Phase 1
    /// ✅ FIXED: Properly track pause operation to avoid race conditions
    func pauseSimulation() {
        guard let runner = currentRunner, isSimulationRunning, !isPaused else { return }

        // Cancel any pending pause/resume operation
        pauseResumeTask?.cancel()

        // Create tracked task for pause operation
        pauseResumeTask = Task {
            await runner.pause()
            await MainActor.run {
                isPaused = true
                if let simulation = selectedSimulation {
                    simulation.status = .paused(at: simulationProgress)
                }
                logViewModel.log("⏸ Simulation paused", level: .info, category: "Simulation")
                logger.info("Simulation paused")
            }
        }
    }

    /// Resume simulation
    /// ✅ NEW: Fully functional with swift-gotenx Phase 1
    /// ✅ FIXED: Properly track resume operation to avoid race conditions
    func resumeSimulation() {
        guard let runner = currentRunner, isSimulationRunning, isPaused else { return }

        // Cancel any pending pause/resume operation
        pauseResumeTask?.cancel()

        // Create tracked task for resume operation
        pauseResumeTask = Task {
            await runner.resume()
            await MainActor.run {
                isPaused = false
                if let simulation = selectedSimulation {
                    simulation.status = .running(progress: simulationProgress)
                }
                logViewModel.log("▶ Simulation resumed", level: .info, category: "Simulation")
                logger.info("Simulation resumed")
            }
        }
    }

    /// Stop simulation
    /// ✅ NEW: Full cancellation support (orchestrator stops immediately)
    /// ✅ FIXED: Also cancel any pending pause/resume operations
    func stopSimulation() {
        guard let task = simulationTask else { return }

        logViewModel.log("⏹ Stopping simulation...", level: .warning, category: "Simulation")

        // Cancel any pending pause/resume operation
        pauseResumeTask?.cancel()
        pauseResumeTask = nil

        // Cancel the task (defer block will clean up isSimulationRunning)
        // ✅ NEW: Task.cancel() now stops orchestrator immediately (swift-gotenx Phase 1)
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

    // ✅ REMOVED: createDefaultProfiles() method
    // Initial profiles are now generated by SimulationRunner.initialize()
    // using physics-based calculations from swift-gotenx
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
