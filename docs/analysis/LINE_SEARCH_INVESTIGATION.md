# Line Search調査結果

**調査日:** 2025-10-27
**設定:** nCells=75, tolerance=2e-1, dt=1.5e-4, moderate profile

---

## 📊 調査結果サマリー

### 🔴 重大な発見

**Newton方向の急激な崩壊:**
- iter=0: ||Δ|| = 2.17e-04 ✅ 正常
- iter=1: ||Δ|| = 8.35e-07 🔴 **260倍縮小**
- iter=2: ||Δ|| = 6.27e-07 🔴 **さらに縮小**

**Line searchの挙動:**
- iter=0: α=1.0で74.9%改善 ✅ 正常
- iter=1以降: α=1.0で悪化、α=0.25でわずかな改善のみ ⚠️

**結論:** 問題は「αの飽和」ではなく、**Newton方向||Δ||の異常な縮小**

---

## 📋 イテレーションごとの詳細

### Iteration 0（初回）

**状態:**
```
residualNorm: 2.03
xScaled range: [0.0, 1.5]
residualScaled range: [-0.513, 4.419]

residualScaled成分:
  Ti: [-0.513, 0.987]
  Te: [3.675, 4.419]  ← 支配的
  ne: [-0.003, 0.025]
```

**Jacobian:**
```
κ = 3.36e+04
σ_max = 3.52e+07
σ_min = 1.05e+03  ✅ 特異ではない

J_TiTi: [0.0, 1.76e+07]
J_TeTe: [0.0, 1.76e+07]
J_nene: [0.0, 6526]
```

**Newton方向:**
```
||Δ|| = 2.17e-04
Δ range: [-4.03e-04, 2.16e-06]
```

**Line search:**
```
α=1.0 → residualNorm=0.510 (74.9% improvement) ✅ Accepted
```

**評価:** ✅ すべて正常

---

### Iteration 1

**状態:**
```
residualNorm: 0.510 (前回から74.9%改善)
xScaled range: [6.555e-11, 1.4997]  ← 最小値が0→6e-11
```

**Jacobian:**
```
κ = 3.36e+04 (変化なし)
σ_max = 3.52e+07
σ_min = 1.05e+03 (変化なし)
```

**Newton方向:**
```
||Δ|| = 8.35e-07  🔴 前回の2.17e-04から260倍縮小！
Δ range: [-1.96e-06, 1.79e-06]
```

**Line search:**
```
α=1.0 → residualNorm=0.526 (-3.2% 悪化)
α=0.5 → residualNorm=0.569 (-11.6% 悪化)
α=0.25 → residualNorm=0.478 (6.2% improvement) ✅ Accepted
```

**評価:** 🔴 ||Δ||の異常な縮小、α=1.0で悪化

---

### Iteration 2

**状態:**
```
residualNorm: 0.478
xScaled range: [6.049e-11, 1.4997]  ← ほぼ変化なし
```

**Jacobian:**
```
κ = 3.36e+04 (変化なし)
```

**Newton方向:**
```
||Δ|| = 6.27e-07  🔴 さらに縮小
Δ range: [-1.48e-06, 1.36e-06]
```

**Line search:**
```
α=1.0 → residualNorm=0.525 (-9.9% 悪化)
α=0.5 → residualNorm=0.541 (-13.1% 悪化)
α=0.25 → residualNorm=0.478 (0.0% 変化なし) ⚠️ 停滞開始
```

**評価:** 🔴 ||Δ||さらに縮小、α=0.25でも改善ゼロ

---

## 🔬 詳細分析

### 1. Newton方向の崩壊

**観測された現象:**

| Iteration | ||Δ|| | 前回比 | 評価 |
|-----------|-------|--------|------|
| 0 | 2.17e-04 | - | ✅ 正常 |
| 1 | 8.35e-07 | 1/260 | 🔴 異常 |
| 2 | 6.27e-07 | 0.75 | 🔴 さらに縮小 |

**問題:**
- iter=0→1で||Δ||が**260倍**縮小
- Jacobianの条件数κは変化していない（3.36e+04で一定）
- σ_minも健全（1.05e+03）

