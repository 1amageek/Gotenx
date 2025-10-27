# Preconditioner導入前の事前調査

**作成日:** 2025-10-27
**目的:** Preconditioner実装前に、現状のスケーリング後の実際の状態を把握する
**重要:** PRECONDITIONER_IMPLEMENTATION_STRATEGY.mdの実装は**保留**し、まずこの調査を完了させる

---

## 🚨 実装戦略の問題点（指摘事項）

### 1. 二重スケーリングの危険性

**既存のスケーリング:**
```swift
// NewtonRaphsonSolver.swift:200付近
let xScaled = x / referenceState
```

**提案したPreconditioner:**
```swift
let P = referenceState
let P_inv = 1.0 / P
```

**問題:** 同じreferenceStateを使うと、実質的に二重スケーリングになる
- 既に `x / referenceState` でスケーリング済み
- さらに `Jacobian * P_inv` で割ると、もう一度同じ値で割ることになる
- 期待しているオーダー調整が崩れる

### 2. 数学的な誤り（左右前処理の混在）

**提案したコード:**
```swift
let residualPreconditioned = residualScaled * P_inv      // 左前処理的
let jacobianPreconditioned = jacobianScaled * P_inv      // 右前処理的
let deltaPreconditioned = solve(jacobianPreconditioned, -residualPreconditioned)
let deltaScaled = deltaPreconditioned * P_inv            // 復元
```

**問題:** 左右前処理が混在している
- 左前処理: `P⁻¹ J Δx = -P⁻¹ R`
- 右前処理: `J P⁻¹ (P Δx) = -R`
- 提案コードはどちらでもない

**正しい形:**

**左前処理:**
```
P⁻¹ J Δx = -P⁻¹ R
J_hat = P⁻¹ J  (行スケーリング)
R_hat = P⁻¹ R
Δx = solve(J_hat, -R_hat)  (そのまま使える)
```

**右前処理:**
```
J P⁻¹ (P Δx) = -R
J_hat = J P⁻¹  (列スケーリング)
Δ_hat = solve(J_hat, -R)
Δx = P⁻¹ Δ_hat  (P⁻¹で復元)
```

### 3. 根拠のない期待値

**提案した期待値:**
- 条件数: κ = 3.36e+04 → 1e+03 (1-2桁改善)

**問題:** 実測データなし
- 既存のスケーリング後のJacobianがどのような状態か不明
- 追加の正規化が本当に必要か検証していない

### 4. Broadcasting の危険性

**提案したコード:**
```swift
let jacobianPreconditioned = jacobianScaled * P_inv  // [nVars, nVars] * [nVars]
```

**問題:** MLXのBroadcasting規則を正確に確認していない
- 意図: 各列jをP_inv[j]で割る（列スケーリング）
- 実際: Broadcastingがどの軸で起きるか不明確
- `P_inv.reshaped([1, nVars])` で明示的に指定すべき

### 5. 桁落ちリスク

**提案したコード:**
```swift
let deltaScaled = deltaPreconditioned * P_inv
```

**問題:** deltaScaledがさらに小さくなる
- 現状でもdeltaScaledが10⁻⁸レベルまで低下
- P_invで割るとさらに桁落ち
- 右前処理なら `deltaScaled = deltaPreconditioned * P` で桁を維持すべき

---

## 📊 事前調査の計画

### Phase 1: 既存スケーリング後の状態確認

**目的:** xScaled = x / referenceState 後のJacobianとresidualが本当にスケール差を持つか確認

#### 調査1-1: referenceStateの内容確認

**実装場所:** `NewtonRaphsonSolver.swift:200付近`

