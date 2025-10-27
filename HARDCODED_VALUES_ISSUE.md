# ハードコード値の問題と改善提案

**作成日**: 2025-10-23
**対象**: swift-gotenx v1.0, Gotenx App
**カテゴリ**: Architecture, Configuration Design

## 問題の概要

シミュレーション実行時に設定ファイル（`SimulationConfiguration`）の値が無視され、コード内にハードコードされた値が使用されている。これにより、ユーザーが設定を変更しても効果がなく、数値安定性の調整も困難になっている。

## 発見された問題

### ✅ 検証済み: 1. 初期タイムステップが無視される

**場所**: `SimulationOrchestrator.swift:413-417`

```swift
} else {
    // First step: use fixed small timestep
    // ✅ FIXED: Increased from 1e-5 to 1e-4 for numerical stability
    dt = 1e-4  // ❌ ハードコード（過去に 1e-5 → 1e-4 に変更されたが、根本的な解決ではない）
    print("[DEBUG] First step: dt=\(dt)s")
}
```

**問題**:
- `SimulationConfiguration.time.initialDt` が既に存在（例: `1e-3`）
- `DynamicRuntimeParams.dt` に正しく渡されている
- しかし `SimulationOrchestrator` がこれを無視して固定値 `1e-4` を使用
- コメントの "FIXED" は過去の数値調整を意味し、根本的な設計問題は未解決

**影響**:
- ユーザーが `initialDt` を設定しても効果がない
- 数値安定性の調整ができない
- プリセット間で初期タイムステップを変えられない
- 応急処置（マジックナンバーの調整）の繰り返しが発生

### 2. 初期プロファイル生成が二重にハードコードされている

#### ✅ 検証済み: 問題 2-A: DynamicConfig でのハードコード

**場所**: `DynamicConfig.swift:102-122`

```swift
/// **Units**: eV for temperature, m^-3 for density (no conversion)
/// This maintains consistency with CoreProfiles and BoundaryConditions.
func toProfileConditions() -> ProfileConditions {
    ProfileConditions(
        ionTemperature: .parabolic(
            peak: boundaries.ionTemperature * 10.0,  // ❌ ハードコード (eV, core ~10× edge)
            edge: boundaries.ionTemperature,
            exponent: 2.0  // ❌ ハードコード
        ),
        electronTemperature: .parabolic(
            peak: boundaries.electronTemperature * 10.0,  // ❌ ハードコード
            edge: boundaries.electronTemperature,
            exponent: 2.0
        ),
        electronDensity: .parabolic(
            peak: boundaries.density * 3.0,  // ❌ ハードコード (m^-3, core ~3× edge)
            edge: boundaries.density,
            exponent: 1.5  // ❌ ハードコード (Flatter density profile)
        ),
        currentDensity: .constant(1.0)  // Placeholder: 1 MA/m^2
    )
}
```

**問題**:
- Core/Edge 比率が固定（温度: 10×, 密度: 3×）
- プロファイル形状の指数が固定（温度: 2.0, 密度: 1.5）
- 物理シナリオによって変更できない
- **このメソッドは実装されているが、SimulationRunner から呼び出されていない**

#### ✅ 検証済み: 問題 2-B: SimulationRunner での再ハードコード

**場所**: `SimulationRunner.swift:211-218`

```swift
// Temperature profiles [eV]
let tiEdge = boundaries.ionTemperature
let tiCore = tiEdge * 5.0  // ✅ FIXED: Reduced from 10× to 5× for smoother initial profile
var ti = [Float](repeating: 0.0, count: nCells)
for i in 0..<nCells {
    let factor = pow(1.0 - rNorm[i] * rNorm[i], 2.0)
    ti[i] = tiEdge + (tiCore - tiEdge) * factor
}

// Density profile [m^-3]
let neCore = neEdge * 2.0  // ❌ ハードコード（DynamicConfig の 3× を無視）
```

**問題**:
- `DynamicConfig.toProfileConditions()` で生成された `ProfileConditions` を**完全に無視**
- 独自のロジックで初期プロファイルを生成
- コメントの "FIXED" は過去に 10× → 5× に調整したことを示すが、応急処置に過ぎない
- 設定システムとの整合性が完全に崩壊

**データフロー図**:
```
SimulationConfiguration
  └─> DynamicConfig
       └─> ProfileConditions (10×, 3×)  ❌ 生成されるが無視される

SimulationRunner.initialize()
  └─> generateInitialProfiles()
       └─> 独自ロジック (5×, 2×)  ❌ ハードコード値を使用
```

