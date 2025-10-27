# プロット機能拡張実装戦略

## 現状分析

### 実装済み
- Temperature Profiles (Ti, Te)
- Electron Density Profile (ne)
- アニメーション制御
- 表示オプション（凡例、グリッド、線の太さ）

### 利用可能だが未実装のデータ

#### Profiles (2D: [nTime, nCells])
1. **Magnetic**
   - `q`: Safety factor (無次元)
   - `magneticShear`: Magnetic shear (無次元)
   - `psi`: Poloidal flux [Wb]

2. **Transport Coefficients [m²/s]**
   - `chiTotalIon/Electron`: Total heat conductivity
   - `chiTurbIon/Electron`: Turbulent heat conductivity
   - `dFace`: Particle diffusivity

3. **Current Density [MA/m²]**
   - `jTotal`: Total current density
   - `jOhmic`: Ohmic current
   - `jBootstrap`: Bootstrap current
   - `jECRH`: ECRH-driven current

4. **Source Terms [MW/m³]**
   - `ohmicHeatSource`: Ohmic heating
   - `fusionHeatSource`: Fusion heating
   - `pICRHIon/Electron`: ICRH heating
   - `pECRHElectron`: ECRH heating

#### Scalars (1D: [nTime])
- `IpProfile`: Plasma current [MA]
- `qFusion`: Fusion gain (Q値)
- `pAuxiliary`: Auxiliary power [MW]
- `pOhmicE`: Ohmic heating power [MW]
- `pAlphaTotal`: Alpha heating power [MW]

---

## 実装戦略：段階的アプローチ

### Phase 1: プロット選択機能の基盤構築 ✅ 優先度: 最高

**目的**: ユーザーが表示するプロットを選択できる仕組みを作る

#### 1.1 PlotType列挙型の定義
```swift
enum PlotType: String, CaseIterable, Identifiable {
    // Phase 1a: 既存実装
    case temperature = "Temperature"
    case density = "Density"

    // Phase 1b: 磁場プロファイル
    case safetyFactor = "Safety Factor (q)"
    case magneticShear = "Magnetic Shear"
    case poloidalFlux = "Poloidal Flux"

    // Phase 1c: 輸送係数
    case heatConductivityIon = "Ion Heat Conductivity"
    case heatConductivityElectron = "Electron Heat Conductivity"

    // Phase 1d: 電流密度
    case currentDensity = "Current Density"

    var id: String { rawValue }
    var icon: String { ... }
    var unit: String { ... }
}
```

#### 1.2 PlotViewModelの拡張
```swift
@Observable
final class PlotViewModel {
    // 既存プロパティ
    var plotData: PlotData?
    var currentTimeIndex: Int = 0

    // 新規: プロット選択
    var selectedPlotTypes: Set<PlotType> = [.temperature, .density]
    var plotDisplayMode: PlotDisplayMode = .multiple  // .multiple or .single
}

enum PlotDisplayMode {
    case single   // 1つだけ表示
    case multiple // 選択された全て表示
}
```

#### 1.3 InspectorViewにプロット選択UIを追加
```swift
Section {
    // プロット表示モード
    Picker("Display Mode", selection: $plotViewModel.plotDisplayMode) {
        Label("Single", systemImage: "square").tag(PlotDisplayMode.single)
        Label("Multiple", systemImage: "square.grid.2x2").tag(PlotDisplayMode.multiple)
    }
    .pickerStyle(.segmented)

    // プロットタイプ選択
    List(PlotType.allCases) { plotType in
        Toggle(isOn: Binding(
            get: { plotViewModel.selectedPlotTypes.contains(plotType) },
            set: { isSelected in
                if isSelected {
                    plotViewModel.selectedPlotTypes.insert(plotType)
                } else {
                    plotViewModel.selectedPlotTypes.remove(plotType)
                }
            }
        )) {
            Label(plotType.rawValue, systemImage: plotType.icon)
        }
    }
} header: {
    Label("Plot Selection", systemImage: "chart.bar.xaxis")
}
```

**実装期間**: 2-3時間
**ファイル**: `PlotViewModel.swift`, `InspectorView.swift`

---

### Phase 2: 汎用的なプロットビューの作成 ✅ 優先度: 高

**目的**: 任意のプロファイルデータを表示できる汎用ビューを作る