**追加コード:**
```swift
// referenceStateの確認
print("[DEBUG-SCALING] referenceState range: [\(referenceState.min().item(Float.self)), \(referenceState.max().item(Float.self))]")

// 変数ごとの範囲（nCells=75の場合、各変数75要素）
let nCells = referenceState.shape[0] / 4  // Ti, Te, ne, psi の4変数
let Ti_ref = referenceState[0..<nCells]
let Te_ref = referenceState[nCells..<(2*nCells)]
let ne_ref = referenceState[(2*nCells)..<(3*nCells)]

eval(Ti_ref, Te_ref, ne_ref)

print("[DEBUG-SCALING] Ti_ref range: [\(Ti_ref.min().item(Float.self)), \(Ti_ref.max().item(Float.self))]")
print("[DEBUG-SCALING] Te_ref range: [\(Te_ref.min().item(Float.self)), \(Te_ref.max().item(Float.self))]")
print("[DEBUG-SCALING] ne_ref range: [\(ne_ref.min().item(Float.self)), \(ne_ref.max().item(Float.self))]")
```

**期待される出力:**
```
[DEBUG-SCALING] referenceState range: [1000.0, 2.4e+19]  ← スケール差 2.4e+16倍
[DEBUG-SCALING] Ti_ref range: [1000.0, 1500.0]
[DEBUG-SCALING] Te_ref range: [1000.0, 1500.0]
[DEBUG-SCALING] ne_ref range: [2.0e+19, 2.4e+19]
```

#### 調査1-2: xScaled後の状態確認

**追加コード:**
```swift
// xScaledの確認
let xScaled = x / referenceState
eval(xScaled)

print("[DEBUG-SCALING] xScaled range: [\(xScaled.min().item(Float.self)), \(xScaled.max().item(Float.self))]")

// 変数ごとの範囲
let Ti_scaled = xScaled[0..<nCells]
let Te_scaled = xScaled[nCells..<(2*nCells)]
let ne_scaled = xScaled[(2*nCells)..<(3*nCells)]

eval(Ti_scaled, Te_scaled, ne_scaled)

print("[DEBUG-SCALING] Ti_scaled range: [\(Ti_scaled.min().item(Float.self)), \(Ti_scaled.max().item(Float.self))]")
print("[DEBUG-SCALING] Te_scaled range: [\(Te_scaled.min().item(Float.self)), \(Te_scaled.max().item(Float.self))]")
print("[DEBUG-SCALING] ne_scaled range: [\(ne_scaled.min().item(Float.self)), \(ne_scaled.max().item(Float.self))]")
```

**期待される出力（もしスケーリングが機能していれば）:**
```
[DEBUG-SCALING] xScaled range: [0.0, 1.5]  ← すべてO(1)
[DEBUG-SCALING] Ti_scaled range: [0.67, 1.0]  ← 1000/1500 ~ 1500/1500
[DEBUG-SCALING] Te_scaled range: [0.67, 1.0]
[DEBUG-SCALING] ne_scaled range: [0.83, 1.0]  ← 2.0e19/2.4e19 ~ 2.4e19/2.4e19
```

**もしスケール差が残っていれば:**
```
[DEBUG-SCALING] xScaled range: [0.0, 大きな値]
[DEBUG-SCALING] ne_scaled range: [大きな値, さらに大きな値]  ← スケール差残存
```

#### 調査1-3: residualScaled の成分オーダー確認

**追加コード（Newtonループ内）:**
```swift
// iter=0のresidualScaled
let residualScaled = ...  // 既存のコード

// 変数ごとの残差範囲
let residual_Ti = residualScaled[0..<nCells]
let residual_Te = residualScaled[nCells..<(2*nCells)]
let residual_ne = residualScaled[(2*nCells)..<(3*nCells)]

eval(residual_Ti, residual_Te, residual_ne)

print("[DEBUG-RESIDUAL] iter=\(iteration): residual_Ti range: [\(residual_Ti.min().item(Float.self)), \(residual_Ti.max().item(Float.self))]")
print("[DEBUG-RESIDUAL] iter=\(iteration): residual_Te range: [\(residual_Te.min().item(Float.self)), \(residual_Te.max().item(Float.self))]")
print("[DEBUG-RESIDUAL] iter=\(iteration): residual_ne range: [\(residual_ne.min().item(Float.self)), \(residual_ne.max().item(Float.self))]")
```

