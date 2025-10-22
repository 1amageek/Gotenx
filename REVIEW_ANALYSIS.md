# Gotenx App 仕様レビュー分析

**日付**: 2025-10-22
**バージョン**: 1.1
**レビュー対象**: GOTENX_APP_SPECIFICATION.md v1.0

---

## 総合評価: ⭐⭐⭐⭐☆ (4/5)

### 強み
- ✅ 非常に詳細で実装可能な仕様
- ✅ アーキテクチャが明確（SwiftUI + SwiftData + Observation）
- ✅ UI/UXデザインが具体的（ASCII図で可視化）
- ✅ 段階的な実装ロードマップ
- ✅ swift-gotenx統合戦略が明確

---

## 🔴 Critical Issues（実装前に必須対応）

### 1. データストレージ戦略の問題 ⚠️ HIGH PRIORITY

**問題箇所**: Section 4.1 - SimulationSnapshot

```swift
@Model
class SimulationSnapshot {
    var profiles: Data  // CoreProfiles encoded (数KB)
    var derivedQuantities: Data?
}
```

**問題分析**:
- **データ量**: 1シミュレーション = 2,000スナップショット × 数KB = 数MB〜数十MB
- **SwiftDataの制約**: 大量の小オブジェクトはインデックス肥大化・検索性能劣化
- **メモリ効率**: 全スナップショットのロードは非効率

**実測見積もり**:
```
CoreProfiles (100セル):
- ionTemperature: [Float] × 100 = 400 bytes
- electronTemperature: [Float] × 100 = 400 bytes
- electronDensity: [Float] × 100 = 400 bytes
- poloidalFlux: [Float] × 100 = 400 bytes
合計: ~1.6 KB/snapshot

2000 snapshots × 1.6 KB = 3.2 MB/simulation
10 simulations = 32 MB (許容範囲)

しかし、100セル → 1000セルの場合:
2000 snapshots × 16 KB = 32 MB/simulation
10 simulations = 320 MB (SwiftDataで非効率)
```

**推奨解決策**: ハイブリッドストレージ

```swift
@Model
class Simulation {
    var id: UUID
    var name: String
    var configuration: Data
    var status: SimulationStatus

    // SwiftDataには軽量メタデータのみ
    var snapshotMetadata: [SnapshotMetadata] = []

    // 実データは外部ファイル
    var dataFileURL: URL?  // ~/Library/Application Support/Gotenx/simulations/{id}/
}

struct SnapshotMetadata: Codable {
    var time: Float
    var index: Int
    var coreTi: Float  // 要約データ（コア温度）
    var avgNe: Float   // 要約データ（平均密度）
    var fileOffset: Int  // データファイル内のオフセット
}
```

**ストレージ構造**:
```
~/Library/Application Support/Gotenx/
├── simulations/
│   ├── {simulation-id-1}/
│   │   ├── config.json
│   │   ├── snapshots.bin    # バイナリ形式（高速）
│   │   └── snapshots.json   # JSON形式（互換性）
│   └── {simulation-id-2}/
│       └── ...
└── gotenx.sqlite  # SwiftData (メタデータのみ)
```

**実装例**:

```swift
// ファイルベースストレージマネージャー
actor SimulationDataStore {
    private let fileManager = FileManager.default
    private let baseURL: URL

    init() throws {
        baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Gotenx/simulations")
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func saveSnapshot(_ snapshot: CoreProfiles, time: Float, for simulationID: UUID) async throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)
        try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)

        let snapshotFile = simDir.appendingPathComponent("snapshots.json")

        // Append to JSONL (JSON Lines) format
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let line = String(data: data, encoding: .utf8)! + "\n"

        if fileManager.fileExists(atPath: snapshotFile.path) {
            let handle = try FileHandle(forWritingTo: snapshotFile)
            try handle.seekToEnd()
            try handle.write(contentsOf: line.data(using: .utf8)!)
            try handle.close()
        } else {
            try line.write(to: snapshotFile, atomically: true, encoding: .utf8)
        }
    }

    func loadSnapshots(for simulationID: UUID) async throws -> [CoreProfiles] {
        let snapshotFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("snapshots.json")

        let contents = try String(contentsOf: snapshotFile, encoding: .utf8)
        let decoder = JSONDecoder()

        return try contents.split(separator: "\n").map { line in
            try decoder.decode(CoreProfiles.self, from: Data(line.utf8))
        }
    }
}
```

