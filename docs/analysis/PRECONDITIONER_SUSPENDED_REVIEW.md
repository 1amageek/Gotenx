# Preconditioner実装保留 - コードレビュー結果

**日付:** 2025-10-27
**ステータス:** 実装保留（SUSPENDED）
**理由:** 根本原因の誤認、二重スケーリングリスク、調査不足

---

## 📌 サマリー

対角ブロックベースPreconditioner（INVESTIGATION_RESULTS.md Option 1）の実装を完了しましたが、
コードレビューにより**重大な問題**が指摘され、実装を保留しました。

**主な問題点:**
1. ✅ Jacobianスケール差（2700倍）の過剰解釈 → 物理的に妥当な値
2. ✅ 二重スケーリングのリスク → referenceStateとの整合性問題
3. ✅ 真の問題の見落とし → Line searchのα飽和を未調査
4. ✅ 実装が時期尚早 → 段階的調査が必要

---

## 🔴 レビュー指摘事項（詳細）

### 1. Jacobianスケール差の過剰解釈

**指摘内容:**
> jacobianScaled に2700倍のスケール差があると断定している点は過剰解釈。
> 実際には J_TiTi が ~1.76×10⁷、J_nene が ~6.5×10³で約2700倍の差があるのは事実でも、
> 温度・密度方程式の物理係数が異なるため、その差自体は自然な結果。

**分析:**
```
温度拡散係数: χ ~ 1 m²/s
密度拡散係数: D ~ 0.1 m²/s
→ 拡散係数の比: 10倍

空間離散化: dr ~ 0.027 m → 1/dr² ~ 1400
時間ステップ: dt ~ 1.5e-4 s

組み合わせ: (χ/dr²) * dt ~ 1.76e-4 * 1400 = 0.25
           (D/dr²) * dt ~ 1.76e-5 * 140 = 0.0025
→ 比率: 100倍

さらに境界条件、ソース項の寄与を考慮すると、
10³～10⁴オーダーの差は物理的に妥当
```

**結論:**
- ❌ 「2700倍 = 異常 = Preconditioner必須」という結論は**早計**
- ✅ Jacobianスケール差は**物理的に説明可能**

**実際の問題:**
- Preconditionerの必要性は、αの飽和やΔの縮小から判断すべき
- Jacobianスケール差だけでは判断できない

---

### 2. 二重スケーリングのリスク（CRITICAL）

**指摘内容:**
> referenceStateは既存コード内でNewton方程式の残差・Jacobianにも反映されており、
> ここに改めてブロックベースの前処理を入れると二重スケーリングになる可能性がある。

**既存のスケーリング機構:**

```swift
// NewtonRaphsonSolver.swift:176-189
let residualFnScaled: (MLXArray) -> MLXArray = { xNewScaled in
    // ① Unscale to physical units
    let xPhysical = xScaledState.unscaled(by: referenceState)

    // ② Compute residual in physical units
    let residualPhysical = residualFnPhysical(xPhysical.values.value)

    // ③ Scale residual back
    let residualScaled = residualState.scaled(by: referenceState)

    return residualScaled.values.value
}

// Jacobian = ∂(residualScaled) / ∂(xScaled)
let jacobianScaled = computeJacobianViaVJP(residualFnScaled, xScaled.values.value)
```

**数学的問題:**

元の方程式（物理空間）:
```
J_physical * Δx_physical = -R_physical
```

referenceStateスケーリング後:
```
J_scaled * Δx_scaled = -R_scaled

where:
  x_scaled = x_physical / referenceState
  J_scaled = (∂R_physical / ∂x_physical) * (referenceState_out / referenceState_in)
  R_scaled = R_physical / referenceState
```

さらにPreconditioner P を追加すると:
```
(J_scaled * P_inv) * (P * Δx_scaled) = -R_scaled

= (J_physical * referenceState_ratio * P_inv) * (P * Δx_physical / referenceState)
```

**問題:**
- referenceStateとPの両方でスケーリング → **二重スケーリング**
- residual側にPを掛けていないため、**左辺と右辺の整合性が崩れる**

**正しいアプローチ（もし前処理が必要なら）:**
1. referenceStateスケーリングを**無効化**してPに統一、または
2. Pを「referenceState後の追加調整」として数学的に一貫させる（residual側も調整）