**チェック項目:**
- Ti, Te, ne の残差が同じオーダー（O(1)）か？
- もし10^16倍のスケール差があれば、ne_residualが極端に大きい
- もしスケーリングが機能していれば、すべてO(1)程度

#### 調査1-4: jacobianScaled の成分オーダー確認

**追加コード:**
```swift
// Jacobian計算後
let jacobianScaled = flattenedState.computeJacobianViaVJP(...)

// ブロックごとの範囲（簡易的に各ブロックの対角要素を確認）
let J_TiTi = jacobianScaled[0..<nCells, 0..<nCells]
let J_TeTe = jacobianScaled[nCells..<(2*nCells), nCells..<(2*nCells)]
let J_nene = jacobianScaled[(2*nCells)..<(3*nCells), (2*nCells)..<(3*nCells)]

eval(J_TiTi, J_TeTe, J_nene)

print("[DEBUG-JACOBIAN] iter=\(iteration): J_TiTi range: [\(J_TiTi.min().item(Float.self)), \(J_TiTi.max().item(Float.self))]")
print("[DEBUG-JACOBIAN] iter=\(iteration): J_TeTe range: [\(J_TeTe.min().item(Float.self)), \(J_TeTe.max().item(Float.self))]")
print("[DEBUG-JACOBIAN] iter=\(iteration): J_nene range: [\(J_nene.min().item(Float.self)), \(J_nene.max().item(Float.self))]")
```

**チェック項目:**
- J_TiTi, J_TeTe, J_nene が同じオーダーか？
- もしスケール差があれば、特定のブロックが極端に大きい/小さい
- 対角要素だけでなく、オフ対角（J_Tine など）も確認すると良い

---

### Phase 2: 追加スケーリングの必要性判断

**Phase 1の結果に基づいて判断:**

#### ケース A: スケーリングが既に機能している

**条件:**
- xScaled, residualScaled, jacobianScaled のすべてがO(1)程度
- 変数間のスケール差が10倍以内

**結論:** Preconditioner不要
- 停滞の原因は他にある（離散化誤差、非線形性など）
- 別のアプローチを検討（Trust-Region法、dtさらに削減など）

#### ケース B: 部分的にスケール差が残存

**条件:**
- xScaledはO(1)だが、residualScaledやjacobianScaledに差がある
- 特定の変数ブロックが他より1-2桁大きい

**結論:** 軽量なPreconditioner検討
- 変数ごとに異なるreferenceScaleを使う
- ただしreferenceStateとは別の値（例: residualの典型的スケール）

#### ケース C: 大きなスケール差が残存

**条件:**
- residualScaledやjacobianScaledに10^3倍以上の差
- neブロックが他より極端に大きい/小さい

**結論:** Preconditioner必要
- ただし、referenceStateとは異なる値を使う
- 例: `P = diag(典型的residualスケール)` または `P = diag(Jacobian対角成分の平均)`

---

### Phase 3: 正しいPreconditioner設計（Phase 2でケースC判明時）

#### 方針の統一

**右前処理を推奨（理由: 復元が自然）:**

```
元の方程式:
  J Δx = -R

右前処理:
  J P⁻¹ (P Δx) = -R
  J_hat (Δx_hat) = -R

ここで:
  J_hat = J P⁻¹     (列スケーリング)
  Δx_hat = P Δx     (拡大されたベクトル)
  R_hat = R         (変更なし)

解法:
  Δx_hat = solve(J_hat, -R_hat)
  Δx = P⁻¹ Δx_hat   (復元: 縮小)
```