#### 2.1 GenericProfilePlotViewの作成
```swift
struct GenericProfilePlotView: View {
    let plotData: PlotData
    let plotType: PlotType
    let timeIndex: Int
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            PlotHeader(
                title: plotType.rawValue,
                time: plotData.time[timeIndex],
                legendItems: plotType.legendItems,
                showLegend: showLegend
            )

            // Chart
            Chart {
                ForEach(plotType.dataFields) { field in
                    let data = extractData(field)

                    // Area fill
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        AreaMark(...)
                            .foregroundStyle(field.gradient)
                    }

                    // Line
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(...)
                            .foregroundStyle(field.color)
                    }
                }
            }
            .chartXAxisLabel("Normalized Radius ρ")
            .chartYAxisLabel(plotType.yAxisLabel)
        }
    }

    private func extractData(_ field: PlotDataField) -> [Float] {
        // KeyPathを使ってPlotDataから動的にデータ抽出
        switch field {
        case .Ti: return plotData.Ti[timeIndex]
        case .Te: return plotData.Te[timeIndex]
        case .ne: return plotData.ne[timeIndex]
        case .q: return plotData.q[timeIndex]
        // ...
        }
    }
}
```

#### 2.2 PlotDataFieldの定義
```swift
enum PlotDataField {
    case Ti, Te, ne, q, psi, jTotal
    // ...

    var color: Color { ... }
    var gradient: LinearGradient { ... }
    var label: String { ... }
}
```

**実装期間**: 3-4時間
**ファイル**: 新規 `GenericProfilePlotView.swift`, `PlotDataField.swift`

---

### Phase 3: MainCanvasViewの更新 ✅ 優先度: 高

**目的**: 選択されたプロットタイプに応じて動的に表示

#### 3.1 動的プロット生成
```swift
// MainCanvasView.swift内
ScrollView {
    VStack(spacing: 32) {
        if let plotData = plotViewModel.plotData {
            // Phase 1: 選択されたプロットタイプのみ表示
            ForEach(Array(plotViewModel.selectedPlotTypes), id: \.self) { plotType in
                GenericProfilePlotView(
                    plotData: plotData,
                    plotType: plotType,
                    timeIndex: plotViewModel.currentTimeIndex,
                    showLegend: plotViewModel.showLegend,
                    showGrid: plotViewModel.showGrid,
                    lineWidth: plotViewModel.lineWidth
                )
                .frame(height: 400)
            }
        }
    }
}
```

**実装期間**: 1-2時間
**ファイル**: `MainCanvasView.swift`

---

### Phase 4: スカラー量の時系列プロット ⚠️ 優先度: 中

**目的**: Q値、プラズマ電流などの時間発展を表示

#### 4.1 TimeSeriesPlotViewの作成
```swift
struct TimeSeriesPlotView: View {
    let plotData: PlotData
    let scalarType: ScalarPlotType
    let currentTimeIndex: Int
    let showGrid: Bool

    var body: some View {
        Chart {
            ForEach(Array(plotData.time.enumerated()), id: \.offset) { index, time in
                LineMark(
                    x: .value("Time", time),
                    y: .value(scalarType.rawValue, extractScalarData(at: index))
                )
                .foregroundStyle(scalarType.color)

                // 現在時刻のマーカー
                if index == currentTimeIndex {
                    PointMark(
                        x: .value("Time", time),
                        y: .value(scalarType.rawValue, extractScalarData(at: index))
                    )
                    .foregroundStyle(.red)
                    .symbolSize(100)
                }
            }
        }
        .chartXAxisLabel("Time [s]")
        .chartYAxisLabel(scalarType.yAxisLabel)
    }

    private func extractScalarData(at index: Int) -> Float {
        switch scalarType {
        case .qFusion: return plotData.qFusion[index]
        case .plasmaCurrent: return plotData.IpProfile[index]
        case .auxiliaryPower: return plotData.pAuxiliary[index]
        // ...
        }
    }
}

enum ScalarPlotType: String, CaseIterable {
    case qFusion = "Fusion Gain (Q)"
    case plasmaCurrent = "Plasma Current"
    case auxiliaryPower = "Auxiliary Power"
    case ohmicPower = "Ohmic Power"

    var yAxisLabel: String { ... }
    var color: Color { ... }
}
```

**実装期間**: 2-3時間
**ファイル**: 新規 `TimeSeriesPlotView.swift`