**メリット**:
- ✅ SwiftDataは軽量（メタデータのみ）
- ✅ 大量データの効率的な保存
- ✅ Lazy loading可能
- ✅ エクスポート容易（ファイルコピー）
- ✅ バックアップ容易

---

### 2. Actor Isolation とSwiftDataの競合 ⚠️ HIGH PRIORITY

**問題箇所**: Section 5.1 - AppViewModel

```swift
@MainActor
@Observable
class AppViewModel {
    func runSimulation(_ simulation: Simulation) async throws {
        orchestrator = SimulationOrchestrator()  // actor

        let result = try await orchestrator!.run(
            config: config,
            progressCallback: { [weak self] progress in
                await self?.handleProgress(progress, simulation: simulation)
            }
        )

        // ❌ Actor isolationエラーの可能性
        simulation.snapshots.append(snapshot)  // SwiftData mutation on MainActor
    }
}
```

**問題分析**:
- `SimulationOrchestrator` は `actor`（非MainActor）
- `Simulation` は `@Model`（MainActor bound）
- コールバック内での状態変更が競合

**推奨解決策**:

```swift
@MainActor
@Observable
class AppViewModel {
    private var simulationTask: Task<Void, Error>?

    func runSimulation(_ simulation: Simulation) async throws {
        guard simulationTask == nil else {
            throw AppError.simulationAlreadyRunning
        }

        simulationTask = Task { @MainActor in
            isSimulationRunning = true
            simulation.status = .running(progress: 0.0)

            // Orchestrator呼び出し（非MainActor）
            let orchestrator = SimulationOrchestrator()

            do {
                let result = try await orchestrator.run(
                    config: config,
                    progressCallback: { progress in
                        // MainActorでコールバック実行
                        await MainActor.run {
                            self.handleProgress(progress, simulation: simulation)
                        }
                    }
                )

                // 結果保存（MainActor）
                await saveResults(result, to: simulation)

                simulation.status = .completed

            } catch {
                simulation.status = .failed(error: error.localizedDescription)
                throw error
            }

            isSimulationRunning = false
            simulationTask = nil
        }

        try await simulationTask?.value
    }

    @MainActor
    private func handleProgress(_ progress: ProgressInfo, simulation: Simulation) {
        // MainActorで安全に状態更新
        simulationProgress = Double(progress.currentTime) / Double(totalSimulationTime)
        liveProfiles = progress.profiles
        simulation.status = .running(progress: simulationProgress)
    }

    @MainActor
    private func saveResults(_ result: SimulationResult, to simulation: Simulation) async {
        guard let timeSeries = result.timeSeries else { return }

        // ファイルベースストレージに保存
        let dataStore = try! SimulationDataStore()

        for timePoint in timeSeries {
            // 外部ファイルに保存
            try await dataStore.saveSnapshot(
                timePoint.profiles,
                time: timePoint.time,
                for: simulation.id
            )

            // SwiftDataには軽量メタデータのみ
            let metadata = SnapshotMetadata(
                time: timePoint.time,
                index: simulation.snapshotMetadata.count,
                coreTi: timePoint.profiles.ionTemperature.first ?? 0,
                avgNe: timePoint.profiles.electronDensity.reduce(0, +) / Float(timePoint.profiles.electronDensity.count)
            )
            simulation.snapshotMetadata.append(metadata)
        }

        simulation.dataFileURL = dataStore.baseURL.appendingPathComponent(simulation.id.uuidString)
    }
}
```

---

### 3. タスクキャンセルと一時停止 ⚠️ MEDIUM PRIORITY

**問題箇所**: Section 5.1 - pauseSimulation/stopSimulation

```swift
func pauseSimulation() {
    // TODO: Orchestrator pause functionality needed
    if let simulation = selectedSimulation {
        simulation.status = .paused(at: simulationProgress)
    }
    isSimulationRunning = false
}
```

**問題**: 実際にはタスクが停止していない

**推奨解決策**:

