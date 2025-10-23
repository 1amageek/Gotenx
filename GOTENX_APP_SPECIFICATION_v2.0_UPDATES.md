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

# v2.1 - Phase 9 Transport Models Support

**Version**: 2.1
**Date**: 2025-10-23
**Status**: PHASE 9 FEATURE INTEGRATION

---

## Overview

This update adds support for swift-gotenx Phase 9 features, enabling users to access all Transport models including the cutting-edge **Turbulence Transition** physics.

### Phase 9 New Features

**Transport Models Available:**
1. `constant` - Simple constant diffusivity (existing)
2. `bohmGyrobohm` - Empirical transport model (existing)
3. `qlknn` - Neural network transport model (macOS only, existing)
4. `densityTransition` - **NEW**: ITG↔RI regime transition

**Key Innovation:**
- Density-dependent turbulence regime transition
- Based on Kinoshita et al., *Phys. Rev. Lett.* **132**, 235101 (2024)
- Isotope effects properly implemented
- Critical bug fixes for numerical stability

---

## UI Design Extensions

### 1. ConfigInspectorView Enhancement

**Current State**: Read-only display of `modelType.rawValue`

**New Design**: Interactive Transport configuration section

```swift
struct ConfigInspectorView: View {
    let simulation: Simulation?
    @State private var selectedModelType: TransportModelType = .constant
    @State private var transportParameters: [String: Float] = [:]

    var body: some View {
        if let simulation = simulation,
           let configData = simulation.configurationData,
           let config = try? JSONDecoder().decode(SimulationConfiguration.self, from: configData) {

            Form {
                // Existing sections...

                // NEW: Transport Model Configuration
                Section {
                    Picker("Model Type", selection: $selectedModelType) {
                        ForEach(TransportModelType.allCases, id: \.self) { modelType in
                            Text(modelType.displayName).tag(modelType)
                        }
                    }
                    .pickerStyle(.menu)

                    // Dynamic parameters based on model type
                    TransportParametersView(
                        modelType: selectedModelType,
                        parameters: $transportParameters
                    )

                } header: {
                    Label("Transport Configuration", systemImage: "wind")
                } footer: {
                    Text(selectedModelType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### 2. TransportParametersView (New Component)

**Purpose**: Dynamic parameter input based on selected model

```swift
struct TransportParametersView: View {
    let modelType: TransportModelType
    @Binding var parameters: [String: Float]

