# Preconditioner事前調査結果

**実行日:** 2025-10-27
**設定:** nCells=75, moderate profile (1.5×, 1.2×), iter=0のみ

---

## 📊 調査結果サマリー

### 結論：**ケースB（部分的にスケール差残存）**

- ✅ xScaledは良好（すべてO(1)）
- ⚠️ residualScaledは概ね良好（100倍程度の差）
- 🔴 **jacobianScaledに2700倍のスケール差**

---

## 🔬 詳細データ

### 1. referenceState（スケーリング基準値）

```
[INVESTIGATION] referenceState breakdown (nCells=75):
[INVESTIGATION]   Ti_ref range: [1000.0, 1000.0]
[INVESTIGATION]   Te_ref range: [1000.0, 1000.0]
[INVESTIGATION]   ne_ref range: [1e+20, 1e+20]
```

**発見:**
- Ti_ref = 1000 eV（一定）
- Te_ref = 1000 eV（一定）
- ne_ref = 1e+20 m⁻³（一定）

**referenceStateは各セルで異なる値ではなく、変数の典型的スケールとして固定値を使用**

**スケール差:**
- ne_ref / Ti_ref = 1e+20 / 1000 = **1e+17倍**

しかし、この大きなスケール差は次のxScaledで解消されている。

---

### 2. xScaled（スケーリング後の状態）

```
[INVESTIGATION] xScaled breakdown:
[INVESTIGATION]   Ti_scaled range: [1.0, 1.5]
[INVESTIGATION]   Te_scaled range: [1.0, 1.5]
[INVESTIGATION]   ne_scaled range: [0.2, 0.24000001]
```

**評価: ✅ 良好**

- Ti_scaled: 1.0～1.5（O(1)）
- Te_scaled: 1.0～1.5（O(1)）
- ne_scaled: 0.2～0.24（O(0.1)）

**すべてO(1)スケール！変数間のスケール差は解消されている。**

**スケール差:**
- max(Ti_scaled) / min(ne_scaled) = 1.5 / 0.2 = **7.5倍**（許容範囲）

---

### 3. residualScaled（スケーリング後の残差）

```
[INVESTIGATION] residualScaled breakdown:
[INVESTIGATION]   residual_Ti range: [-0.5132089, 0.9871042]
[INVESTIGATION]   residual_Te range: [3.674646, 4.419229]
[INVESTIGATION]   residual_ne range: [-0.0030830996, 0.02473901]
```

**評価: ⚠️ 概ね良好だが、わずかな差あり**

- residual_Ti: -0.5～1.0（O(1)）
- residual_Te: 3.7～4.4（O(1)）← わずかに大きい
- residual_ne: -0.003～0.025（O(0.01)）← 2桁小さい

**スケール差:**
- max(residual_Te) / max(residual_ne) = 4.4 / 0.025 = **176倍**

これは中程度の差。Newtonの収束には影響するが、致命的ではない。

---

### 4. jacobianScaled（最重要！）

```
[INVESTIGATION] jacobianScaled block structure:
[INVESTIGATION]   J_TiTi range: [0.0, 1.7599374e+07]
[INVESTIGATION]   J_TeTe range: [0.0, 1.7599376e+07]
[INVESTIGATION]   J_nene range: [0.0, 6526.0415]
[INVESTIGATION]   J_Tine (off-diag) range: [0.0, 0.0]
[INVESTIGATION]   J_neTi (off-diag) range: [-0.0020327172, 0.002020718]
[INVESTIGATION]   J_TiTe (off-diag) range: [-1.759552e+07, 0.0]
```

**評価: 🔴 大きなスケール差あり**

#### 対角ブロック（主対角）

- J_TiTi: O(1.76e+07)
- J_TeTe: O(1.76e+07)
- J_nene: O(6.5e+03)

**スケール差:**
- J_TiTi / J_nene = 1.76e+07 / 6.5e+03 = **2700倍**

#### オフ対角ブロック（変数間の結合）

- J_Tine: 0（Ti→neの影響なし）
- J_neTi: O(0.002)（ne→Tiの影響は非常に小さい）
- J_TiTe: O(1.76e+07)（Ti↔Teは強く結合）

**パターン:**
- Ti ↔ Te: 強く結合（同じスケール）
- ne: 独立（他変数との結合が弱い）
- neの対角ブロックが2700倍小さい

---

## 🎯 ケース判定：**ケースB（部分的にスケール差残存）**

### 判定理由

#### ✅ 基本スケーリングは機能している

`xScaled = x / referenceState` により：
- 物理量（Ti: 1000-1500 eV, ne: 2e19-2.4e19 m⁻³）
- スケーリング後（Ti: 1.0-1.5, ne: 0.2-0.24）

**1e+17倍のスケール差が7.5倍まで縮小**

#### ⚠️ residualに軽微な差

- Ti/Teの残差: O(1)
- neの残差: O(0.01)