**結論:**
- ✅ 現在の実装は**数学的に不正確**
- ❌ residual側の整合性を取らずに列だけ割ると、解が変わる

---

### 3. 真の問題の見落とし（最重要）

**指摘内容:**
> Newton方向が縮退している主因は、Jacobianにゼロ列/ゼロ行が出ることより、
> ラインサーチが最小αに張り付いて更新量が1e-7に落ち込んでいる点にあります。

**観測されたログ（DIAGNOSTIC_RESULTS_nCells75.md）:**

```
iter=0: residualNorm: 2.03 → 0.510 (α=1.0, 74.9% improvement) ✅
iter=1: residualNorm: 0.510 → 0.478 (α=0.25, 6.2% improvement) ⚠️
iter=2: residualNorm: 0.478 → 0.478 (α=0.25, 停滞)
iter=5: residualNorm: 0.478 → 0.462 (α=0.25, 3.3% improvement)
iter=6-15: residualNorm: 0.462 (α=0.25, 完全停滞) ❌

||Δ||: iter=0 で 0.5 → iter=5 で 1e-7 まで縮小
```

**未調査の重要な問題:**

1. **なぜiter=1以降、α=1.0が採用されなくなったのか？**
   - iter=0ではα=1.0で大幅改善（74.9%）
   - iter=1以降はα=1.0で悪化する理由は？

2. **なぜα=0.25で頭打ちになるのか？**
   - Line search設定: minAlpha=0.01, 減衰率0.5
   - α=0.25は減衰3回目: 1.0 → 0.5 → 0.25
   - さらに縮めても改善しないということ？

3. **なぜNewton方向||Δ||が1e-7まで縮小したのか？**
   - Jacobianが特異に近づいている？
   - 線形ソルバーの精度問題？
   - Newton方向の**向き**は正しいのか？

**結論:**
- ❌ Preconditionerを入れても、**α=0.25固定のままなら停滞は解消しない**
- ✅ まず**なぜαが飽和するか**を調査すべき

---

### 4. Preconditioner導入のリスク

**指摘内容:**
> J_TiTi の支配的なオーダーが10⁷である原因がセル径やdtに由来するので、
> 単純に10⁷で割るとNewtonステップが極端に大きくなり、ラインサーチがさらに縮むリスクがある。

**想定されるリスク:**

現状:
```
J_TiTi ~ 1.76e+07 でバランス
→ Δx ~ O(1e-2)
→ α=0.25で停滞
```

Preconditioner後:
```
J_TiTi / 1.76e+07 ~ O(1)
→ Δx ~ O(1)?（10²倍大きくなる可能性）
→ α < 0.25でさらに縮む？
```

**結論:**
- ✅ 段階的導入が必要
- ✅ まず軽量な列ノルム前処理を試すべき
- ✅ α・residualの変化を実測してから判断

---

## ✅ 修正されたアプローチ

### Phase 1: Line Search調査（最優先）

**目的:** αが0.25で飽和する原因を特定

**調査項目:**

1. **Line search詳細ログ追加:**
```swift
// 各α試行での residualNorm を記録
α=1.0 → residualNorm=?
α=0.5 → residualNorm=?
α=0.25 → residualNorm=? (採用)
α=0.125 → residualNorm=? (試した？)
```

2. **Newton方向の妥当性確認:**
```swift
// Δの向きが正しいか？
let dot_product = (Δ · (-gradient))  // Should be positive
let descent_condition = (residualNorm_new < residualNorm_old)
```

3. **Armijo条件の確認:**
```swift
// Line searchの判定条件
f(x + α*Δ) ≤ f(x) + c₁ * α * ∇f(x)·Δ
// c₁ = 1e-4（デフォルト）が厳しすぎる？
```

**推定時間:** 2-3時間（ログ追加 + 実行 + 分析）

---

### Phase 2: Newton方向検証

**目的:** Δの大きさと向きが妥当か確認

**調査項目:**

1. **Jacobianの健全性:**
```swift
// SVD: σ_min が極端に小さくないか？
// 現状: σ_min = 1.05e+03 (健全)
```

2. **線形ソルバー精度:**
```swift
// ||J*Δ + R|| / ||R|| < 1e-6?
let residual_linear = MLX.norm(jacobian * delta + residual) / MLX.norm(residual)
```

