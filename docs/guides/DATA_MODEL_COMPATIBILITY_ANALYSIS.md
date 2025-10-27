# Data Model Compatibility Analysis

**Date**: 2025-10-22
**Status**: CRITICAL ISSUES IDENTIFIED

---

## Executive Summary

The current GOTENX_APP_SPECIFICATION.md v1.1 contains **fundamental data model incompatibilities** with swift-gotenx. The specification incorrectly assumes `CoreProfiles` is `Codable` and can be directly serialized, but it actually contains `EvaluatedArray` fields wrapping GPU tensors (`MLXArray`) which are NOT serializable.

**Impact**: The specification as written CANNOT be implemented without fundamental changes.

---

## Swift-Gotenx Data Model Architecture

### Runtime Types (GPU Computation, Non-Codable)

These types contain MLX GPU tensors and CANNOT be serialized:

#### 1. CoreProfiles ❌ NOT Codable
```swift
public struct CoreProfiles: Sendable, Equatable {
    public let ionTemperature: EvaluatedArray      // ❌ NOT Codable
    public let electronTemperature: EvaluatedArray // ❌ NOT Codable
    public let electronDensity: EvaluatedArray     // ❌ NOT Codable
    public let poloidalFlux: EvaluatedArray        // ❌ NOT Codable
}
```

**Why NOT Codable**: Contains `EvaluatedArray` which wraps `MLXArray` (GPU tensor).

#### 2. EvaluatedArray ❌ NOT Codable
```swift
public struct EvaluatedArray: @unchecked Sendable {
    private let array: MLXArray  // ❌ GPU tensor, NOT Codable
    public var value: MLXArray { array }
}
```

#### 3. SimulationState ❌ NOT Codable
```swift
public struct SimulationState: Sendable {
    public let profiles: CoreProfiles  // ❌ NOT Codable
    public let transport: TransportCoefficients?
    public let sources: SourceTerms?
    public let geometry: Geometry?
    public let derived: DerivedQuantities?      // ✅ Codable
    public let diagnostics: NumericalDiagnostics? // ✅ Codable
    // ...
}
```

**Why NOT Codable**: Contains `CoreProfiles`.

---

### Storage Types (Serialization, Codable)

These types are designed for actor boundaries and serialization:

#### 1. SerializableProfiles ✅ Codable
```swift
public struct SerializableProfiles: Sendable, Codable {
    public let ionTemperature: [Float]      // ✅ Simple array
    public let electronTemperature: [Float] // ✅ Simple array
    public let electronDensity: [Float]     // ✅ Simple array
    public let poloidalFlux: [Float]        // ✅ Simple array
}
```

**Purpose**: Codable wrapper for CoreProfiles.

#### 2. TimePoint ✅ Codable
```swift
public struct TimePoint: Sendable, Codable {
    public let time: Float
    public let profiles: SerializableProfiles      // ✅ Codable
    public let derived: DerivedQuantities?         // ✅ Codable
    public let diagnostics: NumericalDiagnostics?  // ✅ Codable
}
```

**Purpose**: Single snapshot for time series.

#### 3. SimulationResult ✅ Codable
```swift
public struct SimulationResult: Sendable, Codable {
    public let finalProfiles: SerializableProfiles // ✅ Codable
    public let statistics: SimulationStatistics    // ✅ Codable
    public let timeSeries: [TimePoint]?            // ✅ Codable
}
```

**Purpose**: Complete simulation output.

#### 4. Other Codable Types
- ✅ `SimulationConfiguration: Codable`
- ✅ `DerivedQuantities: Sendable, Codable`
- ✅ `NumericalDiagnostics: Sendable, Codable`
- ✅ `SimulationStatistics: Sendable, Codable`

---

### Conversion Pattern

Swift-gotenx provides bidirectional conversion:

```swift
// Runtime → Storage
extension CoreProfiles {
    public func toSerializable() -> SerializableProfiles {
        SerializableProfiles(
            ionTemperature: ionTemperature.value.asArray(Float.self),
            electronTemperature: electronTemperature.value.asArray(Float.self),
            electronDensity: electronDensity.value.asArray(Float.self),
            poloidalFlux: poloidalFlux.value.asArray(Float.self)
        )
    }
}

// Storage → Runtime
extension CoreProfiles {
    public init(from serializable: SerializableProfiles) {
        self.init(
            ionTemperature: EvaluatedArray(evaluating: MLXArray(serializable.ionTemperature)),
            electronTemperature: EvaluatedArray(evaluating: MLXArray(serializable.electronTemperature)),
            electronDensity: EvaluatedArray(evaluating: MLXArray(serializable.electronDensity)),
            poloidalFlux: EvaluatedArray(evaluating: MLXArray(serializable.poloidalFlux))
        )
    }
}

// SimulationState → TimePoint
extension SimulationState {
    public func toTimePoint() -> TimePoint {
        TimePoint(
            time: time,
            profiles: profiles.toSerializable(),  // ← Conversion happens here
            derived: derived,
            diagnostics: diagnostics
        )
    }
}
```

