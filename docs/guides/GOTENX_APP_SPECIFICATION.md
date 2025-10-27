# Gotenx App - Complete Specification

**Version**: 1.1
**Date**: 2024-10-22
**Author**: Gotenx Development Team
**Status**: Updated with production-ready improvements

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [UI/UX Design](#3-uiux-design)
4. [Data Models](#4-data-models)
5. [Data Storage Strategy](#5-data-storage-strategy)
6. [ViewModels](#6-viewmodels)
7. [View Implementation](#7-view-implementation)
8. [Workflows](#8-workflows)
9. [Project Structure](#9-project-structure)
10. [Implementation Roadmap](#10-implementation-roadmap)
11. [Additional Requirements](#11-additional-requirements)

---

## 1. Project Overview

### 1.1 Purpose

Gotenx App is a native macOS/iOS application for running and visualizing tokamak fusion reactor simulations powered by **swift-gotenx** (Swift implementation of Google DeepMind's TORAX).

### 1.2 Key Features

- **Simulation Execution**: Configure and run plasma transport simulations
- **Real-time Monitoring**: Live progress tracking and plot updates
- **Interactive Visualization**: 2D/3D plots with time-series animation
- **Result Management**: Hybrid storage (SwiftData + file-based)
- **Comparison Tools**: Side-by-side analysis of multiple simulations
- **Export Capabilities**: PNG, PDF, CSV, JSON export

### 1.3 Platform Support

- **macOS 26.0+** (Primary target)
- **iOS 26.0+** (Future support)
- **visionOS 26.0+** (Planned)

### 1.4 Technology Stack

- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData (metadata) + File-based storage (snapshot data)
- **Concurrency**: Swift Concurrency (async/await, actors)
- **Reactive Programming**: Observation framework
- **Simulation Engine**: swift-gotenx (Package dependency)
- **Visualization**: Swift Charts, GotenxUI
- **Logging**: OSLog framework

---

## 2. Architecture

### 2.1 System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Gotenx App                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │              SwiftUI Views                       │   │
│  │  (ContentView, SidebarView, MainCanvasView...)   │   │
│  └───────────────────┬──────────────────────────────┘   │
│                      │                                   │
│  ┌───────────────────▼──────────────────────────────┐   │
│  │            ViewModels (@Observable)              │   │
│  │   (AppViewModel, PlotViewModel, ConfigViewModel) │   │
│  └───────────────────┬──────────────────────────────┘   │
│                      │                                   │
│  ┌───────────────────▼──────────────────────────────┐   │
│  │        SwiftData Models (@Model)                 │   │
│  │  (Workspace, Simulation - metadata only)         │   │
│  └───────────────────┬──────────────────────────────┘   │
│                      │                                   │
│  ┌───────────────────▼──────────────────────────────┐   │
│  │     SimulationDataStore (actor)                  │   │
│  │  (File-based snapshot storage)                   │   │
│  └───────────────────┬──────────────────────────────┘   │
└────────────────────┬─┴──────────────────────────────────┘
                     │
         ┌───────────▼──────────────┐
         │     swift-gotenx         │
         │  (Package Dependency)    │
         ├──────────────────────────┤
         │ • Gotenx (Core)          │
         │ • GotenxPhysics          │
         │ • GotenxUI               │
         ├──────────────────────────┤
         │ SimulationOrchestrator   │
         │ TransportModels (QLKNN)  │
         │ FVM Solver               │
         │ PlotData, GotenxPlotView │
         └──────────────────────────┘
```

### 2.2 Dependency Management

**Package.swift** (Gotenx App):

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Gotenx",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        // swift-gotenx (local path or GitHub)
        .package(path: "../swift-gotenx"),
    ],
    targets: [
        .executableTarget(
            name: "Gotenx",
            dependencies: [
                .product(name: "Gotenx", package: "swift-gotenx"),
                .product(name: "GotenxPhysics", package: "swift-gotenx"),
                .product(name: "GotenxUI", package: "swift-gotenx"),
            ]
        )
    ]
)
```

---

## 3. UI/UX Design

### 3.1 Overall Layout (3-Column Design)

```
┌──────────────────────────────────────────────────────────────────┐
│  [▶︎] [⏸] [⏹]    ━━━━━━━ 45%    t=0.45s/2.0s    [⚙️] [📁] [💾]  │ ← Toolbar
├─────────────┬──────────────────────────────────┬─────────────────┤
│             │                                  │                 │
│  Sidebar    │        Main Canvas               │   Inspector     │
│  (250pt)    │                                  │   (300pt)       │
│             │                                  │                 │
│ 📁 Projects │  ┌────────────────────────────┐  │ 📊 Plot         │
│ ├─ ITER-1   │  │                            │  │ ├─ Type         │
│ │  ├─ Config│  │    Chart View              │  │ ├─ Style        │
│ │  └─ Results│  │    (Temperature Profile)   │  │ └─ Export       │
│ │     ├─ t=0│  │                            │  │                 │
│ │     ├─ t=1│  │                            │  │ 📐 Data         │
│ │     └─ t=2│  └────────────────────────────┘  │ ├─ Statistics   │
│ └─ ITER-2   │                                  │ └─ Selection    │
│    └─ ...   │  [Time  ━━━━━●━━━━━━━━ ]       │                 │
│             │  0.0s              2.0s          │ ⚙️ Config       │
│ [+ New]     │                                  │ ├─ Parameters   │
│             │  [Ti] [Te] [ne] [Q] [3D] [+]    │ └─ Validation   │
│             │                                  │                 │
└─────────────┴──────────────────────────────────┴─────────────────┘
```

### 3.2 Top Toolbar

#### Left Section
- **▶︎ Run**: Start simulation (⌘R)
- **⏸ Pause**: Pause execution
- **⏹ Stop**: Stop and reset

#### Center Section
- **Progress Bar**: Visual progress indicator
- **Time Display**: `t = 0.45s / 2.0s`

#### Right Section
- **⚙️ Settings**: App preferences
- **📁 Open**: Load project/configuration
- **💾 Save**: Save workspace
- **📤 Export**: Export results

### 3.3 Left Sidebar (Project Navigator)

#### Hierarchy

```
📁 Workspace
├── 📊 ITER-like (QLKNN) ●running
│   ├── 📝 Configuration
│   └── 📈 Results (23 snapshots)
│       ├── 🔖 t = 0.0s (Initial) ⭐bookmarked
│       ├── ⏱️ t = 0.1s
│       ├── ⏱️ t = 0.2s
│       ⋮
│       └── ⏱️ t = 2.0s (Final)
│
├── 📊 Bohm-GyroBohm ✓completed
│   ├── 📝 Configuration
│   └── 📈 Results (18 snapshots)
│
├── 📊 High-Beta Test ⚠️failed
│
└── 📊 Comparison: ITER vs Bohm
    └── 📊 Difference Plots
```

#### Status Icons
- **●** Running (animated)
- **⏸** Paused
- **✓** Completed
- **⚠️** Failed
- **○** Draft

#### Context Menu
```
Run
Pause
Stop
────────
Duplicate
Rename
Export...
────────
Delete
```

### 3.4 Main Canvas, Inspector - Same as v1.0

(Content unchanged from original specification)

---

## 4. Data Models

### 4.1 SwiftData Schema (Lightweight Metadata Only)

```swift
import SwiftData
import Foundation
import Gotenx

// Workspace (Top-level container)
@Model
class Workspace {
    var id: UUID
    var name: String
    var simulations: [Simulation] = []
    var comparisons: [Comparison] = []
    var createdAt: Date
    var modifiedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// Simulation (Metadata only - actual data in files)
@Model
class Simulation {
    var id: UUID
    var name: String
    var configurationData: Data?  // SimulationConfiguration encoded
    var status: SimulationStatusEnum
    var createdAt: Date
    var modifiedAt: Date
    var tags: [String] = []
    var notes: String = ""

    // Snapshot metadata (lightweight summary)
    var snapshotMetadata: [SnapshotMetadata] = []

    // Reference to external data file
    var dataFileURL: URL?

    init(name: String, configuration: SimulationConfiguration) {
        self.id = UUID()
        self.name = name
        self.configurationData = try? JSONEncoder().encode(configuration)
        self.status = .draft
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // Helper for decoding configuration
    var configuration: SimulationConfiguration? {
        guard let data = configurationData else { return nil }
        return try? JSONDecoder().decode(SimulationConfiguration.self, from: data)
    }

    // Update configuration
    func updateConfiguration(_ config: SimulationConfiguration) throws {
        self.configurationData = try JSONEncoder().encode(config)
        self.modifiedAt = Date()
    }
}

// Simulation Status
enum SimulationStatusEnum: Codable {
    case draft
    case queued
    case running(progress: Double)
    case paused(at: Double)
    case completed
    case failed(error: String)
    case cancelled
}

// Snapshot Metadata (Lightweight - stored in SwiftData)
struct SnapshotMetadata: Codable {
    var time: Float
    var index: Int

    // Summary statistics (for quick preview without loading full data)
    var coreTi: Float      // Core ion temperature [keV]
    var edgeTi: Float      // Edge ion temperature [keV]
    var avgNe: Float       // Average density [10^20 m^-3]
    var peakNe: Float      // Peak density [10^20 m^-3]

    // Derived quantities summary
    var plasmaCurrentMA: Float?  // Plasma current [MA]
    var fusionGainQ: Float?      // Fusion gain Q

    var isBookmarked: Bool = false
}

// Comparison
@Model
class Comparison {
    var id: UUID
    var name: String
    var simulationIDs: [UUID] = []  // References only
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

// Configuration Preset
@Model
class ConfigurationPreset {
    var id: UUID
    var name: String
    var configurationData: Data
    var description: String
    var isBuiltIn: Bool

    init(name: String, configuration: SimulationConfiguration, description: String = "", isBuiltIn: Bool = false) {
        self.id = UUID()
        self.name = name
        self.configurationData = (try? JSONEncoder().encode(configuration)) ?? Data()
        self.description = description
        self.isBuiltIn = isBuiltIn
    }

    var configuration: SimulationConfiguration? {
        try? JSONDecoder().decode(SimulationConfiguration.self, from: configurationData)
    }
}
```

---

## 5. Data Storage Strategy

### 5.1 Hybrid Storage Architecture

**Problem**: Storing thousands of snapshots directly in SwiftData causes:
- Database bloat
- Poor query performance
- Memory inefficiency

**Solution**: Hybrid approach

```
SwiftData (gotenx.sqlite):
- Workspace
- Simulation (metadata only)
- ConfigurationPreset

File System:
~/Library/Application Support/Gotenx/simulations/
├── {simulation-id-1}/
│   ├── config.json          # Human-readable configuration
│   ├── snapshots.jsonl      # Snapshot data (JSON Lines format)
│   └── metadata.json        # Optional: Additional metadata
└── {simulation-id-2}/
    └── ...
```

### 5.2 SimulationDataStore Implementation

```swift
import Foundation
import Gotenx
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "datastore")

/// File-based storage for simulation snapshot data
actor SimulationDataStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    enum StorageError: LocalizedError {
        case directoryCreationFailed(URL)
        case fileWriteFailed(URL, Error)
        case fileReadFailed(URL, Error)
        case corruptedData(URL)
        case simulationNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let url):
                return "Failed to create directory at \(url.path)"
            case .fileWriteFailed(let url, let error):
                return "Failed to write file at \(url.path): \(error.localizedDescription)"
            case .fileReadFailed(let url, let error):
                return "Failed to read file at \(url.path): \(error.localizedDescription)"
            case .corruptedData(let url):
                return "Corrupted data at \(url.path)"
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
        encoder.outputFormatting = [.sortedKeys]

        decoder = JSONDecoder()

        logger.info("SimulationDataStore initialized at \(self.baseURL.path)")
    }

    // MARK: - Write Operations

    /// Save a snapshot to file
    func saveSnapshot(
        _ profiles: CoreProfiles,
        derived: DerivedQuantities?,
        time: Float,
        for simulationID: UUID
    ) async throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        // Create simulation directory if needed
        if !fileManager.fileExists(atPath: simDir.path) {
            do {
                try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
                logger.debug("Created simulation directory: \(simDir.path)")
            } catch {
                logger.error("Failed to create simulation directory: \(error.localizedDescription)")
                throw StorageError.directoryCreationFailed(simDir)
            }
        }

        let snapshotFile = simDir.appendingPathComponent("snapshots.jsonl")

        // Create snapshot data
        let snapshotData = SnapshotData(
            time: time,
            profiles: profiles,
            derived: derived
        )

        do {
            let data = try encoder.encode(snapshotData)
            var line = String(data: data, encoding: .utf8)!
            line.append("\n")

            // Append to JSONL file
            if fileManager.fileExists(atPath: snapshotFile.path) {
                let handle = try FileHandle(forWritingTo: snapshotFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line.data(using: .utf8)!)
            } else {
                try line.write(to: snapshotFile, atomically: true, encoding: .utf8)
            }

            logger.trace("Saved snapshot at t=\(time)s for simulation \(simulationID.uuidString)")

        } catch {
            logger.error("Failed to save snapshot: \(error.localizedDescription)")
            throw StorageError.fileWriteFailed(snapshotFile, error)
        }
    }

    /// Save configuration to human-readable JSON
    func saveConfiguration(_ config: SimulationConfiguration, for simulationID: UUID) async throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        if !fileManager.fileExists(atPath: simDir.path) {
            try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
        }

        let configFile = simDir.appendingPathComponent("config.json")

        do {
            let prettyEncoder = JSONEncoder()
            prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try prettyEncoder.encode(config)
            try data.write(to: configFile)
            logger.debug("Saved configuration for simulation \(simulationID.uuidString)")
        } catch {
            throw StorageError.fileWriteFailed(configFile, error)
        }
    }

    // MARK: - Read Operations

    /// Load all snapshots for a simulation
    func loadSnapshots(for simulationID: UUID) async throws -> [(time: Float, profiles: CoreProfiles, derived: DerivedQuantities?)] {
        let snapshotFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("snapshots.jsonl")

        guard fileManager.fileExists(atPath: snapshotFile.path) else {
            logger.warning("Snapshot file not found for simulation \(simulationID.uuidString)")
            return []
        }

        do {
            let contents = try String(contentsOf: snapshotFile, encoding: .utf8)

            let snapshots = try contents
                .split(separator: "\n")
                .filter { !$0.isEmpty }
                .map { line -> (Float, CoreProfiles, DerivedQuantities?) in
                    guard let snapshot = try? decoder.decode(SnapshotData.self, from: Data(line.utf8)) else {
                        throw StorageError.corruptedData(snapshotFile)
                    }
                    return (snapshot.time, snapshot.profiles, snapshot.derived)
                }

            logger.info("Loaded \(snapshots.count) snapshots for simulation \(simulationID.uuidString)")
            return snapshots

        } catch {
            logger.error("Failed to load snapshots: \(error.localizedDescription)")
            throw StorageError.fileReadFailed(snapshotFile, error)
        }
    }

    /// Load a specific snapshot by index
    func loadSnapshot(at index: Int, for simulationID: UUID) async throws -> (time: Float, profiles: CoreProfiles, derived: DerivedQuantities?) {
        let snapshots = try await loadSnapshots(for: simulationID)

        guard index >= 0 && index < snapshots.count else {
            throw StorageError.corruptedData(
                baseURL.appendingPathComponent(simulationID.uuidString)
            )
        }

        return snapshots[index]
    }

    // MARK: - Delete Operations

    /// Delete all data for a simulation
    func deleteSimulation(_ simulationID: UUID) async throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)

        guard fileManager.fileExists(atPath: simDir.path) else {
            logger.warning("Simulation directory not found: \(simDir.path)")
            return
        }

        do {
            try fileManager.removeItem(at: simDir)
            logger.info("Deleted simulation data: \(simulationID.uuidString)")
        } catch {
            logger.error("Failed to delete simulation: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Utility

    /// Get file size for a simulation
    func getStorageSize(for simulationID: UUID) async throws -> Int64 {
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

// MARK: - Supporting Types

private struct SnapshotData: Codable {
    let time: Float
    let profiles: CoreProfiles
    let derived: DerivedQuantities?
}
```

---

## 6. ViewModels

### 6.1 AppViewModel (Production-Ready)

```swift
import SwiftUI
import Observation
import Gotenx
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "simulation")

@MainActor
@Observable
class AppViewModel {
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
    var liveProfiles: CoreProfiles?
    var liveDerived: DerivedQuantities?
    private var lastUpdateTime: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 0.1  // 100ms

    // UI state
    var showInspector: Bool = true
    var showSidebar: Bool = true
    var errorMessage: String?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    // MARK: - Simulation Operations

    /// Create a new simulation
    func createSimulation(name: String, config: SimulationConfiguration) async throws {
        let simulation = Simulation(name: name, configuration: config)
        workspace.simulations.append(simulation)
        selectedSimulation = simulation

        // Save configuration to file
        let store = try getDataStore()
        try await store.saveConfiguration(config, for: simulation.id)

        logger.info("Created simulation: \(name)")
    }

    /// Run simulation with proper actor isolation and error handling
    func runSimulation(_ simulation: Simulation) async throws {
        guard simulationTask == nil else {
            throw AppError.simulationAlreadyRunning
        }

        guard let config = simulation.configuration else {
            throw AppError.invalidConfiguration
        }

        logger.info("Starting simulation: \(simulation.name)")

        simulationTask = Task { @MainActor in
            isSimulationRunning = true
            isPaused = false
            simulationProgress = 0.0
            simulation.status = .running(progress: 0.0)
            totalSimulationTime = config.time.end
            lastUpdateTime = .distantPast

            // Get data store
            let store = try getDataStore()

            // Create orchestrator (non-MainActor)
            let orchestrator = SimulationOrchestrator()

            do {
                // Run simulation with progress callbacks
                let result = try await orchestrator.run(
                    config: config,
                    progressCallback: { [weak self] progress in
                        // Callback executed on background actor
                        // Must hop to MainActor for UI updates
                        await MainActor.run {
                            self?.handleProgress(progress, simulation: simulation)
                        }
                    }
                )

                // Save results
                try await saveResults(result, to: simulation, using: store)

                // Update status
                simulation.status = .completed
                logger.notice("Simulation completed successfully: \(simulation.name)")

            } catch is CancellationError {
                simulation.status = .cancelled
                logger.info("Simulation cancelled: \(simulation.name)")
            } catch {
                simulation.status = .failed(error: error.localizedDescription)
                errorMessage = error.localizedDescription
                logger.error("Simulation failed: \(error.localizedDescription)")
                throw error
            }

            isSimulationRunning = false
            simulationTask = nil
        }

        try await simulationTask?.value
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
    func resumeSimulation() async throws {
        guard isPaused, let simulation = selectedSimulation else { return }

        isPaused = false
        isSimulationRunning = true
        simulation.status = .running(progress: simulationProgress)

        logger.info("Simulation resumed")

        // TODO: Implement resume from checkpoint
        // Requires swift-gotenx support for resuming from saved state
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
    func deleteSimulation(_ simulation: Simulation) async throws {
        // Delete file data
        let store = try getDataStore()
        try await store.deleteSimulation(simulation.id)

        // Remove from workspace
        workspace.simulations.removeAll { $0.id == simulation.id }

        if selectedSimulation?.id == simulation.id {
            selectedSimulation = nil
        }

        logger.info("Deleted simulation: \(simulation.name)")
    }

    // MARK: - Private Methods

    @MainActor
    private func handleProgress(_ progress: ProgressInfo, simulation: Simulation) {
        let now = Date()

        // Time-based throttling for UI updates
        if now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval {
            let progressRatio = Double(progress.currentTime) / Double(totalSimulationTime)
            simulationProgress = progressRatio
            currentSimulationTime = progress.currentTime
            liveProfiles = progress.profiles
            liveDerived = progress.derivedQuantities
            lastUpdateTime = now

            logger.trace("Progress: \(Int(progressRatio * 100))%, t=\(progress.currentTime)s")
        }

        // Always update status (lightweight operation)
        simulation.status = .running(progress: Double(progress.currentTime) / Double(totalSimulationTime))
    }

    @MainActor
    private func saveResults(
        _ result: SimulationResult,
        to simulation: Simulation,
        using store: SimulationDataStore
    ) async throws {
        guard let timeSeries = result.timeSeries else {
            logger.warning("No time series data in simulation result")
            return
        }

        logger.info("Saving \(timeSeries.count) snapshots...")

        // Save snapshots to file
        for timePoint in timeSeries {
            try await store.saveSnapshot(
                timePoint.profiles,
                derived: timePoint.derived,
                time: timePoint.time,
                for: simulation.id
            )

            // Create lightweight metadata
            let metadata = SnapshotMetadata(
                time: timePoint.time,
                index: simulation.snapshotMetadata.count,
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

            simulation.snapshotMetadata.append(metadata)
        }

        // Update simulation with data file URL
        simulation.dataFileURL = store.baseURL.appendingPathComponent(simulation.id.uuidString)

        logger.notice("Saved \(timeSeries.count) snapshots for simulation \(simulation.name)")
    }

    private func getDataStore() throws -> SimulationDataStore {
        if let existing = dataStore {
            return existing
        }

        let store = try SimulationDataStore()
        dataStore = store
        return store
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
```

### 6.2 PlotViewModel

```swift
import SwiftUI
import Observation
import GotenxUI
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "plotting")

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
    func loadPlotData(for simulation: Simulation) async throws {
        logger.info("Loading plot data for simulation: \(simulation.name)")

        // Check cache
        if let cached = cachedPlotData[simulation.id] {
            self.plotData = cached
            logger.debug("Using cached plot data")
            return
        }

        // Load from file
        let dataStore = try SimulationDataStore()
        let snapshots = try await dataStore.loadSnapshots(for: simulation.id)

        guard !snapshots.isEmpty else {
            logger.warning("No snapshots found for simulation")
            throw PlotError.noData
        }

        // Convert to PlotData
        // TODO: Requires PlotData(from: snapshots) initializer in swift-gotenx
        // For now, use adapter pattern
        let plotData = try convertSnapshotsToPlotData(snapshots)

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

    /// Export plot as image
    func exportPlot(as format: ExportFormat, to url: URL) async throws {
        // TODO: Implement export functionality
        logger.info("Exporting plot as \(format)")
    }

    // MARK: - Private Helpers

    private func convertSnapshotsToPlotData(
        _ snapshots: [(time: Float, profiles: CoreProfiles, derived: DerivedQuantities?)]
    ) throws -> PlotData {
        // Adapter pattern to convert snapshots to PlotData
        // This is a workaround until PlotData(from: snapshots) is implemented in swift-gotenx

        let nTime = snapshots.count
        let nCells = snapshots[0].profiles.ionTemperature.count

        // Generate rho coordinate
        let rho = (0..<nCells).map { Float($0) / Float(max(nCells - 1, 1)) }

        // Extract time array
        let time = snapshots.map { $0.time }

        // Convert temperature profiles: eV → keV
        let Ti = snapshots.map { snapshot in
            snapshot.profiles.ionTemperature.map { $0 / 1000.0 }
        }
        let Te = snapshots.map { snapshot in
            snapshot.profiles.electronTemperature.map { $0 / 1000.0 }
        }

        // Convert density profiles: m^-3 → 10^20 m^-3
        let ne = snapshots.map { snapshot in
            snapshot.profiles.electronDensity.map { $0 / 1e20 }
        }

        // Poloidal flux
        let psi = snapshots.map { $0.profiles.poloidalFlux }

        // Placeholder for unimplemented fields
        let zeroProfile = Array(repeating: Float(0.0), count: nCells)
        let zeroProfiles = Array(repeating: zeroProfile, count: nTime)
        let zeroScalar = Array(repeating: Float(0.0), count: nTime)

        // Extract derived quantities
        let hasDerived = snapshots.contains { $0.derived != nil }

        return PlotData(
            rho: rho,
            time: time,
            Ti: Ti,
            Te: Te,
            ne: ne,
            q: zeroProfiles,
            magneticShear: zeroProfiles,
            psi: psi,
            chiTotalIon: zeroProfiles,
            chiTotalElectron: zeroProfiles,
            chiTurbIon: zeroProfiles,
            chiTurbElectron: zeroProfiles,
            dFace: zeroProfiles,
            jTotal: zeroProfiles,
            jOhmic: zeroProfiles,
            jBootstrap: zeroProfiles,
            jECRH: zeroProfiles,
            ohmicHeatSource: zeroProfiles,
            fusionHeatSource: zeroProfiles,
            pICRHIon: zeroProfiles,
            pICRHElectron: zeroProfiles,
            pECRHElectron: zeroProfiles,
            IpProfile: hasDerived ? snapshots.map { $0.derived?.I_plasma ?? 0.0 } : zeroScalar,
            IBootstrap: hasDerived ? snapshots.map { $0.derived?.I_bootstrap ?? 0.0 } : zeroScalar,
            IECRH: zeroScalar,
            qFusion: hasDerived ? snapshots.map { snapshot in
                guard let derived = snapshot.derived else { return 0.0 }
                let P_input = derived.P_auxiliary + derived.P_ohmic + 1e-10
                return derived.P_fusion / P_input
            } : zeroScalar,
            pAuxiliary: hasDerived ? snapshots.map { $0.derived?.P_auxiliary ?? 0.0 } : zeroScalar,
            pOhmicE: hasDerived ? snapshots.map { $0.derived?.P_ohmic ?? 0.0 } : zeroScalar,
            pAlphaTotal: hasDerived ? snapshots.map { $0.derived?.P_alpha ?? 0.0 } : zeroScalar,
            pBremsstrahlung: zeroScalar,
            pRadiation: zeroScalar
        )
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

enum ExportFormat: String {
    case png
    case pdf
    case svg
    case csv
}
```

---

## 7. View Implementation

(Content mostly unchanged from v1.0, with error handling improvements)

### 7.1 ContentView (Root)

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [Workspace]

    @State private var viewModel: AppViewModel
    @State private var plotViewModel = PlotViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        // Initialize with first workspace or create default
        let workspace = Workspace(name: "Default")
        _viewModel = State(initialValue: AppViewModel(workspace: workspace))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left: Sidebar
            SidebarView(
                workspace: viewModel.workspace,
                selectedSimulation: $viewModel.selectedSimulation
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)

        } content: {
            // Center: Main Canvas
            MainCanvasView(
                simulation: viewModel.selectedSimulation,
                plotViewModel: plotViewModel,
                isRunning: viewModel.isSimulationRunning
            )
            .toolbar {
                ToolbarView(
                    viewModel: viewModel,
                    plotViewModel: plotViewModel
                )
            }

        } detail: {
            // Right: Inspector
            if viewModel.showInspector {
                InspectorView(
                    simulation: viewModel.selectedSimulation,
                    plotViewModel: plotViewModel
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 500)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            if workspaces.isEmpty {
                createDefaultWorkspace()
            } else {
                viewModel.workspace = workspaces[0]
            }
        }
    }

    private func createDefaultWorkspace() {
        let workspace = Workspace(name: "Default")
        modelContext.insert(workspace)
        viewModel.workspace = workspace
    }
}
```

---

## 8-10. Remaining Sections

Remaining sections (Workflows, Project Structure, Implementation Roadmap, Additional Requirements) remain largely unchanged from v1.0, with the following key additions:

### Key Updates:

**Section 9: Implementation Roadmap**

**Phase 1** extended to **3-4 days** (was 1-2):
- ✅ Add SimulationDataStore implementation
- ✅ Add error handling framework
- ✅ Add OSLog integration

**Phase 2** extended to **3-4 days** (was 2-3):
- ✅ Add actor isolation handling
- ✅ Add task cancellation support
- ✅ Add time-based throttling

**Section 11: Additional Requirements**

Added:
- ✅ **SimulationDataStore** complete implementation
- ✅ **OSLog integration** guidelines
- ✅ **Error handling** best practices
- ✅ **Task cancellation** support in swift-gotenx

---

## Appendix A: Migration from v1.0

### Breaking Changes

1. **Data Storage**: Snapshots now stored in files, not SwiftData
2. **Simulation Model**: Removed `snapshots: [SimulationSnapshot]`, added `snapshotMetadata` and `dataFileURL`
3. **Error Handling**: Removed `try!`, added proper error propagation

### Migration Steps

1. Export existing simulations (if any)
2. Update SwiftData schema
3. Re-import simulations using new storage format

---

## Appendix B: Performance Benchmarks

### Expected Performance (100 cells, 2000 snapshots)

| Operation | Time | Memory |
|-----------|------|--------|
| Save snapshot to file | <1ms | ~2KB |
| Load all snapshots | ~50ms | ~3MB |
| SwiftData query (metadata) | <5ms | ~10KB |
| Plot data conversion | ~20ms | ~1MB |
| Animation frame (60fps) | <16ms | ~0.5MB |

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-10-22 | Initial specification |
| 1.1 | 2024-10-22 | Production-ready improvements: hybrid storage, actor isolation, error handling |

---

**End of Specification v1.1**