## アーキテクチャの問題

### 設計の意図 vs 実装の乖離

**本来の設計**:
```
[Configuration] → [ProfileConditions] → [Initial Profiles] → [Simulation]
     JSON              設定値             MLXArray            実行
```

**現在の実装**:
```
[Configuration] → [ProfileConditions] ✗ 無視される

[SimulationRunner] → [ハードコード値] → [Initial Profiles] → [Simulation]
                          5×, 2×            MLXArray            実行
```

### 根本原因

1. **責任の重複**:
   - `DynamicConfig.toProfileConditions()` が初期プロファイル形状を定義
   - `SimulationRunner.generateInitialProfiles()` が同じことを再実装

2. **インターフェース無視**:
   - `ProfileConditions` という抽象化が用意されている
   - しかし `SimulationRunner` がこれを使わず、直接 `BoundaryConfig` から生成

3. **設定システムの不完全性**:
   - 初期プロファイル形状を設定する仕組みがない
   - そのためハードコードに頼らざるを得ない

## 本来あるべき設計

### 原則

1. **Single Source of Truth**: 設定値は `SimulationConfiguration` が唯一の真実
2. **Separation of Concerns**: 設定と実行ロジックを分離
3. **Configurability**: ユーザーが全ての重要なパラメータを設定可能

### 理想のデータフロー

```
[SimulationConfiguration]
  ├─> time.initialDt: 1e-3
  └─> runtime.dynamic.initialProfile
       ├─> temperaturePeakRatio: 5.0
       ├─> densityPeakRatio: 2.0
       ├─> temperatureExponent: 2.0
       └─> densityExponent: 1.5
              ↓
[DynamicRuntimeParams]
  ├─> dt: 1e-3
  └─> profileConditions: .parabolic(...)
              ↓
[SimulationOrchestrator]
  └─> 最初のステップで dt = dynamicParams.dt を使用
              ↓
[SimulationRunner]
  └─> ProfileConditions から初期プロファイルを生成
```

## 改善提案

### Phase 1: 即座の修正（実装バグの修正）

#### 1.1 SimulationOrchestrator での dt 使用

**変更箇所**: `SimulationOrchestrator.swift:413-417`

```swift
// ❌ Before
} else {
    // First step: use fixed small timestep
    // ✅ FIXED: Increased from 1e-5 to 1e-4 for numerical stability
    dt = 1e-4
    print("[DEBUG] First step: dt=\(dt)s")
}

// ✅ After
} else {
    // First step: use configured timestep with safety lower bound
    dt = max(dynamicParams.dt, 1e-5)  // ✅ Use config, but enforce minimum 10μs
    print("[DEBUG] First step: dt=\(dt)s (configured: \(dynamicParams.dt)s)")
}
```

**効果**:
- ユーザーの `initialDt` 設定が即座に反映される
- 数値安定性の調整が可能になる
- 安全な下限（1e-5s）を維持し、極端に小さい値を防ぐ

**実装の注意点**:
- `max(dynamicParams.dt, 1e-5)` により、ユーザーが極端に小さい値（例: 1e-10s）を設定した場合でも、数値誤差の蓄積を防ぐ
- デバッグメッセージで設定値と実際に使用される値の両方を表示

#### 1.2 SimulationRunner での ProfileConditions 使用

**変更箇所**: `SimulationRunner.swift:47-89`

```swift
// ❌ Before (in initialize method)
public func initialize(
    transportModel: any TransportModel,
    sourceModels: [any SourceModel],
    mhdModels: [any MHDModel]? = nil
) async throws {
    let staticParams = try config.runtime.static.toRuntimeParams()

    // ❌ boundaries から直接生成（ProfileConditions を無視）
    let initialProfiles = try generateInitialProfiles(
        mesh: config.runtime.static.mesh,
        boundaries: config.runtime.dynamic.boundaries
    )
    // ...
}

// ✅ After (in initialize method)
public func initialize(
    transportModel: any TransportModel,
    sourceModels: [any SourceModel],
    mhdModels: [any MHDModel]? = nil
) async throws {
    let staticParams = try config.runtime.static.toRuntimeParams()

    // ✅ DynamicConfig から ProfileConditions を取得
    let profileConditions = config.runtime.dynamic.toProfileConditions()

    // ✅ ProfileConditions を使って初期プロファイルを生成
    let initialProfiles = try generateInitialProfiles(
        mesh: config.runtime.static.mesh,
        profileConditions: profileConditions
    )
    // ...
}
```

