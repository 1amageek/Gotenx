# Newton方向分析結果

**日付:** 2025-10-27
**設定:** nCells=75, tolerance=2e-1, dt=1.5e-4

---

## 📊 Phase 1-2 検証結果サマリー

### 🔴 重大な発見（3つ）

**1. iter=0の線形ソルバー精度問題**
```
Relative error = 1.88e-04 ⚠️ (目標: < 1e-6)
```

**2. 変数間の極端な更新量の偏り**
```
iter=0→1でTi, Teが1000倍以上縮小、neはほぼ不変
```

**3. residualの変数ごとの異常な挙動**
```
iter=0→1: Te大幅改善(82.1%)、Ti悪化(-57.6%)、ne悪化(-125.6%)
iter=1以降: Ti, Te完全停滞(0.0%)、neのみ改善(25%)
```

---

## 📋 イテレーションごとの詳細分析

### Iteration 0

**線形ソルバー精度:**
```
||J*Δ + R|| = 6.60e-03
||R|| = 3.52e+01
Relative error = 1.88e-04 ⚠️ WARNING: > 1e-6
```

**評価:** 🔴 線形ソルバーの精度不足
- 目標の1e-6に対して188倍大きい
- これが後続イテレーションの問題の原因の可能性

**降下方向:**
```
Δ·(-R) = 9.41e-02 ✅ Valid descent direction
```

**評価:** ✅ 降下方向は正しい

**Newton方向成分:**
```
||Δ_Ti||  = 2.66e-03
||Δ_Te||  = 2.66e-03
||Δ_ne||  = 1.52e-05  ← Ti, Teの175倍小さい！
||Δ_psi|| = 1.30e-07
Total ||Δ|| = 2.17e-04
```

**評価:** 🔴 neの更新量が極端に小さい
- Ti = Te (同じオーダー)
- ne: Ti, Teの1/175
- これはneのresidualが小さすぎるため

**変数別residualノルム:**
```
||R_Ti||  = 3.96e+00
||R_Te||  = 3.49e+01  ← 支配的（Tiの8.8倍、neの839倍）
||R_ne||  = 4.16e-02  ← 非常に小さい
||R_psi|| = 8.68e-04
Total ||R|| = 2.03e+00
```

**評価:** 🔴 Teが圧倒的に支配的
- Te: Tiの8.8倍、neの839倍
- residualNormはTeに支配されている
- Ti, neの残差が小さくても収束しない

**Line search:**
```
α=1.0 → residualNorm=0.510 (74.9% improvement) ✅
```

**評価:** ✅ 大幅改善

---

### Iteration 1

**線形ソルバー精度:**
```
||J*Δ + R|| = 2.94e-06
||R|| = 8.83e+00
Relative error = 3.33e-07 ✅ OK
```

**評価:** ✅ iter=1では精度OK

**降下方向:**
```
Δ·(-R) = 4.06e-06 ✅ Valid descent direction
```

**評価:** ✅ 降下方向は正しい

**Newton方向成分:**
```
||Δ_Ti||  = 2.27e-06  (前回2.66e-03から1172倍縮小！)
||Δ_Te||  = 2.32e-06  (前回2.66e-03から1147倍縮小！)
||Δ_ne||  = 1.41e-05  (前回1.52e-05からほぼ同じ)
||Δ_psi|| = 5.61e-11
Total ||Δ|| = 8.35e-07
```

**評価:** 🔴 Ti, Teの更新量が異常に縮小
- Ti: 1172倍縮小
- Te: 1147倍縮小
- ne: ほぼ不変（0.93倍）

**これは何を意味するか？**
- Ti, Teのresidualが急激に変化した
- neのresidualは安定

**変数別residualノルム:**
```
||R_Ti||  = 6.24e+00  (+57.6% 悪化！)
||R_Te||  = 6.24e+00  (-82.1% 改善！)
||R_ne||  = 9.39e-02  (+125.6% 悪化！)
||R_psi|| = 3.74e-07  (-100.0% 改善)
Total ||R|| = 5.10e-01
```

**評価:** 🔴 変数ごとの改善率が逆方向
- Te: 大幅改善（3.49e+01 → 6.24e+00、82.1%）
- Ti: **悪化**（3.96e+00 → 6.24e+00、-57.6%）
- ne: **悪化**（4.16e-02 → 9.39e-02、-125.6%）

**これは何を意味するか？**
- iter=0→1の更新はTe中心
- Teを改善する代わりにTi, neが犠牲になった
- これがiter=1以降の停滞の原因

