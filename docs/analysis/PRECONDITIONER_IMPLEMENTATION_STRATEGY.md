# Preconditioner実装戦略

**⚠️ 警告: このドキュメントは保留中です ⚠️**

**作成日:** 2025-10-27
**最終更新:** 2025-10-27
**ステータス:** **実装保留 - 事前調査が必要**

---

## 🚨 重要な指摘事項

このドキュメントの実装戦略には以下の深刻な問題があることが判明しました：

1. **二重スケーリング**: 既に`xScaled = x / referenceState`でスケーリング済みなのに、同じreferenceStateをPreconditionerに使うと二重にスケーリングされる

2. **数学的な誤り**: 左前処理と右前処理を混在させており、数学的に正しくない

3. **根拠のない期待値**: 条件数が1-2桁改善すると記載したが、実測データがない

4. **Broadcasting の危険性**: MLXのBroadcasting規則を正確に確認していない

5. **桁落ちリスク**: deltaScaledがさらに小さくなる可能性

---

## ✅ 代わりに実施すべきこと

**このドキュメントの実装は実施しないでください。**

代わりに、以下のドキュメントに従って事前調査を実施してください：

👉 **`PRECONDITIONER_INVESTIGATION.md`**

このドキュメントでは：
1. 既存スケーリング後の実際の状態を測定
2. 追加のPreconditionerが本当に必要か判定
3. 必要な場合、数学的に正しい実装方針を決定
4. 小規模テストで効果を検証

---

## 📚 参考情報（保留中の内容）

以下は参考情報として残しますが、**実装しないでください**。

---

## 📊 問題の要約

### 現状

**すべてのメッシュ解像度（nCells=50, 75, 100）で以下の問題が発生:**

1. residualNorm ≈ 0.46-0.48 で停滞
2. tolerance=0.1 に到達不可（4.6倍のギャップ）
3. Newton方向の消失（||Δ|| → 10^-8）
4. Line searchで改善不可（α=1.0で大幅悪化）

### 根本原因

**変数スケールの不均一性:**

```
moderate初期プロファイル:
  Ti: 1000 → 1500 eV        (O(10^3))
  Te: 1000 → 1500 eV        (O(10^3))
  ne: 2.0e19 → 2.4e19 m^-3  (O(10^19))

Jacobianのスケール差:
  dF_Ti/dTi: O(10^22) / O(10^3)  = O(10^19)
  dF_ne/dne: O(10^22) / O(10^19) = O(10^3)

  → スケール差: 10^16倍！
```

**結果:** Newton方向が大きなスケールの変数に支配され、小スケール変数が無視される

---

## 🎯 解決策：Diagonal Preconditioner

### 原理

**変数ごとに異なるスケーリングを適用してJacobianを正規化:**

```
元の線形システム:
  J * Δx = -R

Preconditioner P を導入:
  (P^-1 * J) * (P * Δx) = -P^-1 * R

  Jhat * Δhat = -Rhat

ここで:
  Jhat = P^-1 * J      (左前処理)
  Δhat = P * Δx        (前処理された補正)
  Rhat = P^-1 * R      (前処理された残差)

解の復元:
  Δx = P^-1 * Δhat
```

### Preconditioner行列の選択

**Diagonal Preconditioner（対角行列）:**

```swift
P = diag(referenceState)

referenceStateは各変数の典型的スケール:
  P[i] = Ti_ref[i]  (i ∈ Ti indices)
  P[j] = Te_ref[j]  (j ∈ Te indices)
  P[k] = ne_ref[k]  (k ∈ ne indices)
```

**例（nCells=75）:**
```
P = [1000, 1050, 1100, ..., 1500,  // Ti: 75 cells
     1000, 1050, 1100, ..., 1500,  // Te: 75 cells
     2.0e19, 2.05e19, ..., 2.4e19, // ne: 75 cells
     ...]                           // psi (if present)
```

### 期待される効果

1. **条件数の劇的改善:**
   - κ_before: 3.36e+04
   - κ_after: **1e+03程度**（1-2桁改善）

2. **正規化されたJacobian:**
   - すべての変数がO(1)スケール
   - dJhat/dTi と dJhat/dne が同等のオーダー

3. **Newton方向の正確化:**
   - 小スケール変数も適切に更新
   - Line search α=1.0 が成功する可能性

4. **収束速度の向上:**
   - residualNorm < 0.1 到達可能
   - イテレーション数の削減

---

## 🔧 実装計画

### Phase 1: 基本実装（必須）

#### 変更箇所1: `solve()` メソッド