**generateInitialProfiles() の変更**:

```swift
// ❌ Before
private func generateInitialProfiles(
    mesh: MeshConfig,
    boundaries: BoundaryConfig
) throws -> CoreProfiles {
    let nCells = mesh.nCells
    var rNorm = [Float](repeating: 0.0, count: nCells)
    for i in 0..<nCells {
        rNorm[i] = Float(i) / Float(nCells - 1)
    }

    // ❌ ハードコードされた値で生成
    let tiEdge = boundaries.ionTemperature
    let tiCore = tiEdge * 5.0
    var ti = [Float](repeating: 0.0, count: nCells)
    for i in 0..<nCells {
        let factor = pow(1.0 - rNorm[i] * rNorm[i], 2.0)
        ti[i] = tiEdge + (tiCore - tiEdge) * factor
    }
    // ... similar for te, ne
}

// ✅ After
private func generateInitialProfiles(
    mesh: MeshConfig,
    profileConditions: ProfileConditions
) throws -> CoreProfiles {
    let nCells = mesh.nCells

    // Generate radial grid
    var rNorm = [Float](repeating: 0.0, count: nCells)
    for i in 0..<nCells {
        rNorm[i] = Float(i) / Float(nCells - 1)
    }

    // ✅ ProfileConditions から評価
    var ti = [Float](repeating: 0.0, count: nCells)
    var te = [Float](repeating: 0.0, count: nCells)
    var ne = [Float](repeating: 0.0, count: nCells)

    for i in 0..<nCells {
        ti[i] = profileConditions.ionTemperature.evaluate(at: rNorm[i])
        te[i] = profileConditions.electronTemperature.evaluate(at: rNorm[i])
        ne[i] = profileConditions.electronDensity.evaluate(at: rNorm[i])
    }

    // Poloidal flux (initially zero)
    let psi = [Float](repeating: 0.0, count: nCells)

    // Create evaluated arrays
    let evaluated = EvaluatedArray.evaluatingBatch([
        MLXArray(ti),
        MLXArray(te),
        MLXArray(ne),
        MLXArray(psi)
    ])

    return CoreProfiles(
        ionTemperature: evaluated[0],
        electronTemperature: evaluated[1],
        electronDensity: evaluated[2],
        poloidalFlux: evaluated[3]
    )
}
```

**効果**:
- 設定システムが正しく機能する
- DynamicConfig の設定が反映される
- コードの重複が解消される（DRY 原則）

### Phase 2: 設定の拡張（設計改善）

#### 2.1 InitialProfileConfig の追加

**新規ファイル**: `Sources/GotenxCore/Configuration/InitialProfileConfig.swift`

```swift
/// Initial profile generation configuration
///
/// Controls the shape of initial plasma profiles generated from boundary conditions.
/// These parameters significantly affect numerical stability and physical realism.
public struct InitialProfileConfig: Codable, Sendable, Equatable {
    /// Core/Edge temperature ratio
    ///
    /// **Physical range**: 3.0 - 10.0
    /// - Lower values (3.0-5.0): Better numerical stability, suitable for initial testing
    /// - Higher values (7.0-10.0): More realistic tokamak profiles
    ///
    /// **Default**: 5.0 (balanced)
    public let temperaturePeakRatio: Float

    /// Core/Edge density ratio
    ///
    /// **Physical range**: 1.5 - 3.0
    /// - Lower values (1.5-2.0): Better numerical stability, flatter profiles
    /// - Higher values (2.5-3.0): More realistic density peaking
    ///
    /// **Default**: 2.0 (conservative)
    public let densityPeakRatio: Float

    /// Temperature profile shape exponent
    ///
    /// Profile: T(r) = T_edge + (T_core - T_edge) * (1 - (r/a)^2)^exponent
    ///
    /// **Common values**:
    /// - 1.0: Linear
    /// - 2.0: Parabolic (standard)
    /// - 3.0: More peaked
    ///
    /// **Default**: 2.0
    public let temperatureExponent: Float

    /// Density profile shape exponent
    ///
    /// Profile: n(r) = n_edge + (n_core - n_edge) * (1 - (r/a)^2)^exponent
    ///
    /// **Common values**:
    /// - 1.0: Linear
    /// - 1.5: Typical tokamak (flatter than temperature)
    /// - 2.0: Parabolic
    ///
    /// **Default**: 1.5
    public let densityExponent: Float

    public init(
        temperaturePeakRatio: Float = 5.0,
        densityPeakRatio: Float = 2.0,
        temperatureExponent: Float = 2.0,
        densityExponent: Float = 1.5
    ) {
        self.temperaturePeakRatio = temperaturePeakRatio
        self.densityPeakRatio = densityPeakRatio
        self.temperatureExponent = temperatureExponent
        self.densityExponent = densityExponent
    }

    /// Default configuration for numerical stability
    public static let `default` = InitialProfileConfig()

    /// Realistic tokamak profiles (steeper gradients)
    public static let realistic = InitialProfileConfig(
        temperaturePeakRatio: 10.0,
        densityPeakRatio: 3.0,
        temperatureExponent: 2.0,
        densityExponent: 1.5
    )

    /// Conservative profiles for numerical testing
    public static let conservative = InitialProfileConfig(
        temperaturePeakRatio: 3.0,
        densityPeakRatio: 1.5,
        temperatureExponent: 1.5,
        densityExponent: 1.0
    )
}
```

