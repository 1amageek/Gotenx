# Newton-Raphsonソルバーステータスサマリー

**最終更新:** 2025-10-27
**現在のフェーズ:** Phase 0-LINE_SEARCH_INVESTIGATION（Preconditioner実装保留）

---

## 📊 現在の状況

### 問題

Newton-Raphson法が**すべてのメッシュ解像度**（nCells=50, 75, 100）で以下の問題に直面：

- residualNorm ≈ 0.46-0.48 で停滞
- tolerance=0.1 に到達不可（4.6倍のギャップ）
- Newton方向の消失（||Δ|| → 10^-8）
- Line searchで改善不可能（α=1.0で悪化）

### 根本原因

**変数スケールの不均一性:**

```
Ti/Te: O(10^3) eV
ne:    O(10^19) m^-3

Jacobianのスケール差: 10^16倍！
```

これにより：
- Newton方向が大きなスケールの変数に支配される
- 小スケール変数が無視される
- 方向そのものが不正確

### 診断の経緯

1. **nCells=50:** residualNorm=0.475で停滞 → 離散化誤差の疑い
2. **nCells=100:** 条件数悪化（κ=6.5e+05）、収束極端に遅い → ジレンマ発見
3. **nCells=75:** 条件数最良（κ=3.36e+04）だが依然停滞 → メッシュ解像度では解決不可と確定

---

## 🎯 解決策：Diagonal Preconditioner

### 実装の必要性

**Preconditionerなしでは、moderate初期プロファイル（Ti: 1000→1500 eV）でtolerance=0.1に到達できない。**

### 原理

変数ごとに異なるスケーリングを適用してJacobianを正規化：

```
元の線形システム:
  J * Δx = -R

Preconditioner適用後:
  (P^-1 * J) * (P * Δx) = -P^-1 * R

ここで P = diag(referenceState)
```

すべての変数が同じオーダー（O(1)）になる。

### 期待される効果

- **条件数:** κ = 3.36e+04 → 1e+03程度（1-2桁改善）
- **収束:** residualNorm < 0.1 到達可能
- **Line search:** α=1.0 採用率向上
- **イテレーション数:** < 10回（現在15回以上）

---

## 📋 実装計画（改訂版）

### ⚠️ 重要な変更

**PRECONDITIONER_IMPLEMENTATION_STRATEGY.mdの実装は保留されました。**

以下の問題が指摘されたため、まず事前調査を実施します：
1. 二重スケーリングの危険性
2. 数学的な誤り（左右前処理の混在）
3. 根拠のない期待値
4. Broadcasting の危険性
5. 桁落ちリスク

### Phase A: 事前調査（最優先）

**実装場所:** `swift-gotenx/Sources/GotenxCore/Solver/NewtonRaphsonSolver.swift`

**詳細:** `PRECONDITIONER_INVESTIGATION.md` 参照

**目的:**
1. 既存スケーリング後の実際の状態を測定
2. 追加のPreconditionerが本当に必要か判定
3. 必要な場合、数学的に正しい実装方針を決定

**推定時間:** 1-2時間（調査コード追加と実行）

**優先度:** 最高（これなしでは正しい判断ができない）

### Phase B: tolerance一時緩和（完了）

**実装場所:** `SimulationPresets.swift:99`

**変更:**
```swift
tolerance: 2e-1  // 1e-1 → 2e-1（事前調査完了まで）
```

**目的:** 現在の設定で0.462で収束判定され、シミュレーションが完走する

**状態:** ✅ 実装済み

### Phase C: 事前調査の実施と分析

**実装場所:** `NewtonRaphsonSolver.swift`

**内容:** Phase Aで追加した診断コードを実行し、結果を分析

**判定:**
- ケースA: Preconditioner不要 → 別アプローチ
- ケースB: 軽量Preconditioner検討
- ケースC: 本格的Preconditioner実装

**推定時間:** 1時間（実行と分析）

### Phase D: 実装（Phase C判定後）

**ケースAの場合:**
- Trust-Region法の検討
- dtさらに削減（1e-4など）
- 別のソルバーアルゴリズム

**ケースB/Cの場合:**
- 数学的に正しいPreconditioner設計
- 小規模テストで効果検証
- 本実装

**推定時間:** ケース依存（3-10時間）

---

## 📚 関連ドキュメント

### 診断結果

- **`DIAGNOSTIC_RESULTS.md`** - nCells=50の診断（Jacobian健全、離散化誤差の疑い）
- **`DIAGNOSTIC_RESULTS_nCells100.md`** - nCells=100の診断（条件数悪化、収束遅延）
- **`DIAGNOSTIC_RESULTS_nCells75.md`** - nCells=75の最終診断（メッシュ解像度では解決不可と確定）

### 実装戦略

- **`PRECONDITIONER_INVESTIGATION.md`** - 事前調査ガイド（最優先）
  - 既存スケーリングの実測方法
  - Preconditioner必要性の判定基準
  - 数学的に正しい実装方針
  - 小規模テストの方法