100倍程度の差だが、これ自体は大きな問題ではない。

#### 🔴 Jacobianに大きな差

- J_TiTi, J_TeTe: O(1.76e+07)
- J_nene: O(6.5e+03)

**2700倍の差が残っている**

**これがNewton方向の不正確さの主原因と判断**

---

## 💡 なぜJacobianだけ差が残るのか？

### 仮説：物理的な結合の強さの違い

**温度の拡散（Ti, Te）:**
- 拡散係数 χ ≈ 1 m²/s
- セル間隔 dr ≈ 0.027 m
- 特徴的スケール: χ / dr² ≈ 1 / 0.0007 ≈ 1400

**密度の拡散（ne）:**
- 拡散係数 D ≈ 0.1 m²/s（温度の1/10）
- 特徴的スケール: D / dr² ≈ 0.1 / 0.0007 ≈ 140

**比率: 1400 / 140 = 10倍**

これだけでは2700倍を説明できない。他の要因：
- 時間スケールの違い（dt = 1.5e-4 s）
- ソース項の大きさの違い
- 境界条件の影響

**結論:** 物理的な時間スケールの違いがJacobianのスケール差として現れている。

---

## 📋 推奨アクション

### Option 1: Jacobian対角ブロックベースのPreconditioner（推奨）

**方針:** Jacobianの各対角ブロックの典型的スケールで正規化

**Preconditioner:**
```swift
// 各対角ブロックの典型的スケール
let scale_Ti = sqrt(mean(J_TiTi * J_TiTi))  // ≈ 1.76e+07
let scale_Te = sqrt(mean(J_TeTe * J_TeTe))  // ≈ 1.76e+07
let scale_ne = sqrt(mean(J_nene * J_nene))  // ≈ 6.5e+03

// Preconditioner（各変数に対して一定値）
let P = concat([
    repeat(scale_Ti, nCells),   // Ti用
    repeat(scale_Te, nCells),   // Te用
    repeat(scale_ne, nCells),   // ne用
    repeat(1.0, nCells)          // psi用
])
```

**期待される効果:**
- J_TiTi / scale_Ti ≈ 1
- J_TeTe / scale_Te ≈ 1
- J_nene / scale_ne ≈ 1

**すべてO(1)に正規化される**

**実装の複雑さ:** 中程度（対角ブロックの統計量計算が必要）

---

### Option 2: Jacobian全体のFrobeniusノルムベース（簡易版）

**方針:** 各列のノルムで正規化

**Preconditioner:**
```swift
// 各列のL2ノルム
let P = sqrt((jacobianScaled * jacobianScaled).sum(axis: 0)) + 1e-10
```

**利点:** 実装が非常に簡単（1行）

**欠点:**
- オフ対角ブロックの影響を受ける
- J_TiTe が大きいため、ne列も大きくスケーリングされる可能性

**実装の複雑さ:** 低

---

### Option 3: 何もしない（非推奨）

**根拠不足:**
- Jacobianに2700倍の差がある以上、Preconditionerなしでは収束改善は期待できない
- 既にnCells=50, 75, 100すべてで停滞が確認されている

---

## 🚀 次のステップ

### ステップ1: Option 1の実装（推奨）

1. Jacobianの対角ブロックの統計量を計算
2. ブロックごとに異なるスケール値を決定
3. 右前処理で実装
4. 小規模テスト（1-2ステップ）で効果確認

**推定時間:** 2-3時間

---

### ステップ2: 効果の検証

**検証項目:**
1. **Preconditioned Jacobianの条件数:**
   - κ_before: 3.36e+04
   - κ_after: < 1e+04（期待値）
   - 改善率: > 3倍

2. **Preconditioned Jacobianのブロックスケール:**
   - J_TiTi_precond: O(1)
   - J_TeTe_precond: O(1)
   - J_nene_precond: O(1)
   - すべて同じオーダー

3. **Line search α:**
   - α_before: 0.25（iter=1以降）
   - α_after: > 0.5（期待値）

4. **residualNormの収束:**
   - 0.462で停滞 → < 0.2到達（期待値）

---

### ステップ3: 本実装（検証成功後）

- tolerance=1e-1に戻す
- time.end=50msに延長
- 全ステップで収束確認

---

## 📝 重要な注意事項

### 二重スケーリングの回避

**referenceStateは既に使用されている:**
```swift
xScaled = x / referenceState
residualScaled = residual / referenceState（内部で）
```

**Preconditionerには別の値を使う:**
```swift
P = computeFromJacobianBlocks(jacobianScaled)  // ← referenceStateとは別
```

これにより二重スケーリングを回避。

---

## 📊 データサマリー