**Line search:**
```
α=1.0 → residualNorm=0.526 (-3.2% 悪化)
α=0.25 → residualNorm=0.478 (6.2% improvement) ✅
```

**評価:** ⚠️ α=1.0で悪化、α=0.25でわずかな改善

---

### Iteration 2

**Newton方向成分:**
```
||Δ_Ti||  = 1.80e-06  (さらに縮小)
||Δ_Te||  = 1.80e-06  (さらに縮小)
||Δ_ne||  = 1.06e-05  (わずかに減少)
||Δ_psi|| = 4.32e-11
Total ||Δ|| = 6.27e-07
```

**変数別residualノルム:**
```
||R_Ti||  = 5.86e+00  (+6.2% 改善)
||R_Te||  = 5.86e+00  (+6.2% 改善)
||R_ne||  = 7.04e-02  (+25.0% 改善)
||R_psi|| = 2.88e-07  (+23.1% 改善)
Total ||R|| = 4.78e-01
```

**評価:** ⚠️ わずかな改善

**Line search:**
```
α=1.0 → residualNorm=0.525 (-9.9% 悪化)
α=0.25 → residualNorm=0.478 (0.0% 変化なし) ⚠️ 停滞開始
```

**評価:** 🔴 α=0.25でも改善ゼロ

---

### Iteration 3-5

**変数別residualノルム:**
```
iter=3:
  Ti improvement:  +0.0%  ← 完全停滞
  Te improvement:  -0.0%  ← 完全停滞
  ne improvement:  +25.2% ← neのみ改善
  psi improvement: +23.2%

iter=4:
  Ti improvement:  +0.0%  ← 完全停滞
  Te improvement:  -0.0%  ← 完全停滞
  ne improvement:  +25.0% ← neのみ改善
  psi improvement: +22.3%

iter=5:
  Ti improvement:  +0.0%  ← 完全停滞
  Te improvement:  +0.0%  ← 完全停滞
  ne improvement:  +24.8% ← neのみ改善
  psi improvement: +24.1%
```

**評価:** 🔴 Ti, Teが完全停滞、neのみ改善

**Line search:**
```
iter=3-5: α=0.25で0.0% improvement
```

**評価:** 🔴 完全停滞

---

## 🎯 根本原因の特定

### 原因1: Teのresidual支配（最重要）

**iter=0でのresidual:**
```
||R_Te|| = 3.49e+01  (支配的)
||R_Ti|| = 3.96e+00  (Teの1/8.8)
||R_ne|| = 4.16e-02  (Teの1/839)
```

**問題:**
- Total residualNormはTeに支配される
- Newton方向がTe中心になる
- Ti, neの改善が二次的になる

**結果:**
- iter=0→1でTeは大幅改善（82.1%）
- しかしTi, neが悪化（-57.6%, -125.6%）

---

### 原因2: iter=0の線形ソルバー精度不足

**iter=0:**
```
Relative error = 1.88e-04 ⚠️ (目標: < 1e-6)
```

**iter=1以降:**
```
Relative error ~ 3-5×10^-7 ✅ (目標達成)
```

**問題:**
- iter=0で大きな誤差
- これがiter=0→1の不適切な更新につながった可能性

---

### 原因3: 変数間の更新量の偏り

**iter=0:**
```
||Δ_Ti|| = 2.66e-03
||Δ_Te|| = 2.66e-03
||Δ_ne|| = 1.52e-05  ← 175倍小さい
```

**問題:**
- neの更新量が極端に小さい
- これはneのresidualが小さすぎるため

**しかし:**
- neのresidualが小さいのに、iter=0→1でneが悪化（+125.6%）
- これはTe中心の更新がneに悪影響を与えた証拠

---

### 原因4: iter=1以降のTi, Te完全停滞

**iter=1以降:**
```
Ti improvement: 0.0%
Te improvement: 0.0%
```

**なぜ？**
- iter=0→1でTiが悪化（3.96 → 6.24）
- iter=0→1でTeが大幅改善（34.9 → 6.24）
- iter=1でTi = Teになった（両方6.24）

**その後:**
- Ti = Teが均衡状態になった
- Newton方向がTi, Teをほぼ同じ比率で更新
- しかしα=0.25でも改善しない

---

## 💡 対策の方針

### Option 1: 変数別重み付け（推奨）

**方針:** residualに変数ごとの重みを適用

**実装:**
```swift
// Teの重みを下げ、Ti, neの重みを上げる
let weight_Ti = 1.0
let weight_Te = 0.1  // Teを抑える（1/10）
let weight_ne = 10.0 // neを強調（10倍）
let weight_psi = 1.0

// residualに重みを適用
let residualWeighted = MLX.concatenated([
    residual_Ti * weight_Ti,
    residual_Te * weight_Te,
    residual_ne * weight_ne,
    residual_psi * weight_psi
], axis: 0)
```

