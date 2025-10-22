# Gotenx App Specification v2.0 - Data Model Compatibility Updates

**Version**: 2.0
**Date**: 2025-10-22
**Status**: CRITICAL DATA MODEL FIXES

---

## Summary of Changes

This update fixes **critical data model incompatibilities** between the Gotenx App specification and swift-gotenx.

### Root Cause

The v1.1 specification incorrectly assumed `CoreProfiles` is `Codable`, but it contains GPU tensors (`MLXArray` wrapped in `EvaluatedArray`) which cannot be serialized.

### Solution

Use swift-gotenx's existing serializable types:
- ✅ `SerializableProfiles` (Codable) instead of `CoreProfiles` for storage
- ✅ `TimePoint` (Codable) for snapshots (already defined in swift-gotenx)
- ✅ `SimulationResult` (Codable) as the primary return type
- ✅ `PlotData.init(from: SimulationResult)` for visualization (already implemented in GotenxUI)

---

## Changes Required

### 1. Update Section 4: Data Models

#### 4.1 Replace Snapshot Storage Structure

**OLD (WRONG)**:
```swift
// This does NOT work - CoreProfiles is NOT Codable
private struct SnapshotData: Codable {
    let time: Float
    let profiles: CoreProfiles  // ❌ NOT Codable
    let derived: DerivedQuantities?
}
```

**NEW (CORRECT)**:
```swift
// Use swift-gotenx's existing TimePoint structure
// No custom SnapshotData needed - TimePoint is already perfect for this

// Or if you need custom metadata:
struct SnapshotMetadata: Codable {
    var time: Float
    var index: Int
    // Summary statistics only
    var coreTi: Float
    var edgeTi: Float
    var avgNe: Float
    var peakNe: Float
    var plasmaCurrentMA: Float?
    var fusionGainQ: Float?
    var isBookmarked: Bool = false
}
```

---

### 2. Update Section 5.2: SimulationDataStore

Replace the entire SimulationDataStore implementation:

```swift
import Foundation
import Gotenx
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "datastore")

/// File-based storage for simulation results
actor SimulationDataStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    enum StorageError: LocalizedError {
        case directoryCreationFailed(URL)
        case fileWriteFailed(URL, Error)
        case fileReadFailed(URL, Error)
        case simulationNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let url):
                return "Failed to create directory at \(url.path)"
            case .fileWriteFailed(let url, let error):
                return "Failed to write file at \(url.path): \(error.localizedDescription)"
            case .fileReadFailed(let url, let error):
                return "Failed to read file at \(url.path): \(error.localizedDescription)"
            case .simulationNotFound(let id):
                return "Simulation \(id.uuidString) not found"
            }
        }
    }

    init() throws {
        // Get Application Support directory
        baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Gotenx/simulations", isDirectory: true)

        // Create base directory
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Configure encoder/decoder
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        logger.info("SimulationDataStore initialized at \(self.baseURL.path)")
    }

    // MARK: - Write Operations

    /// Save complete simulation result
    func saveSimulationResult(_ result: SimulationResult, simulationID: UUID) throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        // Create simulation directory if needed
        if !fileManager.fileExists(atPath: simDir.path) {
            try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
            logger.debug("Created simulation directory: \(simDir.path)")
        }

        let resultFile = simDir.appendingPathComponent("result.json")

        do {
            let data = try encoder.encode(result)  // ✅ SimulationResult IS Codable
            try data.write(to: resultFile)
            logger.notice("Saved simulation result: \(simulationID.uuidString)")
        } catch {
            logger.error("Failed to save result: \(error.localizedDescription)")
            throw StorageError.fileWriteFailed(resultFile, error)
        }
    }

    /// Save configuration to human-readable JSON
    func saveConfiguration(_ config: SimulationConfiguration, for simulationID: UUID) throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        if !fileManager.fileExists(atPath: simDir.path) {
            try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
        }

        let configFile = simDir.appendingPathComponent("config.json")

        do {
            let data = try encoder.encode(config)  // ✅ SimulationConfiguration IS Codable
            try data.write(to: configFile)
            logger.debug("Saved configuration for simulation \(simulationID.uuidString)")
        } catch {
            throw StorageError.fileWriteFailed(configFile, error)
        }
    }

    // MARK: - Read Operations

    /// Load complete simulation result
    func loadSimulationResult(simulationID: UUID) throws -> SimulationResult {
        let resultFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("result.json")

        guard fileManager.fileExists(atPath: resultFile.path) else {
            logger.warning("Result file not found for simulation \(simulationID.uuidString)")
            throw StorageError.simulationNotFound(simulationID)
        }

        do {
            let data = try Data(contentsOf: resultFile)
            let result = try decoder.decode(SimulationResult.self, from: data)  // ✅ SimulationResult IS Codable
            logger.info("Loaded simulation result: \(simulationID.uuidString)")
            return result
        } catch {
            logger.error("Failed to load result: \(error.localizedDescription)")
            throw StorageError.fileReadFailed(resultFile, error)
        }
    }

    /// Load configuration
    func loadConfiguration(simulationID: UUID) throws -> SimulationConfiguration {
        let configFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configFile.path) else {
            throw StorageError.simulationNotFound(simulationID)
        }

        let data = try Data(contentsOf: configFile)
        return try decoder.decode(SimulationConfiguration.self, from: data)
    }

    // MARK: - Delete Operations

    /// Delete all data for a simulation
    func deleteSimulation(_ simulationID: UUID) throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)

        guard fileManager.fileExists(atPath: simDir.path) else {
            logger.warning("Simulation directory not found: \(simDir.path)")
            return
        }

        try fileManager.removeItem(at: simDir)
        logger.info("Deleted simulation data: \(simulationID.uuidString)")
    }

    // MARK: - Utility

    /// Get file size for a simulation
    func getStorageSize(for simulationID: UUID) throws -> Int64 {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)

        guard fileManager.fileExists(atPath: simDir.path) else {
            return 0
        }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: simDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }
}
```