```swift
@MainActor
@Observable
class AppViewModel {
    private var simulationTask: Task<Void, Error>?
    private var isPaused: Bool = false

    func pauseSimulation() {
        isPaused = true
        if let simulation = selectedSimulation {
            simulation.status = .paused(at: simulationProgress)
        }
        isSimulationRunning = false
    }

    func resumeSimulation() async throws {
        guard isPaused, let simulation = selectedSimulation else { return }
        isPaused = false
        isSimulationRunning = true
        simulation.status = .running(progress: simulationProgress)

        // Resume from current state
        // Note: swift-gotenxにresume機能が必要
    }

    func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        isPaused = false
        isSimulationRunning = false

        if let simulation = selectedSimulation {
            simulation.status = .draft
        }
    }
}
```

**swift-gotenx側の対応が必要**:

```swift
// SimulationOrchestrator.swift
public actor SimulationOrchestrator {
    private var isCancelled = false

    public func cancel() {
        isCancelled = true
    }

    public func run(...) async throws -> SimulationResult {
        while currentTime < endTime {
            // キャンセルチェック
            if isCancelled {
                throw SimulationError.cancelled
            }

            // または Swift Concurrency標準のキャンセルチェック
            try Task.checkCancellation()

            // ... simulation step ...
        }
    }
}
```

---

## 🟡 Important Issues（実装中に対応推奨）

### 4. エラーハンドリングの強化

**問題箇所**: 複数箇所で `try!` の使用

```swift
self.configuration = try! JSONEncoder().encode(configuration)  // ❌
```

**推奨解決策**:

```swift
// Option 1: フォールバック値
self.configuration = (try? JSONEncoder().encode(configuration)) ?? Data()

// Option 2: エラーを投げる初期化
init(name: String, configuration: SimulationConfiguration) throws {
    self.id = UUID()
    self.name = name
    self.configuration = try JSONEncoder().encode(configuration)
    self.status = .draft
    self.createdAt = Date()
    self.modifiedAt = Date()
}

// Option 3: Resultパターン
enum ConfigurationState {
    case valid(Data)
    case invalid(Error)
}

var configurationState: ConfigurationState {
    do {
        let data = try JSONEncoder().encode(decodedConfiguration)
        return .valid(data)
    } catch {
        return .invalid(error)
    }
}
```

---

### 5. リアルタイム更新のスロットリング改善

**問題箇所**: Section 5.1 - handleProgress

```swift
// 現状: フレーム数ベース
if progress.step % 10 == 0 {
    liveProfiles = progress.profiles
}
```

**推奨**: 時間ベースのスロットリング

```swift
@MainActor
@Observable
class AppViewModel {
    private var lastUpdateTime: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 0.1  // 100ms

    private func handleProgress(_ progress: ProgressInfo, simulation: Simulation) {
        let now = Date()

        // 時間ベースのスロットリング
        if now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval {
            simulationProgress = Double(progress.currentTime) / Double(totalSimulationTime)
            liveProfiles = progress.profiles
            liveDerived = progress.derivedQuantities
            lastUpdateTime = now
        }

        // ステータスは常に更新
        simulation.status = .running(progress: Double(progress.currentTime) / Double(totalSimulationTime))
    }
}
```

---

### 6. メモリ効率の改善

**問題**: 大量のプロットデータをメモリに保持

**推奨**: Lazy loading + キャッシュ戦略

```swift
@MainActor
@Observable
class PlotViewModel {
    private var cachedPlotData: [UUID: PlotData] = [:]
    private let cacheLimit = 3  // 最大3シミュレーション分キャッシュ

    func loadPlotData(for simulation: Simulation) async throws {
        // キャッシュチェック
        if let cached = cachedPlotData[simulation.id] {
            self.plotData = cached
            return
        }

        // ファイルから読み込み
        let dataStore = try SimulationDataStore()
        let snapshots = try await dataStore.loadSnapshots(for: simulation.id)

        // PlotDataに変換
        let plotData = try PlotData(from: snapshots)

        // キャッシュ管理
        if cachedPlotData.count >= cacheLimit {
            // LRU: 最も古いエントリを削除
            if let oldestKey = cachedPlotData.keys.first {
                cachedPlotData.removeValue(forKey: oldestKey)
            }
        }

        cachedPlotData[simulation.id] = plotData
        self.plotData = plotData
    }
}
```

---

### 7. SwiftDataの双方向関係

**問題箇所**: Section 4.1

