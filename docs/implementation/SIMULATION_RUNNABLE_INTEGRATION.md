# SimulationRunnable Protocol 統合ドキュメント

**日付**: 2025-10-23
**ステータス**: Phase 1 完了（Production Ready）
**次のステップ**: Phase 2（テスト用依存性注入）

---

## 概要

`SimulationRunnable` protocol は、swift-gotenx と Gotenx アプリの間のシミュレーション実行契約を定義します。この protocol により、テスタビリティ、拡張性、保守性が向上します。

---

## Phase 1: Production Implementation（完了✅）

### swift-gotenx 側の実装

#### 1. SimulationRunnable Protocol

**場所**: `swift-gotenx/Sources/GotenxCore/Protocols/SimulationRunnable.swift`

**設計思想**:
- **Actor Protocol**: すべての実装は actor であり、thread-safe
- **依存性注入**: 具体実装から分離し、テスト可能にする
- **拡張性**: 複数の実装（ローカル、リモート、キャッシュ）をサポート

**Protocol 定義**:

```swift
public protocol SimulationRunnable: Actor {
    /// Initialize simulation with physics models
    func initialize(
        transportModel: any TransportModel,
        sourceModels: [any SourceModel],
        mhdModels: [any MHDModel]?
    ) async throws

    /// Run simulation with progress callback
    func run(
        progressCallback: (@Sendable (Float, ProgressInfo) -> Void)?
    ) async throws -> SimulationResult

    /// Pause the simulation
    func pause() async

    /// Resume the simulation
    func resume() async

    /// Check if simulation is paused
    func isPaused() async -> Bool
}
```

**Default Implementations**:

```swift
extension SimulationRunnable {
    // Convenience: initialize without MHD models
    public func initialize(
        transportModel: any TransportModel,
        sourceModels: [any SourceModel]
    ) async throws {
        try await initialize(
            transportModel: transportModel,
            sourceModels: sourceModels,
            mhdModels: nil
        )
    }

    // Convenience: run without progress callback
    public func run() async throws -> SimulationResult {
        try await run(progressCallback: nil)
    }
}
```

**特徴**:
- ✅ Actor protocol で thread-safe を保証
- ✅ `@Sendable` closure で actor 境界を安全に超える
- ✅ Default implementations で convenience methods 提供
- ✅ 完全なドキュメント（使用例、説明、App Integration ノート）

#### 2. SimulationRunner の実装

**場所**: `swift-gotenx/Sources/GotenxCore/Orchestration/SimulationRunner.swift`

**実装**:

```swift
public actor SimulationRunner: SimulationRunnable {
    private let config: SimulationConfiguration
    private var orchestrator: SimulationOrchestrator?

    public init(config: SimulationConfiguration) {
        self.config = config
    }

    // Protocol conformance (すべてのメソッドを実装)
    public func initialize(...) async throws { /* ... */ }
    public func run(...) async throws -> SimulationResult { /* ... */ }
    public func pause() async { await orchestrator?.pause() }
    public func resume() async { await orchestrator?.resume() }
    public func isPaused() async -> Bool { await orchestrator?.getIsPaused() ?? false }

    // Private methods (protocol 外)
    private func generateInitialProfiles(...) throws -> CoreProfiles { /* ... */ }
    private func adaptTimestep(...) -> Float { /* ... */ }
}
```

**重要な実装詳細**:

1. **initialize() の責務**:
   - Static parameters の作成
   - 初期プロファイルの生成（物理ベース）
   - MHD models の作成（未指定の場合）
   - SimulationOrchestrator の初期化

2. **run() の実装**:
   - Progress monitoring task の起動（バックグラウンド）
   - 100ms ごとに progress callback を呼び出し
   - Orchestrator の実行
   - Task cancellation のサポート

3. **Pause/Resume の実装**:
   - Orchestrator にデリゲート
   - CheckedContinuation による効率的な待機
   - Actor-isolated で thread-safe

#### 3. SimulationError の拡充