---

### Phase 5: 高度な表示オプション ⚠️ 優先度: 低

#### 5.1 Y軸スケール（線形/対数）
```swift
enum AxisScale: String, CaseIterable {
    case linear = "Linear"
    case logarithmic = "Log"
}

// PlotViewModelに追加
var yAxisScale: AxisScale = .linear

// Chartに適用
.chartYScale(
    yAxisScale == .logarithmic ? .log : .linear
)
```

#### 5.2 時間範囲選択
```swift
// PlotViewModelに追加
var timeRange: ClosedRange<Int>?  // nil = 全範囲

// Inspectorに追加
Section {
    Toggle("Custom Time Range", isOn: $hasCustomTimeRange)

    if hasCustomTimeRange {
        HStack {
            Text("Start")
            Slider(value: $startIndex, in: 0...Double(maxIndex))
        }
        HStack {
            Text("End")
            Slider(value: $endIndex, in: 0...Double(maxIndex))
        }
    }
}
```

**実装期間**: 2-3時間
**ファイル**: `PlotViewModel.swift`, `InspectorView.swift`

---

## 実装順序（推奨）

### 即座に実装すべき（Week 1）
1. ✅ Phase 1: プロット選択機能の基盤構築
2. ✅ Phase 2: 汎用的なプロットビューの作成
3. ✅ Phase 3: MainCanvasViewの更新

**理由**: これらは相互依存しており、一度に実装することで重複作業を避けられる

### 次のイテレーション（Week 2）
4. ⚠️ Phase 4: スカラー量の時系列プロット

**理由**: プロファイルプロットとは異なるUIパターンなので、独立して実装可能

### 将来の拡張（Week 3+）
5. ⚠️ Phase 5: 高度な表示オプション

**理由**: ユーザーフィードバックを受けてから実装する方が良い

---

## 技術的な考慮事項

### パフォーマンス
- **問題**: 複数プロットを同時に表示すると重くなる可能性
- **解決策**:
  - LazyVStackを使用
  - 表示外のプロットをレンダリングしない
  - アニメーション中はレンダリング頻度を制限

### データ抽出の効率化
- **問題**: PlotDataから動的にデータを抽出する際のオーバーヘッド
- **解決策**:
  - KeyPathを使った型安全な動的アクセス
  - または Dictionary<PlotType, [[Float]]> でキャッシュ

### ライブプロット対応
- **問題**: LiveTemperaturePlotViewなどの既存実装との整合性
- **解決策**:
  - GenericProfilePlotViewをLiveデータにも対応させる
  - `PlotData?` と `SerializableProfiles?` の両方を受け取れるようにする

---

## ファイル構成（Phase 1-3完了後）

```
Gotenx/Views/
├── MainCanvasView.swift          (更新)
├── InspectorView.swift            (更新)
├── Plots/
│   ├── GenericProfilePlotView.swift   (新規)
│   ├── TimeSeriesPlotView.swift       (Phase 4)
│   ├── PlotHeader.swift               (新規)
│   └── PlotStyles.swift               (新規)
│
Gotenx/ViewModels/
└── PlotViewModel.swift            (更新)

Gotenx/Models/
├── PlotType.swift                 (新規)
├── PlotDataField.swift            (新規)
└── ScalarPlotType.swift           (Phase 4)
```

---

## 見積もり

| フェーズ | 実装時間 | テスト時間 | 合計 |
|---------|---------|----------|------|
| Phase 1 | 2-3h    | 1h       | 3-4h |
| Phase 2 | 3-4h    | 1h       | 4-5h |
| Phase 3 | 1-2h    | 1h       | 2-3h |
| **Phase 1-3 合計** | **6-9h** | **3h** | **9-12h** |
| Phase 4 | 2-3h    | 1h       | 3-4h |
| Phase 5 | 2-3h    | 1h       | 3-4h |
| **全体合計** | **10-15h** | **5h** | **15-20h** |

---

## 次のステップ

**推奨**: Phase 1から順番に実装

1. PlotType列挙型とPlotDataField列挙型を定義
2. PlotViewModelにプロット選択機能を追加
3. InspectorViewにUIを追加
4. GenericProfilePlotViewを作成
5. MainCanvasViewを更新してテスト

**開始しますか？** または戦略の修正が必要ですか？