3. **スケーリング後のΔ:**
```swift
// Δx_physical = Δx_scaled * referenceState
// 物理的に妥当な大きさか？
```

**推定時間:** 1-2時間

---

### Phase 3: 軽量前処理の試行（必要な場合のみ）

**Phase 1, 2の結果に基づいて判断**

**Option A: 列ノルムベース前処理（最軽量）**

```swift
// 各列のL2ノルムで正規化
let columnNorms = sqrt((jacobianScaled * jacobianScaled).sum(axis: 0)) + 1e-10
let P_inv = 1.0 / columnNorms
```

**利点:**
- 実装が簡単（1-2行）
- referenceStateと独立した追加調整として扱える
- 段階的に効果を測定できる

**欠点:**
- オフ対角ブロックの影響を受ける

**導入手順:**
1. 小規模テスト（1-2ステップ）
2. α、residualNormの変化を実測
3. 改善が確認されたら本実装

**推定時間:** 2-3時間（実装 + 検証）

---

## 📊 保留された実装の記録

**実装場所:** `swift-gotenx/Sources/GotenxCore/Solver/NewtonRaphsonSolver.swift:343-369`

**実装内容:**
- 対角ブロックベースPreconditioner（Option 1）
- 右前処理: `J P⁻¹ (P Δx) = -R`
- 診断ログ付き

**保留理由:**
1. 二重スケーリングのリスク（referenceStateとの整合性）
2. 根本原因の誤認（Jacobianスケール差vs α飽和）
3. 実装が時期尚早（段階的調査が必要）

**コード状態:**
- ✅ コメントアウト（警告付き）
- ✅ 元のlinearSolver.solve()に戻した
- ✅ ビルド成功

**参考として残す理由:**
- 正しいアプローチが判明した場合の参考実装
- 数学的に一貫した前処理方法の例

---

## 📋 次のステップ

### ステップ1: Line Search調査ログの追加（最優先）

**実装内容:**
- Line search各試行でのresidualNorm記録
- Newton方向の降下性確認（Δ · (-gradient) > 0）
- Armijo条件の判定過程

**推定時間:** 2時間

---

### ステップ2: 調査実行と分析

**実行:**
- nCells=75, 5-10ステップ
- iter=0とiter=1の挙動を重点的に比較

**分析:**
- なぜiter=1以降α=1.0が失敗するか
- α=0.25が限界の理由
- Newton方向の妥当性

**推定時間:** 1時間

---

### ステップ3: 対策の決定（調査結果に基づく）

**可能性のある対策:**

1. **Line search設定の調整:**
   - Armijo係数 c₁ を緩和（1e-4 → 1e-3）
   - 減衰率を変更（0.5 → 0.7）
   - maxAlphaを調整

2. **Trust-Region法への切り替え:**
   - αが飽和する問題を回避
   - Δの大きさを直接制御

3. **軽量前処理の導入:**
   - 列ノルムベース（段階的）
   - 効果を実測してから判断

**推定時間:** ケース依存（3-10時間）

---

## 📝 教訓

### 1. 物理的妥当性の確認が最優先

- ❌ 数値的な差（2700倍）を見て異常と判断
- ✅ 物理係数から期待される値を先に計算すべき

### 2. 既存機構の理解が必須

- ❌ referenceStateスケーリングの役割を軽視
- ✅ 既存のスケーリングが正しく機能しているか確認すべき

### 3. 症状と原因の区別

- ❌ Jacobianスケール差を原因と断定
- ✅ α飽和、Δ縮小が真の問題である可能性を調査すべき

### 4. 段階的アプローチの重要性

- ❌ いきなり本格的なPreconditionerを実装
- ✅ まず軽量な方法を試して効果を実測すべき

---

## 🔗 関連ドキュメント

- **INVESTIGATION_RESULTS.md** - 調査結果（Option 1の実装を推奨したが保留）
- **NEWTON_SOLVER_STATUS.md** - 全体ステータス（Phase 1に変更が必要）
- **PRECONDITIONER_INVESTIGATION.md** - 事前調査計画（Phase追加が必要）
- **NewtonRaphsonSolver.swift:343-369** - 保留された実装コード

---

**最終更新:** 2025-10-27
**ステータス:** Preconditioner実装保留、Line Search調査を優先
**次のアクション:** Line search詳細ログの追加（Phase 1）
**推定完了日:** 調査実行後に再評価（3-5時間）