    var body: some View {
        Group {
            switch modelType {
            case .constant:
                LabeledContent("Diffusivity") {
                    TextField("m²/s", value: binding(for: "diffusivity", default: 1.0), format: .number)
                        .multilineTextAlignment(.trailing)
                }

            case .bohmGyrobohm:
                LabeledContent("Bohm Coefficient") {
                    TextField("", value: binding(for: "bohm_coeff", default: 1.0), format: .number)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("GyroBohm Coefficient") {
                    TextField("", value: binding(for: "gyrobohm_coeff", default: 1.0), format: .number)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Ion Mass Number") {
                    TextField("", value: binding(for: "ion_mass_number", default: 2.0), format: .number)
                        .multilineTextAlignment(.trailing)
                }

            case .qlknn:
                Text("Uses neural network - no user parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .densityTransition:
                LabeledContent("Transition Density") {
                    TextField("m⁻³", value: binding(for: "transition_density", default: 2.5e19), format: .scientific)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Transition Width") {
                    TextField("m⁻³", value: binding(for: "transition_width", default: 0.5e19), format: .scientific)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Ion Mass Number") {
                    TextField("", value: binding(for: "ion_mass_number", default: 2.0), format: .number)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("RI Coefficient") {
                    TextField("", value: binding(for: "ri_coefficient", default: 0.5), format: .number)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func binding(for key: String, default defaultValue: Float) -> Binding<Float> {
        Binding(
            get: { parameters[key] ?? defaultValue },
            set: { parameters[key] = $0 }
        )
    }
}
```

### 3. Configuration Preset System

**New Feature**: Pre-configured templates for common scenarios

```swift
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
                builder.runtime.static.mesh.majorRadius = 3.0
                builder.runtime.static.mesh.minorRadius = 1.0
                builder.runtime.static.mesh.toroidalField = 2.5

                builder.runtime.dynamic.transport.modelType = .constant
                builder.runtime.dynamic.transport.parameters = [:]

                builder.output.saveInterval = 0.1
            }

        case .bohmGyroBohm:
            return SimulationConfiguration.build { builder in
                // Same basic config...
                builder.runtime.dynamic.transport.modelType = .bohmGyrobohm
                builder.runtime.dynamic.transport.parameters = [
                    "bohm_coeff": 1.0,
                    "gyrobohm_coeff": 1.0,
                    "ion_mass_number": 2.0
                ]
            }

        case .turbulenceTransition:
            return SimulationConfiguration.build { builder in
                // Same basic config...
                builder.runtime.dynamic.transport.modelType = .densityTransition
                builder.runtime.dynamic.transport.parameters = [
                    "transition_density": 2.5e19,
                    "transition_width": 0.5e19,
                    "ion_mass_number": 2.0,
                    "ri_coefficient": 0.5
                ]
            }

        case .qlknn:
            return SimulationConfiguration.build { builder in
                // Same basic config...
                builder.runtime.dynamic.transport.modelType = .qlknn
                builder.runtime.dynamic.transport.parameters = [:]
            }
        }
    }
}
```

### 4. SidebarView Preset Selection

**Enhancement**: Replace simple "New Simulation" button with Preset menu

```swift
struct SidebarView: View {
    // ... existing properties ...
    @State private var showPresetPicker = false

    var body: some View {
        List(selection: $selectedSimulation) {
            Section("Simulations") {
                ForEach(workspace.simulations) { simulation in
                    SimulationRowView(simulation: simulation)
                        .tag(simulation)
                }
                .onDelete(perform: deleteSimulations)
            }
        }
        .navigationTitle(workspace.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(ConfigurationPreset.allCases) { preset in
                        Button {
                            createSimulation(with: preset)
                        } label: {
                            Label(preset.rawValue, systemImage: preset.icon)
                        }
                    }
                } label: {
                    Label("New Simulation", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func createSimulation(with preset: ConfigurationPreset) {
        let config = preset.configuration
        guard let configData = try? JSONEncoder().encode(config) else { return }

        let simulation = Simulation(
            name: "New \(preset.rawValue)",
            configurationData: configData
        )
        simulation.workspace = workspace
        workspace.simulations.append(simulation)
        modelContext.insert(simulation)

        do {
            try modelContext.save()
            selectedSimulation = simulation
        } catch {
            print("Failed to create simulation: \(error)")
        }
    }
}
```

---

## Data Model Extensions

### 1. ConfigViewModel Updates

**New Properties:**

```swift
@MainActor
@Observable
final class ConfigViewModel {
    // Existing...
    var selectedPreset: ConfigurationPreset?
    var isEditingConfiguration: Bool = false

    // NEW: Transport model management
    var selectedTransportModel: TransportModelType = .constant
    var transportParameters: [String: Float] = [:]

    /// Create configuration with specified transport model
    func createConfiguration(
        preset: ConfigurationPreset,
        customParameters: [String: Float]? = nil
    ) -> Data? {
        var config = preset.configuration

        if let params = customParameters {
            // Override preset parameters with custom values
            config.runtime.dynamic.transport.parameters = params
        }

        return try? JSONEncoder().encode(config)
    }

    /// Validate transport parameters
    func validateParameters(for modelType: TransportModelType) -> Bool {
        switch modelType {
        case .densityTransition:
            guard let transitionDensity = transportParameters["transition_density"],
                  transitionDensity > 0 else { return false }
            guard let transitionWidth = transportParameters["transition_width"],
                  transitionWidth > 0 else { return false }
            return true

        case .bohmGyrobohm:
            // Coefficients should be positive
            let bohmCoeff = transportParameters["bohm_coeff"] ?? 1.0
            let gyroBohm = transportParameters["gyrobohm_coeff"] ?? 1.0
            return bohmCoeff >= 0 && gyroBohm >= 0

        case .constant, .qlknn:
            return true
        }
    }
}
```

### 2. TransportModelType Extension

**Add display helpers:**

```swift
extension TransportModelType {
    var displayName: String {
        switch self {
        case .constant: return "Constant"
        case .bohmGyrobohm: return "Bohm-GyroBohm"
        case .qlknn: return "QLKNN"
        case .densityTransition: return "Turbulence Transition"
        }
    }

    var description: String {
        switch self {
        case .constant:
            return "Simple constant diffusivity model"
        case .bohmGyrobohm:
            return "Empirical Bohm and GyroBohm scaling"
        case .qlknn:
            return "Neural network transport model (macOS only)"
        case .densityTransition:
            return "Density-dependent ITG↔RI transition with isotope effects"
        }
    }

    var requiredParameters: [String] {
        switch self {
        case .constant:
            return ["diffusivity"]
        case .bohmGyrobohm:
            return ["bohm_coeff", "gyrobohm_coeff", "ion_mass_number"]
        case .qlknn:
            return []
        case .densityTransition:
            return ["transition_density", "transition_width", "ion_mass_number", "ri_coefficient"]
        }
    }

    var defaultParameters: [String: Float] {
        switch self {
        case .constant:
            return ["diffusivity": 1.0]
        case .bohmGyrobohm:
            return [
                "bohm_coeff": 1.0,
                "gyrobohm_coeff": 1.0,
                "ion_mass_number": 2.0
            ]
        case .qlknn:
            return [:]
        case .densityTransition:
            return [
                "transition_density": 2.5e19,
                "transition_width": 0.5e19,
                "ion_mass_number": 2.0,
                "ri_coefficient": 0.5
            ]
        }
    }
}
```

---

## Implementation Priority

### Phase 1: Read-Only Display (✅ Already Done)
- [x] InspectorView shows `modelType.rawValue`
- [x] Basic configuration loading

### Phase 2: Preset System (Recommended Next)
- [ ] Implement `ConfigurationPreset` enum
- [ ] Add preset menu to SidebarView
- [ ] Test all 4 presets create valid configurations

### Phase 3: Interactive Configuration (Advanced)
- [ ] Implement `TransportParametersView`
- [ ] Add ConfigInspectorView Transport section
- [ ] Parameter validation
- [ ] Real-time configuration updates

### Phase 4: Advanced Features (Optional)
- [ ] Configuration import/export
- [ ] Parameter sensitivity visualization
- [ ] Model comparison tools

---

## Usage Examples

### Example 1: Create Turbulence Transition Simulation

```swift
// User flow:
// 1. Click "New Simulation" in SidebarView
// 2. Select "Turbulence Transition (Advanced)" from menu
// 3. Simulation created with preset parameters

// Result: Configuration
{
  "runtime": {
    "dynamic": {
      "transport": {
        "modelType": "densityTransition",
        "parameters": {
          "transition_density": 2.5e19,
          "transition_width": 0.5e19,
          "ion_mass_number": 2.0,
          "ri_coefficient": 0.5
        }
      }
    }
  }
}
```

### Example 2: Customize Transport Parameters

```swift
// User flow:
// 1. Select existing simulation
// 2. Open Inspector → Config tab
// 3. Change "Transition Density" to 3.0e19
// 4. Click "Save Configuration"

// ConfigViewModel handles update:
func updateTransportParameters() {
    var config = currentSimulation.configuration
    config.runtime.dynamic.transport.parameters["transition_density"] = 3.0e19

    if validateParameters(for: config.runtime.dynamic.transport.modelType) {
        currentSimulation.configurationData = try? JSONEncoder().encode(config)
    }
}
```

### Example 3: Compare Isotopes (H vs D)

```swift
// Create two simulations with different ion masses:

// Hydrogen (m = 1):
let configH = SimulationConfiguration.build { builder in
    builder.runtime.dynamic.transport.parameters["ion_mass_number"] = 1.0
}

// Deuterium (m = 2):
let configD = SimulationConfiguration.build { builder in
    builder.runtime.dynamic.transport.parameters["ion_mass_number"] = 2.0
}

// Run both and compare confinement times in plots
```

---

## Testing Checklist (Phase 9 Features)

- [ ] All 4 TransportModelType cases display correctly
- [ ] Preset menu creates valid configurations
- [ ] Turbulence Transition preset has correct parameters
- [ ] Parameter validation prevents invalid values
- [ ] Configuration serialization/deserialization works
- [ ] InspectorView shows transport parameters read-only
- [ ] No crashes when switching between models

---

## References

1. **swift-gotenx Phase 9 Implementation**
   - `docs/PHASE9_TURBULENCE_TRANSITION_IMPLEMENTATION.md`
   - `MHD_TURBULENCE_FIXES_SUMMARY.md`

2. **Kinoshita et al. (2024)**
   - "Turbulence Transition in Magnetically Confined Hydrogen and Deuterium Plasmas"
   - *Phys. Rev. Lett.* **132**, 235101

3. **swift-gotenx Configuration Examples**
   - `Examples/Configurations/turbulence_transition.json`

---

**End of v2.1 Updates Document**