**ファイル:** `NewtonRaphsonSolver.swift`
**開始行:** 約200行目（solve()メソッド内）

**現在のコード構造:**
```swift
public func solve(...) -> SolverResult {
    // 1. スケーリング
    let xScaled = x / referenceState

    // 2. Newtonループ
    for iteration in 0..<config.maxIterations {
        // 3. 残差計算
        let residualScaled = ...

        // 4. Jacobian計算
        let jacobianScaled = flattenedState.computeJacobianViaVJP(...)

        // 5. SVD診断
        ...

        // 6. 線形ソルバー
        let deltaScaled = linearSolver.solve(jacobianScaled, -residualScaled)

        // 7. Line search
        let alpha = lineSearch(...)

        // 8. 更新
        xScaled = xScaled + alpha * deltaScaled
    }
}
```

**必要な変更（Preconditioner追加）:**

```swift
public func solve(...) -> SolverResult {
    // 1. スケーリング（既存）
    let xScaled = x / referenceState

    // 2. Preconditioner作成（新規）
    let P = referenceState  // [nVars]
    let P_inv = 1.0 / P      // Element-wise inverse
    eval(P_inv)

    // 3. Newtonループ
    for iteration in 0..<config.maxIterations {
        // 4. 残差計算（既存）
        let residualScaled = ...

        // 5. Preconditioned residual（新規）
        let residualPreconditioned = residualScaled * P_inv
        eval(residualPreconditioned)

        // 6. Jacobian計算（既存）
        let jacobianScaled = flattenedState.computeJacobianViaVJP(...)

        // 7. Preconditioned Jacobian（新規）
        // 列スケーリング: J_ij *= 1/P_j
        let jacobianPreconditioned = jacobianScaled * P_inv  // Broadcasting over columns
        eval(jacobianPreconditioned)

        // 8. SVD診断（Preconditioned Jacobianに対して）
        let (_, S, _) = MLX.svd(jacobianPreconditioned, stream: .cpu)
        // ... 条件数計算

        // 9. 線形ソルバー（Preconditionedシステム）
        let deltaPreconditioned = linearSolver.solve(
            jacobianPreconditioned,
            -residualPreconditioned
        )
        eval(deltaPreconditioned)

        // 10. 元のスケールに戻す（新規）
        let deltaScaled = deltaPreconditioned * P_inv
        eval(deltaScaled)

        // 11. Line search（既存、deltaScaledを使用）
        let alpha = lineSearch(...)

        // 12. 更新（既存）
        xScaled = xScaled + alpha * deltaScaled
    }
}
```

#### 重要な注意点

**MLX Broadcasting:**
```swift
// Jacobian: [nVars, nVars]
// P_inv: [nVars]

// 列スケーリング（各列 j を P_inv[j] で割る）
let jacobianPreconditioned = jacobianScaled * P_inv  // Broadcasting over axis 1

// これは以下と等価:
// for j in 0..<nVars {
//     jacobianPreconditioned[:, j] = jacobianScaled[:, j] * P_inv[j]
// }
```

**eval()の配置:**
- Preconditioner作成後: `eval(P_inv)`
- Jacobian/残差のPrecondition後: `eval(jacobianPreconditioned)`, `eval(residualPreconditioned)`
- 線形ソルバー後: `eval(deltaPreconditioned)`
- スケール復元後: `eval(deltaScaled)`

---

### Phase 2: ログ追加（デバッグ用）

**追加するログ:**

```swift
print("[DEBUG-PRECOND] Preconditioner created: P range=[\(P.min().item(Float.self)), \(P.max().item(Float.self))]")

print("[DEBUG-PRECOND] iter=\(iteration): residualPreconditioned range=[\(residualPreconditioned.min().item(Float.self)), \(residualPreconditioned.max().item(Float.self))]")

print("[DEBUG-PRECOND] iter=\(iteration): jacobianPreconditioned condition number before/after: \(conditionNumberBefore) → \(conditionNumberAfter)")

print("[DEBUG-PRECOND] iter=\(iteration): deltaPreconditioned range=[\(deltaPreconditioned.min().item(Float.self)), \(deltaPreconditioned.max().item(Float.self))]")
```

---

### Phase 3: 検証と調整

#### 検証項目

1. **条件数の改善確認:**
   ```
   κ_before: 3.36e+04 (既存のSVD診断)
   κ_after:  < 1e+04 (Preconditioned JacobianのSVD)

   期待値: 1桁以上の改善
   ```