**仮説:**

#### 仮説A: residualが小さすぎる？
```
iter=0: residualNorm = 2.03 → Δ = 2.17e-04
iter=1: residualNorm = 0.510 → Δ = 8.35e-07
```

比率: 2.03/0.510 = 4倍の減少
||Δ||: 2.17e-04 / 8.35e-07 = 260倍の減少

**不整合:** residualの減少（4倍）に対して||Δ||の減少（260倍）が大きすぎる

#### 仮説B: 線形システムの精度問題

線形ソルバーが返すΔは `J * Δ = -R` を満たすはずだが、
実際に満たしているか未確認。

**要確認:** `||J*Δ + R|| / ||R||` < 1e-6?

#### 仮説C: Jacobianの品質劣化

iter=1では状態が変化してJacobianの構造が変わった可能性：
- 条件数κは同じだが、成分の分布が変わった？
- 特定の変数（Te?）の感度が極端に小さくなった？

---

### 2. Line searchでのα=1.0失敗

**iter=0 vs iter=1の比較:**

| Iteration | α=1.0の結果 | 評価 |
|-----------|-------------|------|
| 0 | 74.9% improvement | ✅ 成功 |
| 1 | -3.2% (悪化) | ❌ 失敗 |
| 2 | -9.9% (悪化) | ❌ 失敗 |

**パターン:**
- iter=0: 大きなΔ (2.17e-04) × α=1.0 → 成功
- iter=1: 小さなΔ (8.35e-07) × α=1.0 → 失敗

**仮説:**

#### 仮説D: Newton方向の向きが間違っている

もしΔの**向き**が降下方向でない場合：
```
Δ · (-gradient) < 0  ← 降下方向ではない
```

α=1.0で残差が悪化するのは、方向が間違っているから？

**要確認:**
- `Δ · (-R)` > 0か？（降下性）
- Gradientの計算（residual = R なので -R が降下方向）

#### 仮説E: 非線形性が強い領域

iter=0で大きく動いた結果、非線形性の強い領域に入った？
- 解の近傍では線形近似が有効
- 遠い場所では線形近似が破綻

しかし、iter=1のΔは非常に小さい（8.35e-07）ので、
線形近似が破綻するほど動いていないはず。

---

### 3. residualScaledの成分分析

**iter=0のresidual成分:**

```
Ti: [-0.513, 0.987]   → max = 0.987
Te: [3.675, 4.419]    → max = 4.419  ← 支配的
ne: [-0.003, 0.025]   → max = 0.025
```

**スケール比:**
```
Te / Ti = 4.419 / 0.987 = 4.5倍
Te / ne = 4.419 / 0.025 = 177倍
```

**問題:**
- Te（電子温度）の残差が他の変数より1-2桁大きい
- residualNormはTe成分に支配されている
- Ti, neの残差は小さいが、Teが収束していない

**物理的解釈:**
- Te方程式に大きなソース項（加熱源）があるため残差が大きい？
- Ti, neは比較的バランスしているがTeだけ不均衡？

---

### 4. xScaledの範囲分析

**各イテレーションでのxScaled:**

```
iter=0: [0.0, 1.5]
iter=1: [6.555e-11, 1.4997]
iter=2: [6.049e-11, 1.4997]
```

**最小値の変化:**
```
iter=0: 0.0
iter=1: 6.555e-11  ← ほぼゼロだが厳密にはゼロではない
iter=2: 6.049e-11
```

**推測:**
- 最小値はpsi（ポロイダル磁束）の境界値？
- 境界条件 psi=0 が設定されているが、数値的にゼロではない
- 6e-11は浮動小数点誤差の範囲

**最大値の変化:**
```
iter=0: 1.5     (Tiのピーク値、1500 eV / 1000 eV = 1.5)
iter=1: 1.4997  ← わずかに減少
iter=2: 1.4997  ← ほぼ変化なし
```

