# Simulation Integration Design

**Version**: 3.0
**Date**: 2025-10-23
**Status**: READY FOR IMPLEMENTATION - FULL FEATURE SUPPORT

---

## Overview

現在のGotenxアプリは**プレースホルダー実装**のため、シミュレーションが即座に終了します。
swift-gotenxの`SimulationRunner`と`SimulationOrchestrator`を統合して、実際の物理計算を実行できるようにします。

**🎉 swift-gotenx Phase 1 完了**: 2025-10-23にアプリ統合機能が実装され、以下が利用可能になりました：
- ✅ **タスクキャンセル** - Task.cancel()で即座に停止
- ✅ **Pause/Resume** - runner.pause() / runner.resume()
- ✅ **ライブプロット** - ProgressInfoにprofiles/derivedを追加
- ✅ **改善されたエラーハンドリング** - SimulationError拡張
- ⚠️ **Breaking Change** - SourceModelFactory.create() が throws に変更

---

## swift-gotenx Phase 1 Features

### 1. タスクキャンセル (Full Support)

```swift
let task = Task {
    try await runner.run()
}

// Stop button
task.cancel()  // ← 即座に停止（SimulationOrchestratorがTask.checkCancellation()をチェック）
```

### 2. Pause/Resume

```swift
// Pause button
await runner.pause()

// Resume button
await runner.resume()

// Check state
let paused = await runner.isPaused()
```

### 3. ライブプロット

```swift
// SamplingConfig.realTimePlotting preset使用
let orchestrator = await SimulationOrchestrator(
    staticParams: params,
    initialProfiles: profiles,
    transport: transport,
    samplingConfig: .realTimePlotting  // ← リアルタイムプロット有効化
)

// ProgressInfoにプロファイルが含まれる
let result = try await runner.run { fraction, progressInfo in
    if let profiles = progressInfo.profiles {
        // Ti, Te, ne, psi
        updatePlot(profiles)
    }
    if let derived = progressInfo.derived {
        // τE, Q, βN, etc.
        updateMetrics(derived)
    }
}
```

**ProgressInfo構造**:
```swift
public struct ProgressInfo: Sendable {
    public let currentTime: Float
    public let totalSteps: Int
    public let lastDt: Float
    public let converged: Bool
    public let profiles: SerializableProfiles?  // ← NEW (Optional)
    public let derived: DerivedQuantities?      // ← NEW (Optional)
}
```

### 4. 改善されたエラーハンドリング

```swift
do {
    let result = try await runner.run()
} catch let error as SimulationError {
    errorMessage = error.localizedDescription
    errorRecovery = error.recoverySuggestion  // ← ユーザー向けの復旧提案
} catch let error as SolverError {
    // ソルバーエラー
}
```

**新しいエラー**:
- `modelInitializationFailed(modelName:reason:)`
- `numericInstability(time:variable:value:)`
- `convergenceFailure(iterations:residual:)`
- `invalidBoundaryConditions(String)`
- `meshTooCoarse(nCells:minimum:)`
- `timeStepTooSmall(dt:minimum:)`

### 5. Breaking Change: SourceModelFactory

```swift
// ❌ v2.0
let sources = SourceModelFactory.create(config: sourcesConfig)

// ✅ v3.0
let sources = try SourceModelFactory.create(config: sourcesConfig)
```

---

## Current Placeholder Implementations

### 1. AppViewModel.swift (Line 125-158)

**問題**: 実際のシミュレーション計算が実装されていない

```swift
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
```

**影響**:
- シミュレーションが即座に終了
- 時間データが1ポイントのみ（t=0のみ）
- 進捗表示が更新されない
- 物理計算が行われない

### 2. AppViewModel.swift (Line 184-201)

**問題**: Pause/Resume機能がプレースホルダー

```swift
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
```

**影響**:
- ステータスのみ変更され、実際のシミュレーションは止まらない
- Resumeも同様に機能しない

### 3. AppViewModel.swift (Line 318)

**問題**: 初期プロファイルがプレースホルダー

```swift
// Initial poloidal flux (placeholder)
let psi = Array(repeating: Float(0.0), count: nCells)
```

**影響**:
- 物理的に正しい初期条件が設定されていない
- MHD平衡が考慮されていない

---

## Architecture Design

### Component Diagram (Simplified)