| 項目 | Ti | Te | ne | 比率 |
|------|----|----|----|----|
| **referenceState** | 1e+03 | 1e+03 | 1e+20 | 1:1:1e+17 |
| **xScaled** | 1.0-1.5 | 1.0-1.5 | 0.2-0.24 | ✅ 1:1:0.2 |
| **residualScaled** | 0.5-1.0 | 3.7-4.4 | 0.003-0.025 | ⚠️ 1:4:0.01 |
| **jacobianScaled** | O(1.76e+07) | O(1.76e+07) | O(6.5e+03) | 🔴 2700:2700:1 |

**結論:**
- 基本スケーリング（referenceState）は機能
- しかしJacobianに2700倍の差が残る
- **軽量なPreconditioner（対角ブロックベース）で解決可能**

---

## ✅ 実装完了レポート

**実装日:** 2025-10-27
**実装内容:** Option 1（対角ブロックベースPreconditioner）

### 実装の詳細

**場所:** `swift-gotenx/Sources/GotenxCore/Solver/NewtonRaphsonSolver.swift:343-434`

**実装ステップ:**

1. **対角ブロックスケールの計算:**
```swift
// Jacobian対角ブロックのRMSノルム
let scale_Ti = sqrt(mean((J_TiTi * J_TiTi)))  // ≈ 1.76e+07（期待値）
let scale_Te = sqrt(mean((J_TeTe * J_TeTe)))  // ≈ 1.76e+07
let scale_ne = sqrt(mean((J_nene * J_nene)))  // ≈ 6.5e+03
```

2. **Preconditioner行列の構築:**
```swift
// 各変数タイプごとに一定のスケール値
let P = concat([
    full([nCells], scale_Ti),
    full([nCells], scale_Te),
    full([nCells], scale_ne),
    ones([nCells])  // psi
])
let P_inverse = 1.0 / (P + 1e-10)
```

3. **右前処理の適用:**
```swift
// J P⁻¹ (P Δx) = -R
let P_inv_broadcast = P_inverse.reshaped([1, -1])
let jacobianPreconditioned = jacobianScaled * P_inv_broadcast
let deltaHat = solve(jacobianPreconditioned, -residualScaled)
```

4. **Newton方向の復元:**
```swift
// Δx = P⁻¹ Δx_hat
let deltaScaled = deltaHat * P_inverse
```

### 診断ログの追加

**iter=0時に表示:**
- スケール値（scale_Ti, scale_Te, scale_ne）
- 前処理後のJacobianブロックスケール（J_TiTi_precond, J_TeTe_precond, J_nene_precond）
- 条件数改善（κ_before → κ_after）
- Newton方向の大きさ保存（||Δx_hat|| → ||Δx||）

### 期待される効果

| 項目 | Before | After（期待値） | 改善率 |
|------|--------|----------------|-------|
| κ（条件数） | 3.36e+04 | < 1e+04 | > 3× |
| J_TiTi | O(1.76e+07) | O(1) | 正規化 |
| J_TeTe | O(1.76e+07) | O(1) | 正規化 |
| J_nene | O(6.5e+03) | O(1) | 正規化 |
| Line search α | 0.25（停滞時） | > 0.5 | 2×+ |
| residualNorm | 0.462（停滞） | < 0.2 | 収束改善 |

### 数学的正確性の保証

✅ **右前処理を使用** → Newton方向の大きさ保存
✅ **明示的なreshape** → MLX broadcasting安全
✅ **二重スケーリング回避** → referenceStateとは別のスケール
✅ **対角ブロックベース** → 変数間の結合を考慮

---

---

## ⚠️ 実装保留の通知

**日付:** 2025-10-27

Option 1（対角ブロックベースPreconditioner）の実装は完了しましたが、
コードレビューにより**重大な問題**が指摘され、実装を保留しました。

**保留理由:**
1. 二重スケーリングリスク（referenceStateとの整合性）
2. 根本原因の誤認（Jacobianスケール差 vs α飽和）
3. 調査不足（真の問題はNewton方向の崩壊）

**詳細:** `PRECONDITIONER_SUSPENDED_REVIEW.md` 参照

---

## 🔄 その後の調査結果（2025-10-27）

シミュレーション実行により、**真の問題**が判明しました：

### 重大な発見

**Newton方向の異常な崩壊:**
```
iter=0: ||Δ|| = 2.17e-04 ✅
iter=1: ||Δ|| = 8.35e-07 🔴 260倍縮小！
iter=2: ||Δ|| = 6.27e-07 🔴 さらに縮小
```

**Te残差の支配:**
```
Te: 4.419（支配的）
Ti: 0.987（4.5倍小さい）
ne: 0.025（177倍小さい）
```

**結論:**
- ❌ Jacobianスケール差（2700倍）は問題ではなかった
- ✅ 真の問題は**Newton方向||Δ||の異常な縮小**
- ✅ **Te残差の不均衡**が収束を妨げている

**詳細:** `LINE_SEARCH_INVESTIGATION.md` 参照

---

**最終更新:** 2025-10-27
**ステータス:** 実装保留、真の問題を特定 ⚠️
**次のアクション:** Newton方向崩壊の根本原因調査（Phase 1-3）