**期待される効果:**
- Teの支配を抑制
- Ti, neの改善を促進
- 変数間のバランスの取れた収束

**リスク:**
- Teの収束が遅くなる可能性
- 重みの調整が必要（試行錯誤）

---

### Option 2: 適応的重み付け

**方針:** 各変数のresidualノルムに基づいて動的に重みを調整

**実装:**
```swift
// 各変数のresidualノルムを計算
let norm_Ti = MLX.norm(residual_Ti).item(Float.self)
let norm_Te = MLX.norm(residual_Te).item(Float.self)
let norm_ne = MLX.norm(residual_ne).item(Float.self)
let norm_psi = MLX.norm(residual_psi).item(Float.self)

// 最大ノルムで正規化
let max_norm = max(norm_Ti, norm_Te, norm_ne, norm_psi)

let weight_Ti = max_norm / (norm_Ti + 1e-10)
let weight_Te = max_norm / (norm_Te + 1e-10)
let weight_ne = max_norm / (norm_ne + 1e-10)
let weight_psi = max_norm / (norm_psi + 1e-10)
```

**期待される効果:**
- 自動的にバランスを取る
- 手動調整不要

**リスク:**
- 初期イテレーションで不安定になる可能性

---

### Option 3: 変数ごとの許容誤差

**方針:** 各変数に個別の収束判定

**実装:**
```swift
// 変数ごとの許容誤差
let tolerance_Ti = 0.5
let tolerance_Te = 0.5
let tolerance_ne = 0.01
let tolerance_psi = 1e-3

// 変数ごとに収束判定
let converged_Ti = residualNorm_Ti < tolerance_Ti
let converged_Te = residualNorm_Te < tolerance_Te
let converged_ne = residualNorm_ne < tolerance_ne
let converged_psi = residualNorm_psi < tolerance_psi

let converged = converged_Ti && converged_Te && converged_ne && converged_psi
```

**期待される効果:**
- 各変数の特性に応じた収束判定
- より柔軟な収束基準

---

## 📊 データサマリー

| Metric | iter=0 | iter=1 | iter=2-5 | 評価 |
|--------|--------|--------|----------|------|
| **Linear error** | 1.88e-04 ⚠️ | 3.33e-07 ✅ | 3-5×10^-7 ✅ | iter=0問題 |
| **Descent check** | 9.41e-02 ✅ | 4.06e-06 ✅ | ~3×10^-6 ✅ | 全て正常 |
| **\|\|R_Ti\|\|** | 3.96 | 6.24 (+57.6%) | 5.86 (0.0%) | 悪化→停滞 |
| **\|\|R_Te\|\|** | 34.9 | 6.24 (-82.1%) | 5.86 (0.0%) | 改善→停滞 |
| **\|\|R_ne\|\|** | 4.16e-02 | 9.39e-02 (+125.6%) | 減少中(+25%) | 悪化→改善 |
| **\|\|Δ_Ti\|\|** | 2.66e-03 | 2.27e-06 | ~1-2×10^-6 | 1000倍縮小 |
| **\|\|Δ_Te\|\|** | 2.66e-03 | 2.32e-06 | ~1-2×10^-6 | 1000倍縮小 |
| **\|\|Δ_ne\|\|** | 1.52e-05 | 1.41e-05 | ~0.6-1×10^-5 | ほぼ不変 |
| **α (accepted)** | 1.0 | 0.25 | 0.25 | 飽和 |
| **Total \|\|R\|\|** | 2.03 | 0.510 | 0.478 | 停滞 |

---

## 🎯 最終結論

### 根本原因

**Teのresidual支配 + iter=0→1での不適切な更新**

1. **iter=0:** Teが他変数の8-800倍大きい
2. **iter=0→1:** Te中心の更新でTeは改善、Ti/neは悪化
3. **iter=1以降:** Ti, Teが均衡状態で停滞、neのみわずかに改善

### 推奨対策

**Option 1: 変数別重み付け（即実装可能）**

```swift
weight_Ti = 1.0
weight_Te = 0.1  // Teを抑える
weight_ne = 10.0 // neを強調
```

**期待される効果:**
- Teの支配を抑制
- Ti, neの改善を促進
- バランスの取れた収束

**実装推定時間:** 1-2時間

---

**最終更新:** 2025-10-27
**ステータス:** 根本原因特定完了、対策実装待ち
**次のアクション:** Option 1の実装について承認を得る