2. **収束速度の確認:**
   ```
   iter=0: residualNorm=2.03 → 0.51 (既存と同等)
   iter=1: residualNorm=0.51 → 0.2x (改善期待)
   iter=2-5: residualNorm < 0.1 (目標到達)
   ```

3. **Line searchの成功率:**
   ```
   α=1.0 が採用される割合の増加
   fallback α=0.1 の頻度低下
   ```

4. **deltaScaledの健全性:**
   ```
   ||Δ|| > 1e-6 を維持（10^-8以下に落ちない）
   ```

#### 調整パラメータ

**もし収束が不安定な場合:**

1. **Preconditionerの平滑化:**
   ```swift
   // セル間の急激な変化を平滑化
   let P_smoothed = smoothPreconditioner(P, smoothingFactor: 0.1)
   ```

2. **Partial Preconditioner:**
   ```swift
   // 温度のみPreconditioning、密度は既存スケーリング
   let P = mixPreconditioner(referenceState, mixRatio: 0.5)
   ```

3. **Jacobianの対称性保持:**
   ```swift
   // 左右両側前処理（対称性を保持）
   let jacobianPreconditioned = diag(P_inv) * jacobianScaled * diag(P_inv)
   // ただしdeltaの復元も変更必要
   ```

---

## 📋 実装チェックリスト

### Phase 1: 基本実装

- [ ] `NewtonRaphsonSolver.swift` をバックアップ
- [ ] Preconditioner `P` と `P_inv` の作成コード追加
- [ ] `residualPreconditioned = residualScaled * P_inv` 追加
- [ ] `jacobianPreconditioned = jacobianScaled * P_inv` 追加（列スケーリング）
- [ ] `deltaPreconditioned` を線形ソルバーで解く
- [ ] `deltaScaled = deltaPreconditioned * P_inv` でスケール復元
- [ ] 各ステップに `eval()` 追加
- [ ] SVD診断を `jacobianPreconditioned` に対して実施
- [ ] ビルドエラーの修正

### Phase 2: ログとデバッグ

- [ ] Preconditioner範囲のログ追加
- [ ] 前後の条件数比較ログ追加
- [ ] deltaPreconditioned範囲のログ追加
- [ ] ビルド成功確認（swift-gotenx）

### Phase 3: テストと検証

- [ ] nCells=75, tolerance=1e-1 で実行
- [ ] 条件数が1桁以上改善することを確認
- [ ] residualNorm < 0.1 到達を確認
- [ ] Line search α=1.0 の採用頻度向上を確認
- [ ] 計算時間の変化を記録（改善 or 悪化）

### Phase 4: ドキュメント更新

- [ ] `DIAGNOSTIC_RESULTS_PRECONDITIONER.md` 作成（結果記録）
- [ ] `SimulationPresets.swift` コメント更新
- [ ] `PHASE_MIGRATION_GUIDE.md` 更新（Phase 0成功条件変更）

---

## 🔍 トラブルシューティング

### 問題1: ビルドエラー（Broadcasting）

**症状:**
```
error: Cannot convert value of type 'MLXArray' to expected argument type 'MLXArray'
```

**原因:** MLXのBroadcasting規則の誤解

**解決策:**
```swift
// 明示的に次元を拡張
let P_inv_broadcast = P_inv.reshaped([1, nVars])  // [1, nVars]
let jacobianPreconditioned = jacobianScaled * P_inv_broadcast
```

### 問題2: 条件数が改善しない

**症状:** κ_after ≈ κ_before (3.36e+04 → 3.0e+04)

**原因:** Preconditionerのスケールが不適切

**診断:**
```swift
print("P range: [\(P.min().item(Float.self)), \(P.max().item(Float.self))]")
// 期待値: [1000, 2.4e19] (大きな範囲)
// 実際: [1000, 1500] (範囲が狭い) → neが含まれていない可能性
```

**解決策:** referenceStateの構築を確認

### 問題3: 収束がさらに悪化

**症状:** residualNorm が発散、または停滞がさらに早期化

**原因:** Preconditionerの符号誤り、またはスケール復元の誤り

**診断:**
```swift
// deltaScaledの符号と大きさを確認
print("deltaScaled before preconditioner: \(deltaScaled_old.mean().item(Float.self))")
print("deltaScaled after preconditioner: \(deltaScaled_new.mean().item(Float.self))")
// 同じオーダーで同じ符号であるべき
```

**解決策:** スケール復元の式を再確認
```swift
// 正: deltaScaled = deltaPreconditioned * P_inv
// 誤: deltaScaled = deltaPreconditioned * P
```