```
┌─────────────────────────────────────────────────────────────┐
│                  AppViewModel (@MainActor)                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              simulationTask: Task?                   │   │
│  │  - Direct Task-based concurrency                     │   │
│  │  - Progress callbacks → MainActor                    │   │
│  │  - Task cancellation support                         │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           SimulationRunner (swift-gotenx)            │   │
│  │  - Configuration → RuntimeParams conversion          │   │
│  │  - Model initialization (transport/source/mhd)       │   │
│  │  - Orchestrator lifecycle management                 │   │
│  │  - Built-in progress monitoring (100ms throttle)     │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         SimulationOrchestrator (swift-gotenx)        │   │
│  │  - Time stepping loop                                │   │
│  │  - Physics model integration                         │   │
│  │  - Solver execution                                  │   │
│  │  - Time series capture                               │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Key Design Decision**: Remove intermediate SimulationExecutor actor. Use direct Task integration in AppViewModel for simplicity.

### Data Flow (Simplified)

```
User Action (Run Button)
    │
    ▼
AppViewModel.runSimulation()
    │
    ├─> Decode SimulationConfiguration
    │
    ├─> Create Task (background execution)
    │   │
    │   ├─> Initialize SimulationRunner
    │   │   ├─> TransportModel (from config)
    │   │   ├─> SourceModels (from config)
    │   │   ├─> MHDModels (from config)
    │   │   └─> Generate Initial Profiles (physics-based)
    │   │
    │   ├─> SimulationRunner.run(progressCallback:)
    │   │   │
    │   │   └─> SimulationOrchestrator.run()
    │   │       ├─> Time stepping loop
    │   │       ├─> performStep() × N
    │   │       ├─> Progress updates → Task { @MainActor }
    │   │       └─> Time series capture
    │   │
    │   └─> Return SimulationResult
    │
    ├─> SaveResults (SimulationDataStore)
    │
    └─> Update UI (@MainActor)