```swift
var workspace: Workspace?  // 親への参照
var simulation: Simulation?  // 親への参照
```

**推奨**: SwiftDataの自動管理に任せる

```swift
// ✅ 良い例: SwiftDataが自動管理
@Model
class Simulation {
    var id: UUID
    var name: String
    // 明示的な親参照は不要（SwiftDataが管理）
    // var workspace: Workspace?  // ← 削除
}

// 使用時
let simulation = Simulation(name: "Test", configuration: config)
workspace.simulations.append(simulation)  // これだけでOK
```

---

## 🟢 Minor Issues（最適化レベル）

### 8. プレビュー用のモックデータ

**推奨追加**:

```swift
#if DEBUG
extension Workspace {
    static var preview: Workspace {
        let workspace = Workspace(name: "Preview Workspace")

        let config = SimulationConfiguration.minimal

        // 完了済みシミュレーション
        let completed = Simulation(name: "ITER-like (QLKNN)", configuration: config)
        completed.status = .completed
        workspace.simulations.append(completed)

        // 実行中シミュレーション
        let running = Simulation(name: "Bohm-GyroBohm", configuration: config)
        running.status = .running(progress: 0.45)
        workspace.simulations.append(running)

        // 失敗シミュレーション
        let failed = Simulation(name: "High-Beta Test", configuration: config)
        failed.status = .failed(error: "Convergence failed")
        workspace.simulations.append(failed)

        return workspace
    }
}
#endif
```

---

### 9. ログとデバッグ

**推奨追加**:

```swift
import OSLog

extension Logger {
    static let simulation = Logger(subsystem: "com.gotenx.app", category: "simulation")
    static let dataStore = Logger(subsystem: "com.gotenx.app", category: "datastore")
    static let ui = Logger(subsystem: "com.gotenx.app", category: "ui")
}

// 使用例
@MainActor
func runSimulation(_ simulation: Simulation) async throws {
    Logger.simulation.info("Starting simulation: \(simulation.name, privacy: .public)")

    do {
        let result = try await orchestrator.run(...)
        Logger.simulation.notice("Simulation completed successfully")
    } catch {
        Logger.simulation.error("Simulation failed: \(error.localizedDescription)")
        throw error
    }
}
```

---

### 10. アクセシビリティ

**推奨追加**:

```swift
// ToolbarView.swift
Button {
    // ...
} label: {
    Label("Run", systemImage: "play.fill")
}
.keyboardShortcut("r", modifiers: .command)
.help("Run Simulation (⌘R)")
.accessibilityLabel("Run simulation")
.accessibilityHint("Starts the selected simulation")
```

---

## 📋 修正優先度マトリクス

| 優先度 | 項目 | 影響範囲 | 実装工数 | 推奨タイミング |
|--------|------|----------|----------|--------------|
| 🔴 P0 | データストレージ戦略 | 全体 | 2-3日 | Phase 1 |
| 🔴 P0 | Actor Isolation | 実行フロー | 1-2日 | Phase 2 |
| 🟡 P1 | タスクキャンセル | 実行制御 | 1日 | Phase 2 |
| 🟡 P1 | エラーハンドリング | 全体 | 1日 | Phase 1-2 |
| 🟡 P1 | スロットリング改善 | UI性能 | 0.5日 | Phase 3 |
| 🟢 P2 | メモリ最適化 | 性能 | 1-2日 | Phase 4 |
| 🟢 P2 | ログ・デバッグ | 保守性 | 0.5日 | Phase 1 |
| 🟢 P3 | アクセシビリティ | UX | 1日 | Phase 5 |

---

## 🎯 推奨実装戦略（修正版）

### Phase 1: 基盤整備（2-3日）→ 3-4日に延長

**追加タスク**:
1. ✅ SimulationDataStore実装（ファイルベース）
2. ✅ エラーハンドリング戦略確立
3. ✅ ログフレームワーク統合
4. ✅ SwiftDataモデル（軽量化版）

### Phase 2: シミュレーション実行（2-3日）→ 3-4日に延長

**追加タスク**:
1. ✅ Actor isolation対応
2. ✅ タスクキャンセル実装
3. ✅ 時間ベーススロットリング

### Phase 3以降: 変更なし

---

## 📝 swift-gotenx側の必要対応（再確認）