---

## SimulationOrchestrator API

```swift
public actor SimulationOrchestrator {
    // Initialization
    public init(
        staticParams: StaticRuntimeParams,
        initialProfiles: SerializableProfiles,  // ← Takes SerializableProfiles, NOT CoreProfiles
        transport: any TransportModel,
        sources: [any SourceModel] = [],
        samplingConfig: SamplingConfig = .balanced,
        adaptiveConfig: AdaptiveTimestepConfig = .default
    ) async

    // Main execution
    public func run(
        until endTime: Float,
        dynamicParams: DynamicRuntimeParams,
        saveInterval: Float? = nil
    ) async throws -> SimulationResult  // ← Returns SimulationResult (Codable)

    // Progress monitoring
    public func getProgress() async -> ProgressInfo
}
```

**Key Points**:
1. Takes `SerializableProfiles` as initial conditions (NOT `CoreProfiles`)
2. Returns `SimulationResult` containing `timeSeries: [TimePoint]?`
3. Each `TimePoint` contains `SerializableProfiles` (already converted)

---

## GotenxUI Integration

### PlotData Conversion

GotenxUI already provides conversion from `SimulationResult`:

```swift
// Sources/GotenxUI/Models/PlotData.swift
extension PlotData {
    /// Create PlotData from SimulationResult with unit conversion
    ///
    /// **Unit Conversions**:
    /// - Temperature: eV → keV (÷ 1000)
    /// - Density: m^-3 → 10^20 m^-3 (÷ 1e20)
    ///
    /// - Parameter result: Simulation result with time series
    /// - Throws: If time series is missing
    public init(from result: SimulationResult) throws {
        guard let timeSeries = result.timeSeries, !timeSeries.isEmpty else {
            throw PlotDataError.missingTimeSeries
        }

        // Extracts data from timeSeries[].profiles (SerializableProfiles)
        // and converts units for visualization
        // ...
    }
}
```

**Data Flow**:
```
SimulationResult → PlotData.init(from:) → PlotData → Chart views
```

---

## Critical Issues in Current Specification (v1.1)

### Issue 1: Wrong Data Model Definition

**Location**: Section 4.1 "Data Models"

**Current (WRONG)**:
```swift
// GOTENX_APP_SPECIFICATION.md v1.1
@Model
class SimulationSnapshot {
    var id: UUID
    var time: Float
    var profiles: Data  // ← Assumes CoreProfiles can be encoded
    var derived: Data?
    // ...

    init(time: Float, profiles: CoreProfiles, derived: DerivedQuantities? = nil) {
        self.id = UUID()
        self.time = time
        self.profiles = (try? JSONEncoder().encode(profiles)) ?? Data()  // ❌ FAILS: CoreProfiles is NOT Codable
        self.derivedQuantities = derived.flatMap { try? JSONEncoder().encode($0) }
        // ...
    }
}
```

**Why WRONG**: `CoreProfiles` is NOT `Codable` and CANNOT be JSON encoded.

**Correct**:
```swift
@Model
class SimulationSnapshot {
    var id: UUID
    var time: Float
    var profiles: Data  // Will store SerializableProfiles, NOT CoreProfiles
    var derived: Data?

    init(time: Float, profiles: SerializableProfiles, derived: DerivedQuantities? = nil) {
        self.id = UUID()
        self.time = time
        self.profiles = (try? JSONEncoder().encode(profiles)) ?? Data()  // ✅ SerializableProfiles IS Codable
        self.derivedQuantities = derived.flatMap { try? JSONEncoder().encode($0) }
        // ...
    }

    // OR better: Use TimePoint directly
    init(from timePoint: TimePoint, simulation: Simulation) {
        self.id = UUID()
        self.time = timePoint.time
        self.profiles = (try? JSONEncoder().encode(timePoint.profiles)) ?? Data()
        self.derivedQuantities = timePoint.derived.flatMap { try? JSONEncoder().encode($0) }
        self.diagnostics = timePoint.diagnostics.flatMap { try? JSONEncoder().encode($0) }
        self.simulation = simulation
        // ...
    }
}
```

---