---

### 3. Update Section 6.1: AppViewModel.runSimulation()

Replace the `runSimulation()` method:

```swift
/// Run simulation with proper actor isolation and error handling
func runSimulation(_ simulation: Simulation) async {
    guard simulationTask == nil else {
        logger.error("Simulation already running")
        errorMessage = "A simulation is already running"
        return
    }

    guard let config = simulation.configuration else {
        logger.error("Invalid configuration")
        errorMessage = "Invalid simulation configuration"
        return
    }

    logger.info("Starting simulation: \(simulation.name)")

    simulationTask = Task {
        do {
            isSimulationRunning = true
            isPaused = false
            simulationProgress = 0.0
            simulation.status = .running(progress: 0.0)
            totalSimulationTime = config.time.end
            lastUpdateTime = .distantPast

            // Get data store
            let store = try getDataStore()

            // Convert SimulationConfiguration to RuntimeParams
            let staticParams = try StaticRuntimeParams(from: config.runtime.static)
            let dynamicParams = try DynamicRuntimeParams(from: config.runtime.dynamic)

            // Create initial profiles (SerializableProfiles)
            let initialProfiles = SerializableProfiles.defaultITERLike(nCells: staticParams.mesh.nCells)

            // Create transport model
            let transport = createTransportModel(config.runtime.dynamic.transport)

            // Create source models
            let sources = createSourceModels(config.runtime.dynamic.sources)

            // Create orchestrator (actor isolated)
            let orchestrator = await SimulationOrchestrator(
                staticParams: staticParams,
                initialProfiles: initialProfiles,  // ✅ SerializableProfiles (Codable)
                transport: transport,
                sources: sources,
                samplingConfig: SamplingConfig(
                    profileSamplingInterval: config.output.saveInterval,
                    enableDerivedQuantities: true,
                    enableDiagnostics: true
                )
            )

            // Run simulation
            let result = try await orchestrator.run(
                until: config.time.end,
                dynamicParams: dynamicParams
            )

            // Save results on main actor
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

/// Save simulation results
@MainActor
private func saveResults(simulation: Simulation, result: SimulationResult, store: SimulationDataStore) {
    do {
        // Save complete result to file
        try store.saveSimulationResult(result, simulationID: simulation.id)  // ✅ SimulationResult IS Codable

        // Update simulation metadata
        simulation.finalProfiles = try? JSONEncoder().encode(result.finalProfiles)  // ✅ SerializableProfiles
        simulation.statistics = try? JSONEncoder().encode(result.statistics)
        simulation.status = .completed
        simulation.modifiedAt = Date()

        // Create lightweight metadata from timeSeries
        if let timeSeries = result.timeSeries {
            simulation.snapshotMetadata = timeSeries.enumerated().map { index, timePoint in
                SnapshotMetadata(
                    time: timePoint.time,
                    index: index,
                    coreTi: (timePoint.profiles.ionTemperature.first ?? 0) / 1000.0,  // eV → keV
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

        logger.notice("Saved simulation result: \(simulation.name)")

    } catch {
        logger.error("Failed to save results: \(error)")
        errorMessage = "Failed to save results: \(error.localizedDescription)"
    }
}

/// Create transport model from configuration
private func createTransportModel(_ config: TransportConfig) -> any TransportModel {
    switch config.modelType {
    case .constant:
        return ConstantTransportModel(chiTurb: config.chiConstant ?? 1.0)
    case .qlknn:
        return QLKNNModel()  // Will load pre-trained model
    case .criticalGradient:
        return CriticalGradientModel()
    case .bohm:
        return BohmTransportModel()
    }
}

/// Create source models from configuration
private func createSourceModels(_ config: SourcesConfig) -> [any SourceModel] {
    var sources: [any SourceModel] = []

    // Generic current source (if enabled)
    if let currentSource = config.genericCurrentSource {
        sources.append(GenericCurrentSourceModel(config: currentSource))
    }

    // ECRH (Electron Cyclotron Resonance Heating)
    if let ecrh = config.ecrhSource {
        sources.append(ECRHSourceModel(config: ecrh))
    }

    // NBI (Neutral Beam Injection)
    if let nbi = config.nbiSource {
        sources.append(NBISourceModel(config: nbi))
    }

    // Pellet injection
    if let pellet = config.pelletSource {
        sources.append(PelletSourceModel(config: pellet))
    }

    // Gas puff
    if let gasPuff = config.gasPuffSource {
        sources.append(GasPuffSourceModel(config: gasPuff))
    }

    return sources
}
```

