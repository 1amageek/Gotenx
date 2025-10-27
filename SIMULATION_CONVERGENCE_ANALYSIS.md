# シミュレーション収束問題の診断レポート

**作成日：** 2025-10-27
**対象：** Gotenx App + swift-gotenx
**問題：** Newton-Raphsonソルバーの収束が極端に遅い

---

## 🔍 問題の症状

### コンソールログに表示される現象

```
[DEBUG-NR] iter=0: residualNorm=1.58e+00, tolerance=1.00e-06
[DEBUG-NR] iter=1: residualNorm=5.56e-01, tolerance=1.00e-06  (2.8× 減少)
[DEBUG-NR] iter=2: residualNorm=5.10e-01, tolerance=1.00e-06  (1.09× 減少)
[DEBUG-NR] iter=3: residualNorm=4.85e-01, tolerance=1.00e-06  (1.05× 減少)
...（収束が停滞）
```

### 各イテレーションの時間

```
[DEBUG-NR] iter=0: iteration complete in 9.74s
[DEBUG-NR] iter=1: iteration complete in 9.60s
[DEBUG-NR] iter=2: iteration complete in 10.46s
```

- **Jacobian計算：** 約9.5秒（200回のvjp呼び出し × 0.05秒）
- **線形ソルバー：** 約0.01秒
- **Line search：** 約0.04秒

### 表示される警告（これは正常）

```
[SPATIAL-OP] ⚠️  fluxDivergence: [-1.6554252e+23, 1.607544e+23] eV/(m³·s)
[SPATIAL-OP] ⚠️  source: [-4.3443168e+22, 0.0] eV/(m³·s)
```

**注意：** これらの大きな値は**正規化前の物理的に正しい値**であり、オーバーフローではありません。

---

## 📊 根本原因の分析

### 1. 収束許容値が厳しすぎる ⚠️ 致命的

**現状：**
```swift
solverTolerance: solver.tolerance ?? 1e-6  // StaticConfig.swift:73
```

**問題：**
- `tolerance = 1e-6` は物理シミュレーションとして非常に厳しい
- 現在の`residualNorm = 5.1e-01` から到達するには数百回のイテレーションが必要
- 1イテレーション10秒 × 数百回 = **数時間〜数日**

**証拠：**
```
Gap: 5.1e-01 / 1e-06 = 510,000× （許容値まで51万倍の距離）
```

### 2. 完全にフラットな初期プロファイル ⚠️ 重大

**現状：**
```swift
builder.runtime.dynamic.initialProfile = InitialProfileConfig.flat
```

**flat の定義：**
```swift
temperaturePeakRatio: 1.0,  // コア = エッジ（勾配ゼロ）
densityPeakRatio: 1.0,       // コア = エッジ（勾配ゼロ）
```

**問題：**
- 初期プロファイルが完全にフラット → ソルバーが急峻な勾配を「発見」する必要がある
- 勾配が急激に変化 → 拡散フラックス `-χ∇T` が大きくなる
- 大きなフラックス変化 → Jacobianの条件数が悪化
- 条件数が悪い → Newton収束が遅い

**証拠（ログより）：**
```
[INIT-PROFILES] Ti range: [1000.0, 1000.0] eV  ← 完全にフラット
[INIT-PROFILES] Te range: [1000.0, 1000.0] eV  ← 完全にフラット
```

初期状態では勾配ゼロ → 1ステップ目で急激な勾配が発生 → 残差が大きくなる

### 3. タイムステップが大きい 🔶 中程度

**現状：**
```swift
builder.time.initialDt = 7e-4  // 0.7ms
```

**問題：**
- 初期プロファイルがフラット → 1ステップで大きな変化が必要
- `(T_new - T_old) / dt` が大きい → 残差が大きい
- 残差が大きい → 収束に時間がかかる

**望ましい状態：**
- 初期は小さなdtで徐々に変化させる
- プロファイルが確立した後は大きなdtで効率化
- → **適応タイムステッピング**が必要

### 4. eval()は正しく実装済み ✅ 問題なし

**確認箇所：** `FlattenedState.swift:395`

```swift
eval(vjpResult[0])  // ✅ グラフ蓄積を防ぐ
```

**結果：**
- vjpイテレーションが一定の時間（0.05秒）で実行されている
- グラフ蓄積による指数的遅延は発生していない

### 5. 空間演算子の大きな値 ✅ 正常

**ログより：**
```
fluxDivergence: ~10²³ eV/(m³·s)
source: ~10²² eV/(m³·s)
```

**これは正常です：**