**実装コード（正しい形）:**
```swift
// Preconditioner作成（referenceStateとは異なる）
let P = computePreconditioner(jacobianScaled, residualScaled)  // 後述
let P_inv = 1.0 / P
eval(P_inv)

// 右前処理: 列スケーリング
let P_inv_broadcast = P_inv.reshaped([1, nVars])  // 明示的に列方向
let jacobianPreconditioned = jacobianScaled * P_inv_broadcast
eval(jacobianPreconditioned)

// 残差は変更なし
let residualPreconditioned = residualScaled  // 右前処理では変更不要

// 線形ソルバー
let deltaPreconditioned = linearSolver.solve(jacobianPreconditioned, -residualPreconditioned)
eval(deltaPreconditioned)

// 復元（P⁻¹で縮小）
let deltaScaled = deltaPreconditioned * P_inv  // ← これでdeltaのスケールが適切に
eval(deltaScaled)
```

#### Preconditioner の計算方法

**Option 1: Jacobian対角成分の絶対値**
```swift
func computePreconditioner(_ jacobian: MLXArray, _ residual: MLXArray) -> MLXArray {
    // 各列の典型的スケール = 対角成分の絶対値
    let diag = jacobian.diagonal()
    let P = abs(diag) + 1e-10  // ゼロ除算回避
    eval(P)
    return P
}
```

**Option 2: Jacobian各列のノルム**
```swift
func computePreconditioner(_ jacobian: MLXArray, _ residual: MLXArray) -> MLXArray {
    // 各列のL2ノルム
    let P = sqrt((jacobian * jacobian).sum(axis: 0)) + 1e-10
    eval(P)
    return P
}
```

**Option 3: 残差の典型的スケール**
```swift
func computePreconditioner(_ jacobian: MLXArray, _ residual: MLXArray) -> MLXArray {
    // 各変数の残差スケール
    let P = abs(residual) + 1e-10
    eval(P)
    return P
}
```

**どれを選ぶか:** Phase 1の調査結果に基づいて決定

---

### Phase 4: 小規模テストでの検証

**実装前の最終確認:**

#### テスト1: 条件数の変化

```swift
// Preconditioner適用前
let (_, S_before, _) = MLX.svd(jacobianScaled, stream: .cpu)
eval(S_before)
let kappa_before = S_before[0].item(Float.self) / S_before[S_before.count - 1].item(Float.self)

// Preconditioner適用後
let (_, S_after, _) = MLX.svd(jacobianPreconditioned, stream: .cpu)
eval(S_after)
let kappa_after = S_after[0].item(Float.self) / S_after[S_after.count - 1].item(Float.self)

print("[DEBUG-PRECOND-TEST] κ_before: \(kappa_before)")
print("[DEBUG-PRECOND-TEST] κ_after: \(kappa_after)")
print("[DEBUG-PRECOND-TEST] Improvement ratio: \(kappa_before / kappa_after)")
```

**期待値:** κ_after < κ_before (改善していること)
**最低条件:** 改善率 > 2倍

#### テスト2: Line search α の変化

```swift
// 5イテレーション実行して、採用されたαを記録
var alphas_before: [Float] = []
var alphas_after: [Float] = []

// Preconditioner無し: 5イテレーション
for i in 0..<5 {
    let alpha = lineSearch(...)
    alphas_before.append(alpha)
}

// Preconditioner有り: 5イテレーション
for i in 0..<5 {
    let alpha = lineSearch(...)
    alphas_after.append(alpha)
}

print("[DEBUG-PRECOND-TEST] α before: \(alphas_before)")  // [1.0, 0.25, 0.25, 0.1, 0.1] など
print("[DEBUG-PRECOND-TEST] α after: \(alphas_after)")   // [1.0, 1.0, 1.0, 0.5, 0.5] など（改善期待）
```

**期待値:** alphas_afterで α=1.0 の頻度増加

#### テスト3: ||Δ|| の推移

```swift
// Preconditioner無し/有りで||Δ||の推移を比較
var deltas_before: [Float] = []
var deltas_after: [Float] = []

// 各イテレーションで記録
deltas_before.append(norm(deltaScaled).item(Float.self))
deltas_after.append(norm(deltaScaled).item(Float.self))

print("[DEBUG-PRECOND-TEST] ||Δ|| before: \(deltas_before)")  // [2e-4, 8e-7, 2e-8, ...] など
print("[DEBUG-PRECOND-TEST] ||Δ|| after: \(deltas_after)")   // [2e-4, 5e-5, 1e-5, ...] など（維持期待）
```