**場所**: `swift-gotenx/Sources/GotenxCore/Orchestration/SimulationRunner.swift` (Line 301-380)

**実装**:

```swift
public enum SimulationError: Error, LocalizedError {
    case notInitialized
    case invalidConfiguration(String)
    case executionFailed(String)
    case modelInitializationFailed(modelName: String, reason: String)
    case numericInstability(time: Float, variable: String, value: Float)
    case convergenceFailure(iterations: Int, residual: Float)
    case invalidBoundaryConditions(String)
    case meshTooCoarse(cellCount: Int, minimum: Int)
    case timeStepTooSmall(dt: Float, minimum: Float)

    // LocalizedError protocol
    public var errorDescription: String? { /* ... */ }
    public var recoverySuggestion: String? { /* ... */ }
}
```

**特徴**:
- ✅ `LocalizedError` 準拠でユーザーフレンドリー
- ✅ 具体的なエラーケース（9種類）
- ✅ `recoverySuggestion` で解決策を提示
- ✅ ドキュメントで SimulationError と SolverError の使い分けを説明

---

### Gotenx アプリ側の実装

#### AppViewModel の現状

**場所**: `Gotenx/ViewModels/AppViewModel.swift`

**現在の実装（Phase 1）**:

```swift
@MainActor
@Observable
final class AppViewModel {
    // Simulation execution
    private var currentRunner: SimulationRunner?  // ⚠️ 具体型（まだ protocol 型ではない）

    init(workspace: Workspace) {
        self.workspace = workspace
        // ⚠️ runnerFactory はまだ実装されていない
    }

    func runSimulation(_ simulation: Simulation) {
        simulationTask = Task {
            do {
                let config = try JSONDecoder().decode(SimulationConfiguration.self, from: configData)

                // ✅ SimulationRunner を直接作成
                let runner = SimulationRunner(config: config)
                await MainActor.run {
                    self.currentRunner = runner
                }

                // ✅ Models の作成
                let transportModel = try TransportModelFactory.create(
                    config: config.runtime.dynamic.transport
                )
                let sourceModel = try SourceModelFactory.create(
                    config: config.runtime.dynamic.sources
                )
                let mhdModels = MHDModelFactory.createAllModels(
                    config: config.runtime.dynamic.mhd
                )

                // ✅ Initialize
                try await runner.initialize(
                    transportModel: transportModel,
                    sourceModels: [sourceModel],
                    mhdModels: mhdModels
                )

                // ✅ Run with progress callback
                let result = try await runner.run { fraction, progressInfo in
                    Task { @MainActor in
                        self.simulationProgress = Double(fraction)
                        self.currentSimulationTime = progressInfo.currentTime

                        // ✅ Live plotting (throttled)
                        let now = Date()
                        if now.timeIntervalSince(self.lastUpdateTime) >= self.minUpdateInterval {
                            if let profiles = progressInfo.profiles {
                                self.liveProfiles = profiles
                            }
                            if let derived = progressInfo.derived {
                                self.liveDerived = derived
                            }
                            self.lastUpdateTime = now
                        }
                    }
                }

                // ✅ Save results
                try await saveResults(simulation: simulation, result: result, store: store)

            } catch let error as SimulationError {
                // ✅ LocalizedError のエラーハンドリング
                await MainActor.run {
                    simulation.status = .failed(error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    logViewModel.log(error.localizedDescription, level: .error, category: "Simulation")

                    // ✅ Recovery suggestion の表示
                    if let recovery = error.recoverySuggestion {
                        logViewModel.log("💡 Suggestion: \(recovery)", level: .info, category: "Simulation")
                    }
                }
            }
        }
    }

    // ✅ Pause/Resume/Stop の実装
    func pauseSimulation() {
        guard let runner = currentRunner else { return }
        pauseResumeTask = Task {
            await runner.pause()
            await MainActor.run { isPaused = true }
        }
    }

    func resumeSimulation() {
        guard let runner = currentRunner else { return }
        pauseResumeTask = Task {
            await runner.resume()
            await MainActor.run { isPaused = false }
        }
    }

    func stopSimulation() {
        simulationTask?.cancel()  // ✅ Task cancellation
        pauseResumeTask?.cancel()
        isPaused = false
    }
}
```