### 必須（P0）
1. ✅ `ProgressInfo` struct 追加
2. ✅ `SimulationOrchestrator.run()` にコールバック追加
3. ✅ `CoreProfiles`, `DerivedQuantities` の `Codable` 準拠確認

### 推奨（P1）
4. ⏳ タスクキャンセル対応 (`Task.checkCancellation()`)
5. ⏳ `SimulationError.cancelled` 追加

### オプション（P2）
6. ⏳ Pause/Resume機能（将来対応）
7. ⏳ `PlotData(from: [SimulationSnapshot])` 初期化子
   - **代替案**: Gotenx App側でアダプターパターン実装

---

## ✅ 改善版実装例

### SimulationDataStore（完全版）

```swift
import Foundation

actor SimulationDataStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    enum StorageError: LocalizedError {
        case directoryCreationFailed
        case fileWriteFailed
        case fileReadFailed
        case corruptedData

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed: return "Failed to create storage directory"
            case .fileWriteFailed: return "Failed to write snapshot data"
            case .fileReadFailed: return "Failed to read snapshot data"
            case .corruptedData: return "Snapshot data is corrupted"
            }
        }
    }

    init() throws {
        baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Gotenx/simulations", isDirectory: true)

        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func saveSnapshot(
        _ profiles: CoreProfiles,
        derived: DerivedQuantities?,
        time: Float,
        for simulationID: UUID
    ) async throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        if !fileManager.fileExists(atPath: simDir.path) {
            try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
        }

        let snapshotFile = simDir.appendingPathComponent("snapshots.jsonl")

        let snapshotData = SnapshotData(
            time: time,
            profiles: profiles,
            derived: derived
        )

        do {
            let data = try encoder.encode(snapshotData)
            var line = String(data: data, encoding: .utf8)!
            line.append("\n")

            if fileManager.fileExists(atPath: snapshotFile.path) {
                let handle = try FileHandle(forWritingTo: snapshotFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line.data(using: .utf8)!)
            } else {
                try line.write(to: snapshotFile, atomically: true, encoding: .utf8)
            }
        } catch {
            throw StorageError.fileWriteFailed
        }
    }

    func loadSnapshots(for simulationID: UUID) async throws -> [(time: Float, profiles: CoreProfiles, derived: DerivedQuantities?)] {
        let snapshotFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("snapshots.jsonl")

        guard fileManager.fileExists(atPath: snapshotFile.path) else {
            return []
        }

        do {
            let contents = try String(contentsOf: snapshotFile, encoding: .utf8)

            return try contents
                .split(separator: "\n")
                .filter { !$0.isEmpty }
                .map { line in
                    let snapshot = try decoder.decode(SnapshotData.self, from: Data(line.utf8))
                    return (snapshot.time, snapshot.profiles, snapshot.derived)
                }
        } catch {
            throw StorageError.fileReadFailed
        }
    }

    func deleteSimulation(_ simulationID: UUID) async throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)
        try fileManager.removeItem(at: simDir)
    }
}

private struct SnapshotData: Codable {
    let time: Float
    let profiles: CoreProfiles
    let derived: DerivedQuantities?
}
```

---

## 総評（修正版）

### 総合スコア: ⭐⭐⭐⭐☆ (4.5/5)

**優れている点**:
- ✅ 実装可能性の高い詳細設計
- ✅ 適切な技術スタック選択
- ✅ 明確なアーキテクチャ
- ✅ 段階的実装計画

**改善すべき点**:
- 🔴 データストレージ戦略（SwiftData過信）
- 🔴 Actor isolation考慮不足
- 🟡 エラーハンドリング不足
- 🟡 タスク管理機能不足

**修正後の評価**: ⭐⭐⭐⭐⭐ (5/5)
- 上記の修正を反映すれば、プロダクション品質の設計となる

---

## Next Steps

1. ✅ `GOTENX_APP_SPECIFICATION.md` を修正版で上書き
2. ✅ `SimulationDataStore.swift` を新規追加
3. ✅ `GOTENX_APP_INTEGRATION.md` にキャンセル対応を追加
4. ✅ テスト戦略ドキュメントを作成

---

**レビュー完了日**: 2025-10-22
**次回レビュー**: Phase 2完了時