### 問題4: 計算時間が大幅増加

**症状:** iter時間が16秒 → 30秒超

**原因:** Preconditioner計算のオーバーヘッド、またはeval()不足

**解決策:**
```swift
// Preconditionerはループ外で1回だけ作成
// let P = referenceState  ← ループの外
// for iteration in 0..<maxIterations {
//     let residualPreconditioned = residualScaled * P_inv
// }
```

---

## 📊 成功基準

### 必須条件（Phase 1完了）

1. ビルドが成功し、シミュレーションが開始できる
2. 条件数が既存値より小さくなる（κ < 3.36e+04）
3. 発散しない（residualNorm が ∞ にならない）

### 期待される成果（Phase 3完了）

1. **条件数:** κ < 1e+04（1桁改善）
2. **収束:** residualNorm < 0.1 到達（tolerance達成）
3. **イテレーション数:** < 10回（現在15回以上）
4. **Line search:** α=1.0 採用率 > 50%
5. **計算時間:** 2倍以内の増加（Preconditionerオーバーヘッド）

### 理想的な成果

1. **条件数:** κ < 5e+03（2桁改善）
2. **収束:** residualNorm < 5e-2 到達（元々の目標）
3. **イテレーション数:** < 5回
4. **Line search:** α=1.0 採用率 > 80%
5. **計算時間:** 1.5倍以内

---

## 🚀 実装の順序

### ステップ1: コードレビュー（30分）

- `NewtonRaphsonSolver.swift` の現在のsolve()メソッドを完全に理解
- referenceStateの構造を確認（どの変数がどの位置にあるか）
- 既存のスケーリングとの関係を整理

### ステップ2: 最小実装（1時間）

- Preconditioner作成のみ（ログ追加）
- 実行して P の範囲を確認
- 期待通りの値か検証（Ti: ~1000, ne: ~1e19）

### ステップ3: Jacobian Preconditioning（1時間）

- jacobianPreconditionedの計算追加
- SVD診断で条件数確認
- 改善していることを確認（ログのみ、まだ線形ソルバーに渡さない）

### ステップ4: 完全実装（1時間）

- residualPreconditionedの計算
- 線形ソルバーに渡す
- deltaScaledの復元
- 実行してresidualNormの推移を確認

### ステップ5: デバッグと調整（1-2時間）

- 収束しない場合のトラブルシューティング
- パラメータ調整
- ログの詳細化

### ステップ6: ドキュメント化（30分）

- 結果を `DIAGNOSTIC_RESULTS_PRECONDITIONER.md` に記録
- 成功/失敗の要因分析
- 次のステップの提案

**推定総時間:** 5-7時間

---

## 📝 代替案（Preconditionerが失敗した場合）

### 代替案1: Trust-Region法

**概要:** Line searchの代わりに、事前に信頼半径 r 内でΔxを制限

```
min_{||Δ|| ≤ r} ||J·Δ + R||²
```

**利点:** 遠方での二次近似の破綻に強い

**欠点:** 実装が複雑（Dogleg法、Cauchy点計算など）

**推定実装時間:** 10-20時間

### 代替案2: 適応的変数スケーリング

**概要:** イテレーションごとにreferenceStateを更新

```swift
for iteration in 0..<maxIterations {
    let referenceState_adaptive = currentState.abs() + 1e-6  // ゼロ除算回避
    let xScaled = currentState / referenceState_adaptive
    ...
}
```

**利点:** 実装が簡単（5-10行）

**欠点:** 効果が限定的（根本的解決にならない）

### 代替案3: ソルバー変更（GMRES, BiCGSTAB）

**概要:** 直接法（MLX.solve）の代わりに反復法を使用

**利点:** 大規模問題に強い、Preconditionerと相性良い

**欠点:** 収束判定が複雑、実装コストが高い

**推定実装時間:** 20-40時間

---

## ✅ 最終チェック

実装前に以下を確認:

- [ ] 診断結果（DIAGNOSTIC_RESULTS_nCells75.md）を理解した
- [ ] Preconditionerの数学的原理を理解した
- [ ] 実装箇所（NewtonRaphsonSolver.swift）を特定した
- [ ] MLXのBroadcasting規則を理解した
- [ ] eval()の配置ルールを理解した
- [ ] バックアップを取った
- [ ] トラブルシューティング手順を把握した

**準備が整ったら実装を開始してください。**

---

**最終更新:** 2025-10-27
**ステータス:** 実装準備完了
**推定実装時間:** 5-7時間
**成功確率:** 高（数学的根拠明確、実装リスク中程度）