1. **正規化前の物理値**（NewtonRaphsonSolver.swift:466-469で正規化）
2. **正規化後：** `10²³ / n_e(2×10¹⁹) = 10⁴ eV/s`（扱いやすいスケール）
3. **ジオメトリ：** `Jacobian = 2πR₀ = 38.96 m` ✓（正しい）
4. **メッシュ：** `dx = a/nCells = 0.04 m` ✓（正しい）

---

## 🎯 解決策の優先順位

### 高優先度（Phase 0で実装）

| 対策 | 影響 | 実装難易度 | 期待効果 |
|-----|------|-----------|---------|
| **tolerance緩和** | 致命的 | 簡単 | 収束回数が数百→10回に激減 |
| **初期プロファイル変更** | 重大 | 簡単 | Jacobian条件数が改善 |
| **適応dt有効化** | 重大 | 簡単 | 総ステップ数が大幅減少 |
| **短時間検証** | - | 簡単 | 5-10分で動作確認 |

### 中優先度（Phase 1-2で実装）

- 段階的なtolerance厳密化（1e-2 → 1e-3 → 5e-4）
- より現実的な初期プロファイル（conservative → default）
- maxIterationsの最適化

### 低優先度（Phase 3：将来）

- NumericalTolerances有効化（物理的閾値）
- vjpバッチ化
- 反復線形ソルバー活用

---

## 📈 改善効果の見積もり

### Phase 0実装による効果

**変更前（予測）：**
```
tolerance: 1e-6
initialProfile: flat
適応dt: なし
→ 収束まで数百イテレーション × 10秒 = 数時間〜数日
```

**Phase 0実装後：**
```
tolerance: 1e-2（100倍緩い）
initialProfile: conservative（適度な勾配）
適応dt: 有効（自動最適化）
→ 収束まで10-15イテレーション × 10秒 = 2-3分/ステップ
→ 総14ステップ × 2-3分 = 5-10分
```

**改善率：** 数時間〜数日 → **5-10分**（約100倍高速化）

### Phase 2到達時の効果

```
tolerance: 5e-4（物理的精度を確保）
適応dt: 効果的に機能
→ Newton 5-8回/ステップ
→ 総400-600ステップ（適応dtにより最適化）
→ 総計算時間: 3-5時間で2秒シミュレーション完了
```

---

## 🔬 技術的詳細

### Newton-Raphson収束の理論

**収束条件：**
```
||R(x^{k+1})|| < tolerance
```

**収束率（理想的な場合）：**
```
||R^{k+1}|| ≈ C × ||R^k||²  （二次収束）
```

**現在の収束率（ログより）：**
```
iter 0→1: 1.58 → 0.56 (0.35× = 二次収束相当)
iter 1→2: 0.56 → 0.51 (0.91× = 停滞！)
iter 2→3: 0.51 → 0.48 (0.94× = さらに停滞)
```

→ **二次収束が機能していない** → Jacobianの条件数が悪い

### Jacobian条件数の問題

**条件数の定義：**
```
κ(J) = ||J|| × ||J^{-1}||
```

**悪い条件数の影響：**
- 小さな入力変化 → 大きな出力変化
- 線形ソルバーの精度低下
- Newton方向が不正確になる
- 収束が遅い、または発散

**flatプロファイルの問題：**
- 初期勾配ゼロ → 1ステップ目で急激な勾配発生
- 急激な変化 → フラックス項が大きく変化
- 大きな変化 → Jacobianの要素が極端な値を持つ
- → 条件数が悪化

**conservativeプロファイルの利点：**
- 初期から適度な勾配（3×, 1.5×）
- 勾配が徐々に変化
- フラックス項の変化が穏やか
- → Jacobianの条件数が改善

### 適応タイムステッピングの効果

**アルゴリズム（CFL条件ベース）：**
```
// 拡散のCFL条件
dt_diffusion = safetyFactor * dr^2 / χ_max

// 対流のCFL条件
dt_convection = safetyFactor * dr / |v_max|

// 小さい方を採用
dt = min(dt_diffusion, dt_convection)

// クランプ
dt = clamp(dt, min: minDt, max: maxDt)
```

**効果：**
- Transport係数（χ）が大きい → dt自動的に小さくなる → 安定化
- Transport係数（χ）が小さい → dt自動的に大きくなる → 効率化
- 物理的制約（CFL条件）を常に満たす → 数値安定性

**総ステップ数への影響：**
```
固定dt=7e-4:  2.0秒 / 7e-4秒 = 2,857ステップ
適応dt:       CFL条件により変動、transport係数に依存
              - 高χ領域：dtが小さくなる
              - 低χ領域：dtが大きくなる
              - 平均的には固定dtより効率的（推定：1000-2000ステップ）
```