---

### 4. Update Section 6.2: PlotViewModel

Replace the `loadPlotData()` method:

```swift
@MainActor
@Observable
class PlotViewModel {
    var plotData: PlotData?
    var plotData3D: PlotData3D?

    var selectedPlotTypes: Set<PlotType> = [.tempDensity]
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
            let result = try dataStore.loadSimulationResult(simulationID: simulation.id)  // ✅ Returns SimulationResult

            // Use GotenxUI's built-in conversion
            let plotData = try PlotData(from: result)  // ✅ Already implemented in GotenxUI

            // Update cache
            if cachedPlotData.count >= cacheLimit {
                // Remove oldest entry (LRU)
                if let oldestKey = cachedPlotData.keys.first {
                    cachedPlotData.removeValue(forKey: oldestKey)
                }
            }

            cachedPlotData[simulation.id] = plotData
            self.plotData = plotData

            logger.info("Loaded plot data with \(plotData.nTime) time points")

        } catch {
            logger.error("Failed to load plot data: \(error)")
            errorMessage = "Failed to load plot data: \(error.localizedDescription)"
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
}
```

---

### 5. Add New Section: Data Model Reference

Add this new section to the specification:

## Appendix C: swift-gotenx Data Model Reference

### Runtime Types (Non-Codable)

These types contain GPU tensors and CANNOT be serialized:

#### CoreProfiles ❌ NOT Codable
```swift
public struct CoreProfiles: Sendable, Equatable {
    public let ionTemperature: EvaluatedArray      // GPU tensor
    public let electronTemperature: EvaluatedArray // GPU tensor
    public let electronDensity: EvaluatedArray     // GPU tensor
    public let poloidalFlux: EvaluatedArray        // GPU tensor
}
```

#### EvaluatedArray ❌ NOT Codable
```swift
public struct EvaluatedArray: @unchecked Sendable {
    private let array: MLXArray  // GPU tensor
}
```

---

### Storage Types (Codable)

These types are designed for serialization and actor boundaries:

#### SerializableProfiles ✅ Codable
```swift
public struct SerializableProfiles: Sendable, Codable {
    public let ionTemperature: [Float]
    public let electronTemperature: [Float]
    public let electronDensity: [Float]
    public let poloidalFlux: [Float]
}
```

#### TimePoint ✅ Codable
```swift
public struct TimePoint: Sendable, Codable {
    public let time: Float
    public let profiles: SerializableProfiles
    public let derived: DerivedQuantities?
    public let diagnostics: NumericalDiagnostics?
}
```

#### SimulationResult ✅ Codable
```swift
public struct SimulationResult: Sendable, Codable {
    public let finalProfiles: SerializableProfiles
    public let statistics: SimulationStatistics
    public let timeSeries: [TimePoint]?
}
```

#### Other Codable Types
- ✅ `SimulationConfiguration: Codable`
- ✅ `DerivedQuantities: Codable`
- ✅ `NumericalDiagnostics: Codable`
- ✅ `SimulationStatistics: Codable`

---

### Conversion Pattern

```swift
// Runtime → Storage
let serializable = coreProfiles.toSerializable()  // CoreProfiles → SerializableProfiles

// Storage → Runtime (if needed for computation)
let coreProfiles = CoreProfiles(from: serializable)  // SerializableProfiles → CoreProfiles

// SimulationState → TimePoint
let timePoint = state.toTimePoint()  // Internally uses .toSerializable()
```