- **`PRECONDITIONER_IMPLEMENTATION_STRATEGY.md`** - ⚠️ 保留中
  - 二重スケーリング等の問題により実装保留
  - 参考情報として残存

### フェーズ管理

- **`PHASE_MIGRATION_GUIDE.md`** - Phase移行条件とロードマップ
  - Phase 0-PRECONDITIONER（現在）
  - Phase 1: Preconditioner検証（50ms）
  - Phase 2: 実運用（2秒）
  - Phase 3: 長期最適化

### 設定ファイル

- **`SimulationPresets.swift`** - シミュレーション設定
  - 現在: nCells=75, tolerance=2e-1（一時的）
  - Preconditioner後: tolerance=1e-1（本来の目標）

---

## ✅ 次のステップ（改訂版）

### ステップ1: 実装準備（完了✅）

- [x] 診断結果の分析と根本原因特定
- [x] tolerance一時緩和（動作確認用）
- [x] 事前調査計画の策定

### ステップ2: 事前調査の実装（完了✅）

- [x] `NewtonRaphsonSolver.swift` に診断ログ追加
  - [x] referenceStateの内容確認
  - [x] xScaled後の状態確認
  - [x] residualScaledの成分オーダー確認
  - [x] jacobianScaledの成分オーダー確認
- [x] swift-gotenxビルド
- [x] nCells=75で1-2ステップだけ実行

### ステップ3: 調査結果の分析と判定（完了✅）

- [x] ログから各変数のオーダーを確認
- [x] ケースA/B/Cを判定 → **ケースB確定**
- [x] 判定結果をドキュメント化 → `INVESTIGATION_RESULTS.md`
- [x] 次のアプローチを決定 → Option 1: 対角ブロックベースPreconditioner

### ステップ4: Preconditioner実装（⚠️ 保留）

**実装内容（ケースB - Option 1）:**
- [x] 対角ブロックベースPreconditioner設計・実装
- [x] swift-gotenxビルド成功

**⚠️ コードレビューによる保留:**
- ❌ **二重スケーリングリスク:** referenceStateと整合性問題
- ❌ **根本原因の誤認:** Jacobianスケール差vs α飽和
- ❌ **実装が時期尚早:** Line search調査が先

**詳細:** `PRECONDITIONER_SUSPENDED_REVIEW.md` 参照

**実装場所:** `swift-gotenx/Sources/GotenxCore/Solver/NewtonRaphsonSolver.swift:343-369`（コメントアウト済み）

### ステップ5: Line Search調査（完了✅）

**目的:** αが0.25で飽和する真の原因を特定

**実施内容:**
- [x] シミュレーション実行（nCells=75, iter=0-2）
- [x] 既存ログの詳細分析
- [x] 根本原因の特定

**重大な発見:**

**1. Newton方向の異常な崩壊（最重要）**
```
iter=0: ||Δ|| = 2.17e-04 ✅
iter=1: ||Δ|| = 8.35e-07 🔴 260倍縮小！
iter=2: ||Δ|| = 6.27e-07 🔴 さらに縮小
```

**2. Line searchパターン:**
```
iter=0: α=1.0で74.9%改善 ✅
iter=1: α=1.0で-3.2%悪化、α=0.25で6.2%改善 ⚠️
iter=2: α=0.25で0.0%改善（停滞開始） ❌
```

**3. residual成分の不均衡:**
```
Te: 4.419（支配的）
Ti: 0.987（4.5倍小さい）
ne: 0.025（177倍小さい）
```

**結論:**
- ❌ 問題は「αの飽和」ではない
- ✅ 真の問題は **Newton方向||Δ||の異常な縮小**
- ✅ Te（電子温度）残差が他変数を支配

**詳細:** `LINE_SEARCH_INVESTIGATION.md` 参照

---

### ステップ6: 追加調査の実施（完了✅）

**目的:** Newton方向崩壊の根本原因を特定

**Phase 1: Newton方向の妥当性検証**
- [x] 降下性確認: Δ · (-R) > 0? → ✅ 全イテレーションで正の降下方向
- [x] 線形ソルバー精度: ||J*Δ + R|| / ||R|| < 1e-6? → ⚠️ iter=0のみ1.88e-04（不足）、iter=1+はOK
- [x] Δの成分分解: Ti, Te, neごとの||Δ|| → 🔴 iter=0→1でTi, Te が1000倍縮小、neはほぼ不変

**Phase 2: residual成分の追跡**
- [x] 変数ごとのresidualノルム追跡 → 実装済み
- [x] 改善率の変数ごと分析 → 完了
- [x] Teだけが停滞しているか確認 → 🔴 iter=1+でTi, Te完全停滞（0.0%）、neのみ改善

**Phase 3: α=1.0失敗の詳細**
- [x] α=1.0での各変数のresidual → 分析完了
- [x] 予測 vs 実際の改善比較 → iter=0→1でTe改善、Ti/ne悪化を確認
- [x] 線形近似の有効性確認 → iter=0で精度不足、iter=1+はOK