注：実際のステップ数はtransport係数の空間分布に強く依存します。

---

## 📝 Phase 0実装の詳細

### 変更内容（SimulationPresets.swift）

```diff
- builder.time.end = 2.0
+ builder.time.end = 0.01  // 10ms（短時間検証）

+ builder.time.adaptive = AdaptiveTimestepConfig(
+     minDt: 1e-5,
+     minDtFraction: nil,
+     maxDt: 1e-3,
+     safetyFactor: 0.9,
+     maxTimestepGrowth: 1.2
+ )
+ // CFL条件: dt = 0.9 * dr^2 / χ_max

+ builder.runtime.static.solver = SolverConfig(
+     type: "newtonRaphson",
+     tolerance: 1e-2,  // 100倍緩い
+     maxIterations: 30,
+     tolerances: nil,
+     physicalThresholds: nil
+ )

- builder.runtime.dynamic.initialProfile = InitialProfileConfig.flat
+ builder.runtime.dynamic.initialProfile = .conservative

- builder.output.saveInterval = 0.1
+ builder.output.saveInterval = 0.002  // 10msで5スナップショット
```

### 期待される動作

**ステップ1-3（初期）：**
```
dt=7e-4（初期値）, Newton 15-20回 → 残差減少が遅い
χ（transport係数）が決定される
→ CFL条件により dt自動調整（例: χが大きければ dt→3e-4）
```

**ステップ4-10（安定化）：**
```
dt=CFL条件により決定, Newton 10-15回 → 残差が安定して減少
transport係数が変化 → dtも自動的に追従
```

**ステップ11-14（後期）：**
```
dt=CFL条件により決定（maxDt=1e-3以下）
Newton 8-12回 → 収束が安定
```

注：実際のdtはtransport係数（χ）に依存し、Newton収束回数とは無関係です。

**最終結果（期待値）：**
- 総ステップ数：14-20ステップ（CFL条件により変動）
- 平均Newton収束：10-15回
- 総計算時間：5-15分（Newton収束速度に依存）
- プロット表示：成功

---

## ✅ 検証項目

### Phase 0実行時に確認すべき項目

#### 1. 収束成功（必須）

```bash
# ログで以下を検索
grep "CONVERGED" console.log
# → 全ステップで表示されるべき

grep "Max iterations" console.log
# → 表示されないべき
```

#### 2. Newton収束回数（目標値）

```bash
# 最終5ステップの平均を計算
# 目標: < 15回
```

#### 3. 数値安定性（必須）

```bash
grep "NaN\|Inf" console.log
# → 表示されないべき
```

#### 4. dtの適応（期待動作）

```bash
# dtが変化していることを確認
grep "dt=" console.log | tail -10
# → 値が変動しているべき
```

#### 5. UIプロット（視覚確認）

- [ ] 温度プロットが物理的に妥当
- [ ] 密度プロットが物理的に妥当
- [ ] 負の値や極端な値がない

---

## 🚨 トラブルシューティング

### ケース1: Phase 0でも収束しない

**症状：**
```
⚠️ Max iterations reached without convergence!
```

**診断：**
1. 最終残差を確認
   ```
   Final residualNorm: X.XXe-XX
   ```

2. toleranceとのギャップ
   ```
   Gap: residualNorm / tolerance
   ```

**対策：**

- Gap < 10倍 → toleranceをさらに緩める（5e-2）
- Gap > 100倍 → 初期プロファイルをflatに戻す + dt半減
- Gap > 1000倍 → swift-gotenxのソルバー実装に根本的問題

### ケース2: 計算時間が予想以上にかかる

**症状：** 10分経過しても完了しない

**診断：**
1. 現在のステップ数を確認
2. 1ステップあたりの時間を計算

**対策：**

- Newton 20回以上/ステップ → maxIterations削減（30→20）
- dt変化なし → adaptive設定の見直し
- ステップ数が14以上 → time.end短縮（0.01→0.005）

### ケース3: プロットが物理的に不自然

**症状：** 負の温度、極端な値

**診断：**
ログで以下を確認：
```
[DEBUG-NR-INIT] Initial profiles:
  Ti: min=XXX, max=XXX
```

**対策：**

- 負の値 → densityClamping確認（NewtonRaphsonSolver.swift:140）
- 極端な値 → tolerance厳しくする（1e-2→5e-3）

---

**最終更新：** 2025-10-27
**バージョン：** Phase 0診断レポート