#### 2.2 DynamicConfig への統合

**変更箇所**: `DynamicConfig.swift`

```swift
public struct DynamicConfig: Codable, Sendable, Equatable {
    // 既存フィールド
    public let boundaries: BoundaryConfig
    public let transport: TransportConfig
    public let sources: SourcesConfig
    public let pedestal: PedestalConfig?
    public let mhd: MHDConfig
    public let restart: RestartConfig

    // 追加
    /// Initial profile configuration
    public let initialProfile: InitialProfileConfig

    public init(
        boundaries: BoundaryConfig,
        transport: TransportConfig,
        sources: SourcesConfig = .default,
        pedestal: PedestalConfig? = nil,
        mhd: MHDConfig = .default,
        restart: RestartConfig = .default,
        initialProfile: InitialProfileConfig = .default  // 追加
    ) {
        self.boundaries = boundaries
        self.transport = transport
        self.sources = sources
        self.pedestal = pedestal
        self.mhd = mhd
        self.restart = restart
        self.initialProfile = initialProfile  // 追加
    }

    func toProfileConditions() -> ProfileConditions {
        ProfileConditions(
            ionTemperature: .parabolic(
                peak: boundaries.ionTemperature * initialProfile.temperaturePeakRatio,  // ✅ 設定値を使用
                edge: boundaries.ionTemperature,
                exponent: initialProfile.temperatureExponent  // ✅ 設定値を使用
            ),
            electronTemperature: .parabolic(
                peak: boundaries.electronTemperature * initialProfile.temperaturePeakRatio,
                edge: boundaries.electronTemperature,
                exponent: initialProfile.temperatureExponent
            ),
            electronDensity: .parabolic(
                peak: boundaries.density * initialProfile.densityPeakRatio,  // ✅ 設定値を使用
                edge: boundaries.density,
                exponent: initialProfile.densityExponent  // ✅ 設定値を使用
            ),
            currentDensity: .constant(1.0)
        )
    }
}
```

#### 2.3 SimulationPresets での使用例

**変更箇所**: `Gotenx/Models/SimulationPresets.swift`

```swift
case .constant:
    return SimulationConfiguration.build { builder in
        builder.time.start = 0.0
        builder.time.end = 2.0
        builder.time.initialDt = 1e-3

        builder.runtime.static.mesh.nCells = 100
        builder.runtime.static.mesh.majorRadius = 6.2
        builder.runtime.static.mesh.minorRadius = 2.0
        builder.runtime.static.mesh.toroidalField = 5.3

        builder.runtime.dynamic.transport = TransportConfig(
            modelType: .constant,
            parameters: [
                "chi_ion": 1.0,
                "chi_electron": 1.0,
                "particle_diffusivity": 0.1,
                "convection_velocity": 0.0
            ]
        )

        builder.runtime.dynamic.boundaries = BoundaryConfig(
            ionTemperature: 100.0,
            electronTemperature: 100.0,
            density: 2.0e19
        )

        // ✅ 追加: 初期プロファイル設定
        builder.runtime.dynamic.initialProfile = InitialProfileConfig(
            temperaturePeakRatio: 5.0,  // 数値安定性のため控えめ
            densityPeakRatio: 2.0,
            temperatureExponent: 2.0,
            densityExponent: 1.5
        )

        builder.output.saveInterval = 0.1
        builder.output.directory = "/tmp/gotenx_results"
    }

case .bohmGyroBohm:
    return SimulationConfiguration.build { builder in
        // ... 他の設定 ...

        // より現実的なプロファイル
        builder.runtime.dynamic.initialProfile = InitialProfileConfig.realistic
    }
```