### Issue 2: Wrong Storage Architecture

**Location**: Section 4.2.2 "SimulationDataStore"

**Current (WRONG)**:
```swift
// Custom JSONL format for snapshots
struct SnapshotData: Codable {
    let time: Float
    let profiles: CoreProfiles  // ❌ NOT Codable
    let derived: DerivedQuantities?
}
```

**Why WRONG**: Invents custom format instead of using swift-gotenx's existing types.

**Correct Option 1**: Store SimulationResult directly
```swift
// Store the entire SimulationResult (already Codable)
actor SimulationDataStore {
    func saveSimulationResult(_ result: SimulationResult, simulationID: UUID) throws {
        let url = snapshotsURL(for: simulationID)
        let data = try JSONEncoder().encode(result)  // ✅ SimulationResult IS Codable
        try data.write(to: url)
    }
}
```

**Correct Option 2**: Use TimePoint from swift-gotenx
```swift
// TimePoint is already defined in swift-gotenx and is Codable
actor SimulationDataStore {
    func appendSnapshot(_ timePoint: TimePoint, simulationID: UUID) throws {
        // TimePoint already contains SerializableProfiles
        let data = try JSONEncoder().encode(timePoint)  // ✅ TimePoint IS Codable
        // Append to JSONL file
    }

    func loadSnapshots(simulationID: UUID) throws -> [TimePoint] {
        // Load and decode TimePoint array
    }
}
```

---

### Issue 3: Wrong Conversion Code

**Location**: Section 5.1 "AppViewModel" and 5.5 "SimulationProgressHandler"

**Current (WRONG)**:
```swift
private func saveResults(simulation: Simulation, result: SimulationResult) async {
    // ...
    let snapshot = SimulationSnapshot(
        time: result.time,
        profiles: result.profiles,  // ❌ Assumes CoreProfiles
        derived: result.derived
    )
    // ...
}
```

**Why WRONG**: `result.profiles` doesn't exist. `SimulationResult` contains `finalProfiles: SerializableProfiles` and `timeSeries: [TimePoint]?`.

**Correct**:
```swift
private func saveResults(simulation: Simulation, result: SimulationResult) async {
    // Option 1: Store entire result
    try? await dataStore.saveSimulationResult(result, simulationID: simulation.id)

    // Option 2: Store individual snapshots from timeSeries
    if let timeSeries = result.timeSeries {
        for timePoint in timeSeries {
            let snapshot = SimulationSnapshot(
                from: timePoint,  // ✅ Use TimePoint from swift-gotenx
                simulation: simulation
            )
            modelContext.insert(snapshot)
        }
    }

    // Update simulation with final state
    simulation.finalProfiles = try? JSONEncoder().encode(result.finalProfiles)  // ✅ SerializableProfiles
    simulation.statistics = try? JSONEncoder().encode(result.statistics)
    simulation.status = .completed
}
```

---

### Issue 4: Missing Initial Profiles Conversion

**Location**: Section 5.1 "AppViewModel.runSimulation()"

**Current (WRONG)**:
```swift
simulationTask = Task { @MainActor in
    let orchestrator = SimulationOrchestrator()  // ❌ Wrong: No init params
    let result = try await orchestrator.run(
        config: config,  // ❌ Wrong: Takes RuntimeParams, not SimulationConfiguration
        // ...
    )
}
```

**Why WRONG**:
1. `SimulationOrchestrator` requires initialization with `initialProfiles: SerializableProfiles`
2. Takes `StaticRuntimeParams` and `DynamicRuntimeParams`, not `SimulationConfiguration`

**Correct**:
```swift
simulationTask = Task {
    // 1. Convert SimulationConfiguration to RuntimeParams
    let staticParams = StaticRuntimeParams(from: config.runtime.static)
    let dynamicParams = DynamicRuntimeParams(from: config.runtime.dynamic)

    // 2. Create initial profiles (SerializableProfiles)
    let initialProfiles = SerializableProfiles.defaultITERLike(nCells: staticParams.mesh.nCells)

    // 3. Create orchestrator (actor isolated)
    let orchestrator = await SimulationOrchestrator(
        staticParams: staticParams,
        initialProfiles: initialProfiles,  // ✅ SerializableProfiles
        transport: createTransportModel(config.runtime.dynamic.transport),
        sources: createSourceModels(config.runtime.dynamic.sources),
        samplingConfig: .balanced
    )

    // 4. Run simulation
    let result = try await orchestrator.run(
        until: config.time.end,
        dynamicParams: dynamicParams
    )

    // 5. Update UI on main actor
    await MainActor.run {
        self.saveResults(simulation: simulation, result: result)
    }
}
```