**観測:**
- iter=0→1で Tiピーク値が 1.5 → 1.4997（0.02%減少）
- これは物理的には 1500 eV → 1499.7 eV（0.3 eV減少）
- 非常に小さな変化

---

## 🎯 根本原因の仮説

### 最有力仮説: Newton方向の精度劣化

**証拠:**
1. ✅ Jacobian自体は健全（κ=3.36e+04、σ_min=1.05e+03）
2. ✅ 線形ソルバーは成功している（Direct solver succeeded）
3. 🔴 しかし||Δ||が異常に小さい
4. 🔴 α=1.0で悪化する

**可能性のある原因:**

#### 原因1: residualの成分バランス

Te残差が支配的（177倍）:
```
Te: 4.419
ne: 0.025
```

Jacobianを解く際、Te成分が支配的だと：
- Δの更新がTe中心になる
- Ti, neの更新が不十分
- 全体として収束が遅い

#### 原因2: Jacobian成分のスケール差（2700倍）

レビューでは「物理的に妥当」と指摘されたが、
実際の収束には影響している可能性：

```
J_TiTi ~ 1.76e+07
J_nene ~ 6.5e+03
比率: 2700倍
```

→ Ti方向の感度が高く、ne方向の感度が低い
→ Ti中心の更新になり、neが取り残される？

#### 原因3: スケーリングの不均一

referenceStateスケーリング:
```
Ti: 1000 eV
Te: 1000 eV
ne: 1e+20 m⁻³
```

しかしresidualには不均一:
```
residual_Ti: O(1)
residual_Te: O(4)  ← 4倍大きい
residual_ne: O(0.01)
```

→ referenceStateスケーリングはxには有効だが、residualには不十分？

---

## 📋 次の調査ステップ（レビュー依頼）

### Phase 1: Newton方向の妥当性検証

**目的:** Δの向きと大きさが妥当か確認

**実装内容:**

1. **降下性の確認:**
```swift
// iter=0でのログに追加
let descent_check = (deltaScaled * (-residualScaled)).sum()
print("[NR-CHECK] Descent condition: Δ·(-R) = \(descent_check.item(Float.self))")
// Should be > 0 for valid descent direction
```

2. **線形ソルバー精度:**
```swift
let linear_residual = jacobianScaled.matmul(deltaScaled) + residualScaled
let linear_error = MLX.norm(linear_residual) / MLX.norm(residualScaled)
print("[NR-CHECK] Linear solve error: ||J*Δ + R|| / ||R|| = \(linear_error.item(Float.self))")
// Should be < 1e-6
```

3. **Δの成分分解:**
```swift
// iter=0でのΔの変数ごとの大きさ
let delta_Ti = deltaScaled[0..<nCells]
let delta_Te = deltaScaled[nCells..<(2*nCells)]
let delta_ne = deltaScaled[(2*nCells)..<(3*nCells)]

print("[NR-CHECK] ||Δ_Ti|| = \(MLX.norm(delta_Ti).item(Float.self))")
print("[NR-CHECK] ||Δ_Te|| = \(MLX.norm(delta_Te).item(Float.self))")
print("[NR-CHECK] ||Δ_ne|| = \(MLX.norm(delta_ne).item(Float.self))")
```

**期待される結果:**
- Descent condition > 0（降下方向）
- Linear error < 1e-6（線形ソルバー精度）
- Δの成分バランス確認

---

### Phase 2: residual成分の追跡

**目的:** Te残差が支配的な理由を特定

**実装内容:**

1. **residualの変数ごとのノルム:**
```swift
// 各イテレーションで
let residualNorm_Ti = MLX.norm(residual_Ti).item(Float.self)
let residualNorm_Te = MLX.norm(residual_Te).item(Float.self)
let residualNorm_ne = MLX.norm(residual_ne).item(Float.self)

print("[NR-RESIDUAL] ||R_Ti|| = \(residualNorm_Ti)")
print("[NR-RESIDUAL] ||R_Te|| = \(residualNorm_Te)")
print("[NR-RESIDUAL] ||R_ne|| = \(residualNorm_ne)")
print("[NR-RESIDUAL] Total = \(residualNorm)")
```