### Phase 3: クリーンアップとドキュメント

#### 3.1 SimulationRunner.generateInitialProfiles() の再実装

**変更箇所**: `SimulationRunner.swift`

```swift
/// Generate initial profiles from profile conditions
///
/// **Design**: Uses ProfileConditions from configuration system instead of
/// hardcoded values. This ensures consistency with user settings.
private func generateInitialProfiles(
    mesh: MeshConfig,
    profileConditions: ProfileConditions
) throws -> CoreProfiles {
    let nCells = mesh.nCells

    // Generate radial grid
    var rNorm = [Float](repeating: 0.0, count: nCells)
    for i in 0..<nCells {
        rNorm[i] = Float(i) / Float(nCells - 1)
    }

    // Evaluate profile conditions
    var ti = [Float](repeating: 0.0, count: nCells)
    var te = [Float](repeating: 0.0, count: nCells)
    var ne = [Float](repeating: 0.0, count: nCells)

    for i in 0..<nCells {
        ti[i] = profileConditions.ionTemperature.evaluate(at: rNorm[i])
        te[i] = profileConditions.electronTemperature.evaluate(at: rNorm[i])
        ne[i] = profileConditions.electronDensity.evaluate(at: rNorm[i])
    }

    // Poloidal flux (initially zero)
    let psi = [Float](repeating: 0.0, count: nCells)

    // Create evaluated arrays
    let evaluated = EvaluatedArray.evaluatingBatch([
        MLXArray(ti),
        MLXArray(te),
        MLXArray(ne),
        MLXArray(psi)
    ])

    return CoreProfiles(
        ionTemperature: evaluated[0],
        electronTemperature: evaluated[1],
        electronDensity: evaluated[2],
        poloidalFlux: evaluated[3]
    )
}
```

#### 3.2 ProfileCondition の evaluate() メソッド追加

**変更箇所**: `ProfileConditions.swift` (新規ファイル: `swift-gotenx/Sources/GotenxCore/Configuration/ProfileConditions.swift`)

```swift
public enum ProfileCondition: Codable, Sendable, Equatable {
    case constant(Float)
    case parabolic(peak: Float, edge: Float, exponent: Float)
    case custom([Float])  // 将来の拡張用

    /// Evaluate profile at normalized radius
    ///
    /// - Parameter r: Normalized radius [0, 1]
    /// - Returns: Profile value at r
    public func evaluate(at r: Float) -> Float {
        // ✅ Validate input with clamping
        let clamped = max(0.0, min(1.0, r))

        switch self {
        case .constant(let value):
            return value

        case .parabolic(let peak, let edge, let exponent):
            let factor = pow(1.0 - clamped * clamped, exponent)
            return edge + (peak - edge) * factor

        case .custom(let values):
            guard !values.isEmpty else { return 0.0 }

            // Linear interpolation
            let index = clamped * Float(values.count - 1)
            let i = Int(index)

            if i >= values.count - 1 {
                return values.last ?? 0.0
            }

            let frac = index - Float(i)
            return values[i] * (1.0 - frac) + values[i + 1] * frac
        }
    }
}

public struct ProfileConditions: Codable, Sendable, Equatable {
    public let ionTemperature: ProfileCondition
    public let electronTemperature: ProfileCondition
    public let electronDensity: ProfileCondition
    public let currentDensity: ProfileCondition

    public init(
        ionTemperature: ProfileCondition,
        electronTemperature: ProfileCondition,
        electronDensity: ProfileCondition,
        currentDensity: ProfileCondition
    ) {
        self.ionTemperature = ionTemperature
        self.electronTemperature = electronTemperature
        self.electronDensity = electronDensity
        self.currentDensity = currentDensity
    }
}
```

**注意**: 現在 ProfileConditions 型が `DynamicConfig.swift` 内で定義されている可能性があります。その場合は、別ファイルに移動することを推奨します。

#### 3.3 ドキュメント追加

**新規ファイル**: `docs/configuration/initial-profiles.md`

内容:
- 初期プロファイル設定の使い方
- 物理的意味の説明
- 数値安定性への影響
- プリセットの選び方
- トラブルシューティング

## 実装の優先順位

### 優先度: 高（即座に対応）✅

1. **Phase 1.1**: `SimulationOrchestrator` での `dt` 使用
   - 影響範囲: 小（1箇所の変更）
   - 効果: 大（即座にユーザー設定が反映）
   - 工数: **30 minutes**
   - リスク: 低（既存の動作を維持しつつ改善）