---

### Issue 5: Wrong PlotData Conversion

**Location**: Section 5.4 "PlotViewModel"

**Current (WRONG)**:
```swift
func loadPlotData(from simulation: Simulation) async {
    // Custom conversion logic invented
    // ...
}
```

**Why WRONG**: Reinvents conversion that already exists in GotenxUI.

**Correct**:
```swift
func loadPlotData(from simulation: Simulation) async {
    do {
        // Load SimulationResult from storage
        let result = try await dataStore.loadSimulationResult(simulationID: simulation.id)

        // Use GotenxUI's built-in conversion
        let plotData = try PlotData(from: result)  // ✅ Already implemented in GotenxUI

        await MainActor.run {
            self.plotData = plotData
        }
    } catch {
        logger.error("Failed to load plot data: \(error)")
    }
}
```

---

## Correct Data Flow

### 1. Simulation Setup
```
User Configuration
    ↓
SimulationConfiguration (Codable)
    ↓ Convert
StaticRuntimeParams + DynamicRuntimeParams
    ↓
SimulationOrchestrator.init(
    staticParams: StaticRuntimeParams,
    initialProfiles: SerializableProfiles  // ← Codable
)
```

### 2. Simulation Execution
```
SimulationOrchestrator (actor)
    ├─ Internal State: SimulationState
    │   └─ profiles: CoreProfiles (GPU tensors, NOT Codable)
    │
    └─ Public API: SimulationResult (Codable)
        ├─ finalProfiles: SerializableProfiles  ← Converted from CoreProfiles
        ├─ statistics: SimulationStatistics
        └─ timeSeries: [TimePoint]?
            └─ TimePoint
                ├─ time: Float
                ├─ profiles: SerializableProfiles  ← Already converted
                ├─ derived: DerivedQuantities?
                └─ diagnostics: NumericalDiagnostics?
```

### 3. Data Storage
```
SimulationResult (from orchestrator)
    ↓
SimulationDataStore (actor)
    ├─ Save as JSON file
    └─ Store metadata in SwiftData

SwiftData (metadata only):
    - Simulation.finalProfiles: Data (encoded SerializableProfiles)
    - Simulation.statistics: Data
    - SimulationSnapshot.profiles: Data (encoded SerializableProfiles)

File System (full data):
    - ~/Library/Application Support/Gotenx/simulations/{id}/result.json
      (Complete SimulationResult with timeSeries)
```

### 4. Visualization
```
SimulationResult (from storage)
    ↓
PlotData.init(from: result)  ← Built-in GotenxUI conversion
    ↓
PlotData
    ├─ Ti: [[Float]] in keV  ← Converted from SerializableProfiles
    ├─ Te: [[Float]] in keV
    ├─ ne: [[Float]] in 10²⁰ m⁻³
    └─ time: [Float]
    ↓
Chart views (SwiftUI)
```

---

## Required Specification Updates

### 1. Update Section 4.1: Data Models

Replace `SimulationSnapshot` to use `SerializableProfiles` or `TimePoint`:

```swift
@Model
class SimulationSnapshot {
    var id: UUID
    var time: Float
    var profiles: Data        // Encoded SerializableProfiles
    var derived: Data?        // Encoded DerivedQuantities
    var diagnostics: Data?    // Encoded NumericalDiagnostics
    var timestamp: Date
    var isBookmarked: Bool
    var simulation: Simulation?

    /// Initialize from swift-gotenx TimePoint
    init(from timePoint: TimePoint, simulation: Simulation) {
        self.id = UUID()
        self.time = timePoint.time
        self.profiles = (try? JSONEncoder().encode(timePoint.profiles)) ?? Data()
        self.derived = timePoint.derived.flatMap { try? JSONEncoder().encode($0) }
        self.diagnostics = timePoint.diagnostics.flatMap { try? JSONEncoder().encode($0) }
        self.timestamp = Date()
        self.isBookmarked = false
        self.simulation = simulation
    }
}
```

### 2. Update Section 4.2.2: SimulationDataStore

Store `SimulationResult` directly:

```swift
actor SimulationDataStore {
    func saveSimulationResult(_ result: SimulationResult, simulationID: UUID) throws {
        let url = resultURL(for: simulationID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(result)
        try data.write(to: url)
    }

    func loadSimulationResult(simulationID: UUID) throws -> SimulationResult {
        let url = resultURL(for: simulationID)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(SimulationResult.self, from: data)
    }
}
```

### 3. Update Section 5.1: AppViewModel.runSimulation()