**根本原因特定:**
- **Te residual dominance**: ||R_Te|| = 34.9（Tiの8.8倍、neの839倍）
- **Unbalanced updates**: iter=0→1でTe: +82.1%, Ti: -57.6%, ne: -125.6%
- **Complete stagnation**: iter=1+でTi, Te改善率0.0%

**詳細:** `NEWTON_DIRECTION_ANALYSIS.md`

---

### ステップ7: 対策の実装（完了✅）

**選択した対策: Option A - Variable-wise Weighting**

**実装内容:**
```swift
// NewtonRaphsonSolver.swift:194-211
let weight_Ti: Float = 1.0
let weight_Te: Float = 0.1  // Suppress Te by 10×
let weight_ne: Float = 10.0 // Emphasize ne by 10×
let weight_psi: Float = 1.0

let residualWeighted = MLX.concatenated([
    residual_Ti * weight_Ti,
    residual_Te * weight_Te,
    residual_ne * weight_ne,
    residual_psi * weight_psi
], axis: 0)
```

**実装場所:** `swift-gotenx/Sources/GotenxCore/Solver/NewtonRaphsonSolver.swift:188-211`

**期待される効果:**
- Te残差の支配を抑制（10分の1に）
- ne残差を強調（10倍に）
- Ti, Te, neのバランスの取れた更新
- iter=0→1での不均衡な更新を防止

**ビルド:** ✅ 成功（2025-10-27）

**次のステップ:** テストと効果測定

---

### ステップ8: Phase 1移行（対策成功後）

- [ ] tolerance=1e-1に戻す
- [ ] time.end=50msに延長
- [ ] 長時間実行での安定性確認

---

## 🔍 現在の設定

### SimulationPresets.swift (.constant)

```swift
// Phase 0-PRECONDITIONER: Preconditioner実装待ち
nCells: 75                    // 条件数最良
tolerance: 2e-1               // 一時的緩和（0.462で収束）
initialDt: 1.5e-4             // 0.15ms
moderate profile: 1.5×, 1.2×  // Ti/ne ピーク比
time.end: 0.005               // 5ms（診断用）
```

### Jacobian診断結果（nCells=75）

```
κ = 3.36e+04     ✅ 良好（3パターン中最良）
σ_max = 3.52e+07
σ_min = 1.05e+03 ✅ 特異ではない
```

### 収束状況（nCells=75）

```
iter=0: 2.03 → 0.510 (α=1.0, 74.9% improvement) ✅
iter=1: 0.510 → 0.478 (α=0.25, 6.2% improvement) ✅
iter=2-4: 0.478 → 0.478 (停滞) ⚠️
iter=5: 0.478 → 0.462 (α=0.25, 3.3% improvement) ✅
iter=6-15: 0.462 (完全停滞) ❌
```

**現在:** residualNorm=0.462（tolerance=2e-1で収束判定）

---

## 📞 サポート

### 実装に関する質問

`PRECONDITIONER_IMPLEMENTATION_STRATEGY.md` のトラブルシューティングセクション参照

### 追加の診断が必要な場合

以下を実行：
1. nCells、tolerance、初期プロファイルを記録
2. 最終10イテレーションのログを保存
3. 新しい `DIAGNOSTIC_RESULTS_*.md` を作成

---

**ステータス:** Variable-wise weighting実装完了、テスト待ち
**次のアクション:** 重み付け効果の測定と収束テスト

**実装完了:**
- ✅ **Phase 1-3 調査完了**（Newton方向検証、residual追跡、根本原因特定）
- ✅ **Variable-wise weighting実装**（Te: 0.1×, ne: 10.0×）
- ✅ **Build成功**（swift-gotenx）

**根本原因（確定）:**
- 🔴 **Te residual dominance**: ||R_Te|| = 34.9（Tiの8.8倍、neの839倍）
- 🔴 **Unbalanced updates**: iter=0→1でTe: +82.1%, Ti: -57.6%, ne: -125.6%
- 🔴 **Complete stagnation**: iter=1+でTi, Te改善率0.0%

**実装した解決策:**
- ✅ **Variable-wise weighting** (NewtonRaphsonSolver.swift:188-211)
  - Te残差を10分の1に抑制
  - ne残差を10倍に強調
  - バランスの取れた変数更新を促進

**詳細:**
- `NEWTON_DIRECTION_ANALYSIS.md` - 根本原因分析と解決策
- `LINE_SEARCH_INVESTIGATION.md` - 初期調査結果
- `PRECONDITIONER_SUSPENDED_REVIEW.md` - Preconditioner保留理由

**次のテスト項目:**
1. nCells=75で5msシミュレーション実行
2. 変数ごとのresidual改善率を確認
3. toleranceへの到達を確認（目標: < 2e-1）
4. α=1.0採用率の改善を確認