**実装されている機能**:
- ✅ SimulationRunner の作成と初期化
- ✅ Progress callback による UI 更新
- ✅ Live plotting（throttled）
- ✅ Pause/Resume/Stop
- ✅ SimulationError のエラーハンドリング
- ✅ Recovery suggestion の表示
- ✅ Task cancellation のサポート

**まだ実装されていない機能**:
- ⏳ Protocol 型 `(any SimulationRunnable)?` への変更
- ⏳ runnerFactory による依存性注入
- ⏳ MockSimulationRunner
- ⏳ テストコード

---

## Phase 1 の評価

### ✅ 完了した項目

#### swift-gotenx 側
1. ✅ SimulationRunnable protocol の定義
2. ✅ SimulationRunner の protocol 適合
3. ✅ Default implementations
4. ✅ 完全なドキュメント
5. ✅ SimulationError の LocalizedError 対応
6. ✅ Task cancellation のサポート
7. ✅ Pause/Resume のサポート
8. ✅ Progress callback with live data

#### Gotenx アプリ側
1. ✅ SimulationRunner の使用
2. ✅ Initialize/Run の呼び出し
3. ✅ Progress callback の実装
4. ✅ Live plotting（throttled）
5. ✅ Pause/Resume/Stop の実装
6. ✅ エラーハンドリング
7. ✅ Recovery suggestion の表示
8. ✅ Task cleanup と state management

### 🎯 Production Ready

**Phase 1 の実装は production ready です**:
- ✅ すべての機能が動作
- ✅ エラーハンドリングが適切
- ✅ Actor isolation が正しい
- ✅ UI 更新が MainActor で実行
- ✅ ドキュメントが充実

---

## Phase 2: テスト用依存性注入（次のステップ）

### 目的

- AppViewModel を単体テスト可能にする
- 実際のシミュレーション実行なしでテスト
- CI/CD で高速な自動テスト

### 実装計画

#### 1. AppViewModel の依存性注入

**変更点**:

```swift
@MainActor
@Observable
final class AppViewModel {
    // ✅ Protocol 型に変更
    private var currentRunner: (any SimulationRunnable)?

    // ✅ Runner factory を追加
    private let runnerFactory: (SimulationConfiguration) -> any SimulationRunnable

    // ✅ Init with factory
    init(
        workspace: Workspace,
        runnerFactory: @escaping (SimulationConfiguration) -> any SimulationRunnable = { config in
            SimulationRunner(config: config)  // Default: production
        }
    ) {
        self.workspace = workspace
        self.runnerFactory = runnerFactory
    }

    func runSimulation(_ simulation: Simulation) {
        simulationTask = Task {
            // ...
            let config = try JSONDecoder().decode(SimulationConfiguration.self, from: configData)

            // ✅ Use factory instead of direct instantiation
            let runner = runnerFactory(config)
            await MainActor.run {
                self.currentRunner = runner
            }

            // Rest of the code unchanged
            // ...
        }
    }
}
```

**変更量**: 最小限（5行程度）

#### 2. MockSimulationRunner の実装

**場所**: `GotenxTests/Mocks/MockSimulationRunner.swift`

**実装**:

```swift
actor MockSimulationRunner: SimulationRunnable {
    // Test control
    var shouldFail: Bool = false
    var shouldCancel: Bool = false
    var simulationDuration: TimeInterval = 0.1  // Fast for tests
    var progressUpdatesCount: Int = 10

    // State tracking
    private(set) var isInitialized: Bool = false
    private(set) var isRunning: Bool = false
    private(set) var _isPaused: Bool = false
    private(set) var initializeCallCount: Int = 0
    private(set) var runCallCount: Int = 0

    // Recorded values
    private(set) var lastTransportModel: (any TransportModel)?
    private(set) var lastSourceModels: [any SourceModel]?
    private(set) var lastMHDModels: [any MHDModel]?

    func initialize(
        transportModel: any TransportModel,
        sourceModels: [any SourceModel],
        mhdModels: [any MHDModel]?
    ) async throws {
        initializeCallCount += 1
        lastTransportModel = transportModel
        lastSourceModels = sourceModels
        lastMHDModels = mhdModels

        if shouldFail {
            throw SimulationError.modelInitializationFailed(
                modelName: "Mock",
                reason: "Test failure"
            )
        }

        isInitialized = true
    }

    func run(
        progressCallback: (@Sendable (Float, ProgressInfo) -> Void)?
    ) async throws -> SimulationResult {
        runCallCount += 1
        isRunning = true
        defer { isRunning = false }

        guard isInitialized else {
            throw SimulationError.notInitialized
        }

        if shouldFail {
            throw SimulationError.executionFailed("Test failure")
        }

        // Simulate progress updates
        let stepDuration = simulationDuration / Double(progressUpdatesCount)
        for i in 0..<progressUpdatesCount {
            // Check cancellation
            try Task.checkCancellation()

            // Wait for pause
            while _isPaused {
                try await Task.sleep(for: .milliseconds(10))
            }

            let fraction = Float(i) / Float(progressUpdatesCount)
            let progressInfo = ProgressInfo(
                currentTime: fraction * 2.0,  // 2s simulation
                totalSteps: i,
                lastDt: 1e-4,
                converged: true,
                profiles: nil,
                derived: nil
            )

            progressCallback?(fraction, progressInfo)

            try await Task.sleep(for: .seconds(stepDuration))
        }

        // Return mock result
        return SimulationResult(
            finalProfiles: SerializableProfiles(
                ionTemperature: [Float](repeating: 1000.0, count: 100),
                electronTemperature: [Float](repeating: 1000.0, count: 100),
                electronDensity: [Float](repeating: 1e20, count: 100),
                poloidalFlux: [Float](repeating: 0.0, count: 100)
            ),
            statistics: SimulationStatistics(
                totalIterations: 100,
                totalSteps: progressUpdatesCount,
                converged: true,
                maxResidualNorm: 1e-8,
                wallTime: Float(simulationDuration)
            ),
            timeSeries: nil
        )
    }

    func pause() async {
        _isPaused = true
    }

    func resume() async {
        _isPaused = false
    }

    func isPaused() async -> Bool {
        _isPaused
    }
}
```

**特徴**:
- ✅ すべての protocol メソッドを実装
- ✅ テスト制御（shouldFail, simulationDuration など）
- ✅ 状態追跡（callCount, 記録された値）
- ✅ Task cancellation と pause/resume のサポート
- ✅ 高速実行（0.1s）

#### 3. テストコードの実装

**場所**: `GotenxTests/ViewModels/AppViewModelTests.swift`

**テストケース**:

```swift
@MainActor
final class AppViewModelTests: XCTestCase {
    func testSimulationSuccess() async throws {
        // Setup
        let workspace = Workspace(name: "Test")
        let mockRunner = MockSimulationRunner()

        let viewModel = AppViewModel(workspace: workspace) { config in
            mockRunner  // Inject mock
        }

        let simulation = Simulation(
            name: "Test Sim",
            configurationData: createTestConfig()
        )
        workspace.simulations.append(simulation)
        viewModel.selectedSimulation = simulation

        // Execute
        viewModel.runSimulation(simulation)

        // Wait for completion
        try await Task.sleep(for: .milliseconds(500))

        // Verify
        let isPaused = await mockRunner.isPaused()
        XCTAssertFalse(isPaused)
        XCTAssertEqual(await mockRunner.runCallCount, 1)
        XCTAssertEqual(simulation.status, .completed)
    }

    func testSimulationCancellation() async throws {
        let workspace = Workspace(name: "Test")
        let mockRunner = MockSimulationRunner()
        mockRunner.simulationDuration = 10.0  // Long simulation

        let viewModel = AppViewModel(workspace: workspace) { _ in mockRunner }

        let simulation = Simulation(
            name: "Test Sim",
            configurationData: createTestConfig()
        )
        viewModel.selectedSimulation = simulation

        // Start simulation
        viewModel.runSimulation(simulation)

        // Wait a bit
        try await Task.sleep(for: .milliseconds(100))

        // Cancel
        viewModel.stopSimulation()

        // Wait for cancellation
        try await Task.sleep(for: .milliseconds(200))

        // Verify
        XCTAssertEqual(simulation.status, .cancelled)
    }

    func testPauseResume() async throws {
        let workspace = Workspace(name: "Test")
        let mockRunner = MockSimulationRunner()
        mockRunner.simulationDuration = 2.0

        let viewModel = AppViewModel(workspace: workspace) { _ in mockRunner }

        let simulation = Simulation(
            name: "Test Sim",
            configurationData: createTestConfig()
        )
        viewModel.selectedSimulation = simulation

        // Start
        viewModel.runSimulation(simulation)
        try await Task.sleep(for: .milliseconds(200))

        // Pause
        viewModel.pauseSimulation()
        try await Task.sleep(for: .milliseconds(100))

        let isPausedAfterPause = await mockRunner.isPaused()
        XCTAssertTrue(isPausedAfterPause)

        // Resume
        viewModel.resumeSimulation()
        try await Task.sleep(for: .milliseconds(100))

        let isPausedAfterResume = await mockRunner.isPaused()
        XCTAssertFalse(isPausedAfterResume)
    }

    func testSimulationErrorHandling() async throws {
        let workspace = Workspace(name: "Test")
        let mockRunner = MockSimulationRunner()
        mockRunner.shouldFail = true  // Force failure

        let viewModel = AppViewModel(workspace: workspace) { _ in mockRunner }

        let simulation = Simulation(
            name: "Test Sim",
            configurationData: createTestConfig()
        )
        viewModel.selectedSimulation = simulation

        // Execute
        viewModel.runSimulation(simulation)

        // Wait for completion
        try await Task.sleep(for: .milliseconds(500))

        // Verify
        XCTAssertEqual(simulation.status, .failed(error: "Test failure"))
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
```

---

## Phase 2 の実装チェックリスト

### Gotenx アプリ側

- [ ] AppViewModel に runnerFactory を追加
  - [ ] `private let runnerFactory: (SimulationConfiguration) -> any SimulationRunnable`
  - [ ] `init` に factory parameter を追加
  - [ ] `currentRunner` を `(any SimulationRunnable)?` 型に変更
  - [ ] `runSimulation` で factory を使用

- [ ] MockSimulationRunner を実装
  - [ ] すべての protocol メソッド
  - [ ] テスト制御プロパティ
  - [ ] 状態追跡
  - [ ] Task cancellation サポート

- [ ] テストコードを作成
  - [ ] testSimulationSuccess
  - [ ] testSimulationCancellation
  - [ ] testPauseResume
  - [ ] testSimulationErrorHandling

**推定時間**: 3-4 hours

---

## メリット

### Phase 1（完了）
- ✅ Production コードが動作
- ✅ エラーハンドリングが適切
- ✅ Pause/Resume/Stop が機能
- ✅ Live plotting が実装

### Phase 2（実装後）
- ✅ AppViewModel を高速にテスト可能
- ✅ CI/CD で自動テスト実行
- ✅ 様々なシナリオをテスト（成功、失敗、キャンセル）
- ✅ 将来の拡張性（RemoteSimulationRunner など）

---

## 結論

**Phase 1 は完了し、production ready です**。

**次のステップ**:
1. Phase 2 の実装（依存性注入とモック）
2. テストコードの作成
3. CI/CD パイプラインへの組み込み

**推定作業時間（Phase 2）**: 3-4 hours

---

**文書バージョン**: 1.0
**最終更新**: 2025-10-23
**次のアクション**: Phase 2 の実装を開始（オプション）