Fix orchestrator initialization and result handling:

```swift
func runSimulation(_ simulation: Simulation) async {
    guard let configData = simulation.configuration,
          let config = try? JSONDecoder().decode(SimulationConfiguration.self, from: configData) else {
        logger.error("Invalid simulation configuration")
        return
    }

    simulationTask = Task {
        do {
            // Convert configuration to runtime params
            let staticParams = StaticRuntimeParams(from: config.runtime.static)
            let dynamicParams = DynamicRuntimeParams(from: config.runtime.dynamic)

            // Create initial profiles
            let initialProfiles = SerializableProfiles.defaultITERLike(nCells: staticParams.mesh.nCells)

            // Create orchestrator
            let orchestrator = await SimulationOrchestrator(
                staticParams: staticParams,
                initialProfiles: initialProfiles,
                transport: createTransportModel(config.runtime.dynamic.transport),
                sources: createSourceModels(config.runtime.dynamic.sources),
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
                saveResults(simulation: simulation, result: result)
            }

        } catch {
            await MainActor.run {
                logger.error("Simulation failed: \(error)")
                simulation.status = .failed(error: error.localizedDescription)
            }
        }
    }
}

private func saveResults(simulation: Simulation, result: SimulationResult) {
    do {
        // Store result to file
        try await dataStore.saveSimulationResult(result, simulationID: simulation.id)

        // Update simulation metadata
        simulation.finalProfiles = try? JSONEncoder().encode(result.finalProfiles)
        simulation.statistics = try? JSONEncoder().encode(result.statistics)
        simulation.status = .completed
        simulation.modifiedAt = Date()

        // Optionally create snapshots in SwiftData for quick access
        if let timeSeries = result.timeSeries {
            for timePoint in timeSeries {
                let snapshot = SimulationSnapshot(from: timePoint, simulation: simulation)
                modelContext.insert(snapshot)
            }
        }

        try modelContext.save()

    } catch {
        logger.error("Failed to save results: \(error)")
    }
}
```

### 4. Update Section 5.4: PlotViewModel

Use GotenxUI's built-in conversion:

```swift
@Observable
class PlotViewModel {
    var plotData: PlotData?
    private let dataStore: SimulationDataStore
    private let logger = Logger(subsystem: "com.gotenx.app", category: "PlotViewModel")

    func loadPlotData(from simulation: Simulation) async {
        do {
            // Load SimulationResult from storage
            let result = try await dataStore.loadSimulationResult(simulationID: simulation.id)

            // Use GotenxUI's built-in conversion
            let plotData = try PlotData(from: result)

            await MainActor.run {
                self.plotData = plotData
            }

        } catch PlotDataError.missingTimeSeries {
            logger.warning("No time series data available for plotting")
        } catch {
            logger.error("Failed to load plot data: \(error)")
        }
    }
}
```

### 5. Add Section: Runtime Parameters Conversion

Document how to convert `SimulationConfiguration` to runtime parameters:

```swift
extension StaticRuntimeParams {
    init(from config: StaticConfig) {
        // Map SimulationConfiguration.runtime.static to StaticRuntimeParams
        // This conversion logic needs to be implemented
    }
}

extension DynamicRuntimeParams {
    init(from config: DynamicConfig) {
        // Map SimulationConfiguration.runtime.dynamic to DynamicRuntimeParams
        // This conversion logic needs to be implemented
    }
}
```

---

## Action Items

1. ✅ **Analyze swift-gotenx data models** - COMPLETED
2. ✅ **Identify compatibility issues** - COMPLETED
3. ✅ **Document issues** - THIS DOCUMENT
4. ⏳ **Update GOTENX_APP_SPECIFICATION.md** - NEXT
   - Fix Section 4.1: Data Models
   - Fix Section 4.2.2: SimulationDataStore
   - Fix Section 5.1: AppViewModel
   - Fix Section 5.4: PlotViewModel
   - Add Section: Runtime Parameters Conversion
   - Add Section: Data Model Reference

---

## Conclusion

The current specification has **fundamental incompatibilities** with swift-gotenx's data model. The main issue is assuming `CoreProfiles` is `Codable` when it contains GPU tensors.

**Solution**: Use swift-gotenx's existing serializable types:
- ✅ `SerializableProfiles` instead of `CoreProfiles` for storage
- ✅ `TimePoint` for snapshots (already defined and Codable)
- ✅ `SimulationResult` as the primary storage format
- ✅ `PlotData.init(from: SimulationResult)` for visualization

These types are already designed, tested, and ready to use. The App should leverage them instead of inventing custom formats.