2. **改善率の変数ごと追跡:**
```swift
// iter=1での各変数の改善率
let improvement_Ti = (residualNorm_Ti_old - residualNorm_Ti) / residualNorm_Ti_old
print("[NR-RESIDUAL] Ti improvement: \(improvement_Ti * 100)%")
// Te, neも同様
```

**期待される結果:**
- Teだけ収束が遅いのか確認
- Ti, neは収束しているがTeが停滞？

---

### Phase 3: α=1.0失敗の詳細調査

**目的:** なぜα=1.0で悪化するか特定

**実装内容:**

1. **α=1.0でのresidual成分:**
```swift
// Line search内で
if alpha == 1.0 && iter > 0 {
    // α=1.0での各変数のresidual
    print("[LS-DETAIL] α=1.0: residual_Ti range")
    print("[LS-DETAIL] α=1.0: residual_Te range")
    print("[LS-DETAIL] α=1.0: residual_ne range")
}
```

2. **予測 vs 実際:**
```swift
// 1次近似での予測: f(x + Δ) ≈ f(x) + ∇f·Δ
let predicted_improvement = (residualScaled * deltaScaled).sum()
print("[NR-PREDICT] Predicted Δf = \(predicted_improvement.item(Float.self))")
// 実際の改善と比較
```

**期待される結果:**
- どの変数が悪化しているか特定
- 線形近似の有効性確認

---

## 💡 対策の方向性（仮説）

### Option A: residual成分ごとの重み付け

**もしTe残差が支配的なら:**

```swift
// residualに変数ごとの重みを適用
let weight_Ti = 1.0
let weight_Te = 0.25  // Teを抑える
let weight_ne = 1.0

let residualWeighted = concat([
    residual_Ti * weight_Ti,
    residual_Te * weight_Te,
    residual_ne * weight_ne,
    residual_psi
])
```

**期待効果:**
- Te残差の影響を抑え、Ti, neもバランスよく収束

**リスク:**
- Teの収束が遅くなる可能性
- 物理的な妥当性の検証が必要

---

### Option B: 適応的ダンピング

**もしα=1.0が大きすぎるなら:**

```swift
// Newton方向の大きさに基づいて初期αを調整
let adaptive_alpha = min(1.0, 1e-3 / deltaNorm)
```

**期待効果:**
- iter=1以降でも適切なαから開始
- 過度な更新を防ぐ

---

### Option C: Trust-Region法への切り替え

**もしLine searchが本質的に不適切なら:**

Trust-Region法:
```
min ||Δ||  s.t. ||J*Δ + R|| ≤ ε and ||Δ|| ≤ trust_radius
```

**期待効果:**
- Δの大きさを直接制御
- αの飽和問題を回避

**デメリット:**
- 実装が複雑
- trust_radiusの調整が必要

---

## 📊 データサマリー

| Metric | iter=0 | iter=1 | iter=2 | 評価 |
|--------|--------|--------|--------|------|
| residualNorm | 2.03 | 0.510 | 0.478 | ⚠️ 停滞傾向 |
| \|\|Δ\|\| | 2.17e-04 | 8.35e-07 | 6.27e-07 | 🔴 異常縮小 |
| α (accepted) | 1.0 | 0.25 | 0.25 | ⚠️ 飽和 |
| κ | 3.36e+04 | 3.36e+04 | 3.36e+04 | ✅ 安定 |
| residual_Te (max) | 4.419 | ? | ? | ⚠️ 支配的 |

---

## 🔗 関連ドキュメント

- **PRECONDITIONER_SUSPENDED_REVIEW.md** - Preconditioner保留の理由
- **INVESTIGATION_RESULTS.md** - Jacobianスケール差の調査
- **NEWTON_SOLVER_STATUS.md** - 全体ステータス

---

**最終更新:** 2025-10-27
**ステータス:** 根本原因の仮説特定、次の調査ステップをレビュー待ち
**優先度:** 最高（収束問題の根本原因）
**次のアクション:** Phase 1-3のログ実装について承認を得る