**期待値:** deltas_afterで10⁻⁸への急落が起きない

#### テスト4: residualNorm の収束速度

```swift
// 両者で10イテレーション実行し、residualNormの推移を比較
var residuals_before: [Float] = []
var residuals_after: [Float] = []

// 記録...

print("[DEBUG-PRECOND-TEST] residualNorm before: \(residuals_before)")
print("[DEBUG-PRECOND-TEST] residualNorm after: \(residuals_after)")
```

**期待値:** residuals_afterが0.1以下に到達、またはより速く減少

---

## 📋 実装チェックリスト（改訂版）

### Phase 1: 事前調査（必須）

- [ ] referenceStateの内容確認（変数ごとの範囲）
- [ ] xScaled後の状態確認（O(1)になっているか）
- [ ] residualScaledの成分オーダー確認（変数間の差）
- [ ] jacobianScaledの成分オーダー確認（ブロックごとの差）
- [ ] 調査結果を記録（新しいドキュメント作成）

### Phase 2: 必要性判断

- [ ] Phase 1の結果に基づき、ケースA/B/Cを判定
- [ ] ケースAの場合: Preconditioner不要、別アプローチ検討
- [ ] ケースBの場合: 軽量Preconditioner検討
- [ ] ケースCの場合: Phase 3へ進む

### Phase 3: Preconditioner設計（ケースCのみ）

- [ ] 右前処理に方針統一
- [ ] Preconditioner計算方法選択（Option 1/2/3）
- [ ] Broadcasting明示的に指定（.reshaped）
- [ ] 復元ステップの数学的検証

### Phase 4: 小規模テスト

- [ ] 条件数の変化を実測（κ_before vs κ_after）
- [ ] Line search αの変化を記録
- [ ] ||Δ||の推移を確認（桁落ちしないか）
- [ ] residualNormの収束速度比較
- [ ] テスト結果をドキュメント化

### Phase 5: 本実装（テスト成功後）

- [ ] NewtonRaphsonSolver.swiftに統合
- [ ] swift-gotenxビルド
- [ ] nCells=75, tolerance=1e-1で実行
- [ ] 結果をDIAGNOSTIC_RESULTS_PRECONDITIONER.mdに記録

---

## 🎯 成功基準（改訂版）

### Phase 1完了の基準

- [ ] すべての調査項目のログが取得できた
- [ ] 各変数のスケールオーダーが判明した
- [ ] ケースA/B/Cの判定ができる状態

### Phase 4完了の基準（ケースCの場合）

- [ ] κ_after < κ_before (条件数改善)
- [ ] α=1.0採用率が向上（+20%以上）
- [ ] ||Δ||が10⁻⁸に落ちない
- [ ] residualNormが改善傾向

### Phase 5完了の基準

- [ ] 本実装でresiduaLNorm < 0.1到達
- [ ] 全ステップで収束
- [ ] 計算時間が2倍以内

---

## 📝 次のアクション

1. **Phase 1の調査コードを実装**
   - NewtonRaphsonSolver.swiftに診断ログ追加
   - swift-gotenxビルド
   - nCells=75で1-2ステップだけ実行

2. **調査結果の分析**
   - ログから各変数のオーダーを確認
   - ケースA/B/Cを判定
   - 結果をドキュメント化

3. **方針決定**
   - ケースAなら別アプローチ
   - ケースBなら軽量Preconditioner
   - ケースCならPhase 3へ

**重要:** PRECONDITIONER_IMPLEMENTATION_STRATEGY.mdの実装は**実施しないでください**。
まずこの調査を完了させてから判断します。

---

**最終更新:** 2025-10-27
**ステータス:** Phase 1（事前調査）待ち
**推定時間:** Phase 1実装と実行で1-2時間