2. **Phase 1.2**: `SimulationRunner` での `ProfileConditions` 使用
   - 影響範囲: 中（initialize と generateInitialProfiles の変更）
   - 効果: 大（設定システムが機能する）
   - 工数: **2-3 hours**
   - リスク: 低（既存の ProfileConditions インフラを活用）

**Phase 1 合計推定時間**: 3-4 hours

### 優先度: 中（次のリリースで対応）

3. **Phase 2**: `InitialProfileConfig` の追加
   - 影響範囲: 中（新規構造体と DynamicConfig への統合）
   - 効果: 中（ユーザー設定の柔軟性向上）
   - 工数: **4-6 hours**
   - リスク: 低（オプショナルフィールドでデフォルト値を提供）

### 優先度: 低（時間があれば対応）

4. **Phase 3**: クリーンアップとドキュメント
   - 影響範囲: 小（リファクタリングとドキュメント）
   - 効果: 小（保守性向上、ユーザー理解の改善）
   - 工数: **2-3 hours**
   - リスク: なし

**全 Phase 合計推定時間**: 9-13 hours

## 後方互換性

### Phase 1 の変更

- **破壊的変更なし**: 既存の設定ファイルはそのまま動作
- **デフォルト値**: 現在のハードコード値をデフォルトとして維持

### Phase 2 の変更

- **オプショナルフィールド**: `initialProfile` はデフォルト値あり
- **既存の JSON**: `initialProfile` フィールドがない場合はデフォルト使用
- **段階的移行**: 既存プリセットは徐々に更新

## テスト戦略

### Phase 1 のテスト

1. **単体テスト**:
   - `SimulationOrchestrator` が `dynamicParams.dt` を正しく使用
   - `generateInitialProfiles()` が `ProfileConditions` を正しく評価

2. **統合テスト**:
   - 各プリセットで初期プロファイルが設定通りに生成される
   - タイムステップが設定通りに使用される

3. **回帰テスト**:
   - 既存のシミュレーション結果と一致（デフォルト値使用時）

### Phase 2 のテスト

1. **設定バリデーション**:
   - 不正な値（負の値、0など）が拒否される
   - 極端な値（100×など）に警告が出る

2. **数値安定性テスト**:
   - さまざまな `InitialProfileConfig` で収束することを確認
   - 推奨範囲外の値での動作を検証

## まとめ

### ✅ 検証結果

すべての問題点を実際のコードで確認しました：
- ✅ `SimulationOrchestrator.swift:413-417` でハードコード `dt = 1e-4` を確認
- ✅ `SimulationRunner.swift:211-218` でハードコード `tiCore = tiEdge * 5.0` を確認
- ✅ `DynamicConfig.swift:102-122` の `toProfileConditions()` が未使用であることを確認

コメントの "FIXED" は過去の応急処置を示しており、根本的な設計問題は未解決です。

### 現状の問題

- ✗ 設定システムが機能していない（ハードコード値が優先）
- ✗ ユーザーが数値安定性を調整できない
- ✗ コードの保守性が低い（魔法の数値が散在）
- ✗ 応急処置（マジックナンバーの調整）の繰り返し

### 改善後の状態

- ✓ 設定システムが正しく機能する
- ✓ ユーザーが全てのパラメータを制御可能
- ✓ 物理シナリオごとに適切な初期条件を選択可能
- ✓ コードの保守性が向上（DRY 原則、単一責任原則）
- ✓ ドキュメントが充実

### 次のアクション

1. **Phase 1.1 の実装**（30 min）: `dt` の修正
   - `SimulationOrchestrator.swift:417` を `dt = max(dynamicParams.dt, 1e-5)` に変更

2. **Phase 1.2 の実装**（2-3 hours）: `ProfileConditions` の使用
   - `SimulationRunner.initialize()` で `toProfileConditions()` を呼び出し
   - `generateInitialProfiles()` を `ProfileConditions` ベースに書き換え
   - `ProfileCondition.evaluate()` メソッドの追加

3. **テストと検証**（1-2 hours）:
   - 単体テスト（profile continuity, boundary values）
   - 統合テスト（各プリセットでの動作確認）
   - 回帰テスト（既存結果との一致確認）

4. **Phase 2 の設計レビュー**（必要に応じて）

---

**ドキュメント更新日**: 2025-10-23
**ステータス**: ✅ 検証完了、実装準備完了
**推定実装時間**: 3-4 hours (Phase 1)