---

### Data Flow Diagram

```
Simulation Execution:
┌─────────────────────────────────────────────────────────┐
│ SimulationOrchestrator (actor)                          │
│                                                          │
│  Internal State:                                        │
│  ├─ SimulationState                                     │
│  │   └─ profiles: CoreProfiles (GPU tensors) ❌ NOT Codable│
│  │                                                       │
│  Returns:                                               │
│  └─ SimulationResult ✅ Codable                         │
│      ├─ finalProfiles: SerializableProfiles             │
│      ├─ statistics: SimulationStatistics                │
│      └─ timeSeries: [TimePoint]                         │
│          └─ TimePoint                                   │
│              ├─ time: Float                             │
│              ├─ profiles: SerializableProfiles ✅        │
│              ├─ derived: DerivedQuantities? ✅           │
│              └─ diagnostics: NumericalDiagnostics? ✅    │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ SimulationDataStore (actor)                             │
│                                                          │
│  Storage:                                               │
│  ~/Library/Application Support/Gotenx/simulations/      │
│  └─ {simulation-id}/                                    │
│      ├─ config.json (SimulationConfiguration) ✅         │
│      └─ result.json (SimulationResult) ✅                │
│          Contains complete timeSeries: [TimePoint]       │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│ GotenxUI Visualization                                   │
│                                                          │
│  PlotData.init(from: SimulationResult) ✅                │
│  ├─ Extracts timeSeries: [TimePoint]                    │
│  ├─ Converts units (eV → keV, m⁻³ → 10²⁰ m⁻³)          │
│  └─ Creates PlotData for Chart views                    │
└─────────────────────────────────────────────────────────┘
```

---

## Document Updates Summary

| Section | Change Type | Description |
|---------|-------------|-------------|
| 4.1 | CRITICAL FIX | Remove custom `SnapshotData` structure |
| 5.2 | COMPLETE REWRITE | SimulationDataStore to use `SimulationResult` |
| 6.1 | MAJOR UPDATE | AppViewModel.runSimulation() - proper orchestrator init |
| 6.1 | MAJOR UPDATE | AppViewModel.saveResults() - use `SerializableProfiles` |
| 6.2 | COMPLETE REWRITE | PlotViewModel - use GotenxUI conversion |
| Appendix C | NEW SECTION | Data model reference and conversion patterns |

---

## Migration from v1.1

### Breaking Changes

1. **SimulationDataStore API**: Now stores `SimulationResult` instead of individual snapshots
2. **No custom SnapshotData**: Use `TimePoint` from swift-gotenx
3. **PlotViewModel**: Removed custom conversion, use GotenxUI's built-in `PlotData.init(from:)`

### Required swift-gotenx Extensions

Add these helper extensions to the App (not swift-gotenx):

```swift
extension SerializableProfiles {
    /// Create default ITER-like initial profiles
    static func defaultITERLike(nCells: Int) -> SerializableProfiles {
        let rho = (0..<nCells).map { Float($0) / Float(max(nCells - 1, 1)) }

        // Parabolic temperature profile: T = T0 * (1 - rho^2)
        let Ti = rho.map { 10000.0 * (1.0 - $0 * $0) }  // 10 keV peak
        let Te = rho.map { 10000.0 * (1.0 - $0 * $0) }

        // Parabolic density profile: n = n0 * (1 - rho^2)^0.5
        let ne = rho.map { 1e20 * pow(1.0 - $0 * $0, 0.5) }  // 10^20 m^-3 peak

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

extension StaticRuntimeParams {
    init(from config: StaticConfig) throws {
        // Map SimulationConfiguration.runtime.static to StaticRuntimeParams
        // This conversion logic needs to be implemented based on actual structures
        // See swift-gotenx/Sources/Gotenx/Configuration/ for details
        fatalError("Not implemented - requires mapping StaticConfig → StaticRuntimeParams")
    }
}

extension DynamicRuntimeParams {
    init(from config: DynamicConfig) throws {
        // Map SimulationConfiguration.runtime.dynamic to DynamicRuntimeParams
        fatalError("Not implemented - requires mapping DynamicConfig → DynamicRuntimeParams")
    }
}
```

---

## Testing Checklist

- [ ] SimulationDataStore can save/load `SimulationResult`
- [ ] AppViewModel properly initializes `SimulationOrchestrator` with `SerializableProfiles`
- [ ] PlotViewModel uses `PlotData.init(from: SimulationResult)`
- [ ] No code attempts to encode `CoreProfiles` directly
- [ ] All storage uses `SerializableProfiles` or `TimePoint`
- [ ] Build succeeds without type errors

---

**End of v2.0 Updates Document**