```

---

## Implementation Plan

### Phase 1: AppViewModel Direct Integration

**File**: `Gotenx/ViewModels/AppViewModel.swift`

**1. Add SimulationRunner Reference**:

```swift
// Store runner reference for pause/resume
private var currentRunner: SimulationRunner?
```

**2. Replace Placeholder Execution**:

```swift
func runSimulation(_ simulation: Simulation) {
    // ... existing validation ...

    logViewModel.log("Starting simulation: \(simulation.name)", level: .info, category: "Simulation")

    simulationTask = Task {
        defer {
            Task { @MainActor in
                isSimulationRunning = false
                currentRunner = nil
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

            logViewModel.log("Simulation initialized (duration: \(config.time.end)s)", level: .info, category: "Simulation")

            // ✅ NEW: Create SimulationRunner directly
            let runner = SimulationRunner(config: config)
            await MainActor.run {
                currentRunner = runner  // Store for pause/resume
            }

            // ✅ NEW: Initialize models (with all required parameters)
            let transportModel = try TransportModelFactory.create(
                config: config.runtime.dynamic.transport
            )
            // ⚠️ Breaking Change: Now throws
            let sourceModels = try SourceModelFactory.create(
                config: config.runtime.dynamic.sources
            )
            let mhdModels = MHDModelFactory.createAllModels(
                config: config.runtime.dynamic.mhd
            )

            try await runner.initialize(
                transportModel: transportModel,
                sourceModels: sourceModels,
                mhdModels: mhdModels
            )

            logViewModel.log("Models initialized", level: .debug, category: "Simulation")

            // ✅ NEW: Run actual simulation with progress callback
            let result = try await runner.run { fraction, progressInfo in
                // Progress callback (already runs on background, hop to MainActor for UI)
                Task { @MainActor in
                    self.simulationProgress = Double(fraction)
                    self.currentSimulationTime = progressInfo.currentTime

                    // ✅ NEW: Update live plots
                    if let profiles = progressInfo.profiles {
                        self.plotViewModel.updateLiveProfiles(profiles)
                    }
                    if let derived = progressInfo.derived {
                        self.plotViewModel.updateDerivedQuantities(derived)
                    }

                    // Log every 10%
                    if fraction.truncatingRemainder(dividingBy: 0.1) < 0.01 {
                        self.logViewModel.log(
                            "Progress: \(Int(fraction * 100))% | t = \(progressInfo.currentTime)s | dt = \(progressInfo.lastDt)s",
                            level: .debug,
                            category: "Simulation"
                        )
                    }
                }
            }

            // Get data store
            logViewModel.log("Saving simulation results...", level: .info, category: "Storage")
            let store = try getDataStore()
            try await saveResults(simulation: simulation, result: result, store: store)

            await MainActor.run {
                logViewModel.log("✓ Simulation completed successfully", level: .info, category: "Simulation")
            }

        } catch is CancellationError {
            await MainActor.run {
                logViewModel.log("⚠ Simulation cancelled by user", level: .warning, category: "Simulation")
                if let simulation = selectedSimulation {
                    simulation.status = .cancelled
                }
            }
        } catch let error as SimulationError {
            await MainActor.run {
                logViewModel.log("✗ Simulation failed: \(error.localizedDescription)", level: .error, category: "Simulation")

                // Show recovery suggestion if available
                if let recovery = error.recoverySuggestion {
                    logViewModel.log("💡 Suggestion: \(recovery)", level: .info, category: "Simulation")
                }

                errorMessage = error.localizedDescription
                if let simulation = selectedSimulation {
                    simulation.status = .failed(error: error.localizedDescription)
                }
            }
        } catch {
            await MainActor.run {
                logViewModel.log("✗ Unexpected error: \(error.localizedDescription)", level: .error, category: "Simulation")
                errorMessage = error.localizedDescription
                if let simulation = selectedSimulation {
                    simulation.status = .failed(error: error.localizedDescription)
                }
            }
        }
    }
}
```

**3. Implement Pause/Resume** (✅ Now Fully Functional):

```swift
func pauseSimulation() {
    guard let runner = currentRunner, isSimulationRunning, !isPaused else { return }

    Task {
        await runner.pause()
        await MainActor.run {
            isPaused = true
            if let simulation = selectedSimulation {
                simulation.status = .paused(at: simulationProgress)
            }
            logViewModel.log("⏸ Simulation paused", level: .info, category: "Simulation")
        }
    }
}

func resumeSimulation() {
    guard let runner = currentRunner, isSimulationRunning, isPaused else { return }

    Task {
        await runner.resume()
        await MainActor.run {
            isPaused = false
            if let simulation = selectedSimulation {
                simulation.status = .running(progress: simulationProgress)
            }
            logViewModel.log("▶ Simulation resumed", level: .info, category: "Simulation")
        }
    }
}
```

**4. Update Cancellation** (✅ Full Support):

```swift
func stopSimulation() {
    guard let task = simulationTask else { return }

    logViewModel.log("⏹ Stopping simulation...", level: .warning, category: "Simulation")

    task.cancel()  // ✅ Full cancellation (orchestrator stops immediately)
    isPaused = false

    if let simulation = selectedSimulation {
        simulation.status = .cancelled
    }
}
```

### Phase 1b: PlotViewModel Live Plotting Support

**File**: `Gotenx/ViewModels/PlotViewModel.swift`

**Add Methods for Live Updates**:

```swift
/// Update plots with live profiles during simulation
func updateLiveProfiles(_ profiles: SerializableProfiles) {
    // Update existing plot data with new profiles
    // This method should update the current time point without saving to persistent storage

    guard let plotData = self.plotData else { return }

    // Replace last time point with live data
    // (Implementation depends on PlotData structure)

    // Note: Don't save to SwiftData here - only update in-memory plot
}

/// Update derived quantities during simulation
func updateDerivedQuantities(_ derived: DerivedQuantities) {
    // Update energy confinement time, power balance, etc.
    // Display in inspector or metrics panel
}
```

**Note**: Live plotting is optional. If not implemented, ProgressInfo.profiles will simply be ignored and plots will update after simulation completes.

### Phase 2: Testing & Refinement

**Initial Profiles**: Automatically handled by `SimulationRunner.initialize()`. Remove manual `createDefaultProfiles()` method from AppViewModel.

**Testing Focus**:

1. **Unit Tests**
   - Configuration decoding
   - Model factory integration
   - Error handling
   - Task cancellation

2. **Integration Tests**
   - Short simulation (0.1s duration)
   - Verify time series data (multiple time points)
   - Check progress updates (logs every 10%)
   - Test all transport models (Constant, Bohm-GyroBohm, QLKNN)

3. **Performance Tests**
   - Memory usage during simulation
   - Progress callback overhead (already throttled by SimulationRunner to 100ms)
   - UI responsiveness

---

## Dependencies

### Required swift-gotenx Components

**✅ All Features Available (Phase 1 Complete)**:
- ✅ `SimulationRunner` - Core simulation lifecycle management
- ✅ `SimulationOrchestrator` - Time stepping and physics integration
- ✅ `TransportModelFactory.create()` - Transport model instantiation
- ✅ `SourceModelFactory.create()` - **throws** (Breaking Change in v3.0)
- ✅ `MHDModelFactory.createAllModels()` - MHD model instantiation
- ✅ `generateInitialProfiles()` - Physics-based initial conditions (called internally)
- ✅ **Progress monitoring** - Built-in 100ms throttling with live profiles
- ✅ **Pause/Resume** - `runner.pause()` / `runner.resume()` / `runner.isPaused()`
- ✅ **Full Cancellation** - Task.cancel() stops orchestrator immediately
- ✅ **Live Plotting** - ProgressInfo.profiles / ProgressInfo.derived (with SamplingConfig.realTimePlotting)
- ✅ **Error Handling** - SimulationError with localizedDescription and recoverySuggestion

### Future Enhancements (Phase 2+)

- [ ] **Checkpoint/Restart** - Save/load intermediate states for long simulations
- [ ] **Multi-simulation parallelization** - Run multiple configs concurrently
- [ ] **GPU memory optimization** - Streaming for very large meshes
- [ ] **Advanced diagnostics** - Pedestal detection, mode analysis

---

## Risk Analysis

### High Risk

1. **Memory Usage**
   - **Risk**: Large time series causing OOM, especially with live plotting enabled
   - **Mitigation**: Use SamplingConfig.realTimePlotting (balanced memory vs. frequency), monitor during testing

### Medium Risk

1. **Live Plotting Overhead**
   - **Risk**: Frequent profile serialization and UI updates slow down simulation
   - **Mitigation**: SimulationRunner throttles to 100ms, profile serialization is ~100μs, total overhead ~0.1%

2. **Model Factory Failures**
   - **Risk**: Factory methods throw errors with invalid configurations
   - **Mitigation**: Comprehensive error handling with SimulationError catching, show recovery suggestions to user

3. **Breaking Change Migration**
   - **Risk**: SourceModelFactory.create() now throws, existing code will fail to compile
   - **Mitigation**: Add `try` keyword (simple fix), comprehensive testing after migration

### Low Risk

1. **Configuration Conversion**
   - **Risk**: SimulationConfiguration → RuntimeParams conversion fails
   - **Mitigation**: Validation in SimulationRunner.initialize(), catch and log errors with detailed messages

2. **Concurrency Issues**
   - **Risk**: Race conditions between progress callbacks and UI updates
   - **Mitigation**: All UI updates wrapped in `Task { @MainActor }`, structured concurrency patterns

### ✅ Resolved Risks (v2.0 → v3.0)

- ~~Incomplete Cancellation~~ - **RESOLVED**: Task.cancel() now stops orchestrator immediately
- ~~Pause/Resume Not Available~~ - **RESOLVED**: runner.pause() / runner.resume() fully implemented
- ~~Progress Callback Overhead~~ - **RESOLVED**: Built-in throttling sufficient

---

## Implementation Checklist

### Phase 1: AppViewModel Direct Integration (4-5 hours)
- [ ] **Breaking Change**: Add `try` to SourceModelFactory.create() call
- [ ] Add `currentRunner: SimulationRunner?` property for pause/resume
- [ ] Replace placeholder execution in `runSimulation()` (AppViewModel.swift:125-158)
  - [ ] Create SimulationRunner directly (no executor wrapper)
  - [ ] Store runner reference for pause/resume
  - [ ] Initialize models with correct parameters:
    - [ ] TransportModelFactory.create()
    - [ ] SourceModelFactory.create() (⚠️ now throws)
    - [ ] MHDModelFactory.createAllModels()
  - [ ] Implement progress callback with:
    - [ ] MainActor hopping for UI updates
    - [ ] Live profile updates (optional)
    - [ ] Live derived quantities (optional)
    - [ ] 10% logging
  - [ ] Add comprehensive error handling:
    - [ ] CancellationError catch
    - [ ] SimulationError catch (with recoverySuggestion)
    - [ ] General error catch
- [ ] **✅ Implement Pause/Resume** (now fully functional):
  - [ ] `pauseSimulation()` with runner.pause()
  - [ ] `resumeSimulation()` with runner.resume()
  - [ ] Update UI state and logs
- [ ] **✅ Update `stopSimulation()`** for full cancellation
- [ ] Remove `createDefaultProfiles()` method (AppViewModel.swift:318)

### Phase 1b: PlotViewModel Live Plotting (Optional, 1-2 hours)
- [ ] Add `updateLiveProfiles(_ profiles:)` method
- [ ] Add `updateDerivedQuantities(_ derived:)` method
- [ ] Integrate with existing plot display logic
- [ ] Note: Can be deferred to Phase 2+

### Phase 2: Testing & Refinement (2-3 hours)
- [ ] **Unit Tests**:
  - [ ] Configuration decoding
  - [ ] Model factory integration (with throws)
  - [ ] Error handling paths (SimulationError, SolverError)
  - [ ] Task cancellation (verify immediate stop)
  - [ ] Pause/Resume behavior
- [ ] **Integration Tests**:
  - [ ] Short simulation (0.1s) with all transport models
  - [ ] Verify time series has multiple points (not just t=0)
  - [ ] Check progress updates in console (every 10%)
  - [ ] Test full cancellation (orchestrator stops immediately)
  - [ ] Test pause/resume cycle
  - [ ] Verify live plotting (if implemented)
- [ ] **Performance**:
  - [ ] Memory profiling with SamplingConfig.realTimePlotting
  - [ ] UI responsiveness check (especially during live updates)
  - [ ] Verify 100ms throttling overhead (~0.1%)

**Total Estimated Time**: 6-8 hours (with live plotting) or 5-7 hours (without live plotting)

---

## Success Criteria

1. ✅ Simulation runs for configured duration (not instant completion)
2. ✅ Progress updates show real-time advancement in console
3. ✅ Time series contains multiple time points (not just t=0)
4. ✅ Console logs show simulation steps (every 10%)
5. ✅ **Stop button cancels simulation immediately** (full cancellation support)
6. ✅ **Pause/Resume buttons work correctly** (pause at any time, resume from same state)
7. ✅ Results are physically consistent (proper initial profiles)
8. ✅ All transport models work correctly (Constant, Bohm-GyroBohm, QLKNN)
9. ✅ No SimulationExecutor complexity (direct integration)
10. ✅ Proper error handling with recovery suggestions
11. 🔄 **Live plotting updates during simulation** (optional, Phase 1b)

---

## Changes from v2.0

**🎉 swift-gotenx Phase 1 Complete**:
- ✅ **Pause/Resume** - Moved from Future Enhancements to fully implemented
- ✅ **Full Cancellation** - Task.cancel() now stops orchestrator immediately
- ✅ **Live Plotting** - ProgressInfo includes profiles and derived quantities
- ✅ **Enhanced Error Handling** - SimulationError with localizedDescription and recoverySuggestion
- ⚠️ **Breaking Change** - SourceModelFactory.create() now throws

**Implementation Updates**:
- Added `currentRunner` property for pause/resume
- Updated progress callback to handle live profiles
- Enhanced error handling with SimulationError catch
- Updated time estimate to 6-8 hours (with live plotting) or 5-7 hours (without)

**Risk Mitigation**:
- Resolved: Incomplete cancellation
- Resolved: Pause/Resume unavailable
- New: Live plotting overhead (0.1%, negligible)
- New: Breaking change migration (simple: add `try`)

---

## Changes from v1.0

**v1.0 → v2.0** (Architectural Simplification):
- ❌ Removed SimulationExecutor actor (unnecessary abstraction)
- ✅ Direct Task-based integration in AppViewModel
- ✅ Fixed SimulationRunner API (added mhdModels parameter)
- ✅ Fixed ProgressCallback signature (pass ProgressInfo directly)
- 🚫 Pause/Resume moved to Future Enhancements
- ⚠️ Documented cancellation limitations
- ✅ Reduced time estimate to 5-7 hours (from 7-10 hours)

**v2.0 → v3.0** (Full Feature Support):
- ✅ Pause/Resume now fully implemented
- ✅ Full cancellation support
- ✅ Live plotting with SamplingConfig.realTimePlotting
- ✅ Enhanced error handling
- ⚠️ SourceModelFactory.create() now throws

---

**Document Version**: 3.0
**Last Updated**: 2025-10-23
**Status**: Ready for Implementation - Full Feature Support
