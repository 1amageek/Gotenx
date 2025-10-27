# Phase移行ガイド - Newton-Raphson収束最適化（改訂版）

**最終更新:** 2025-10-27
**重要:** 診断結果に基づき、フェーズ体系を全面改訂しました。

---

## 🔬 診断結果の要約

**2025-10-27実施の包括的診断により以下が判明:**

1. **nCells=50, 75, 100すべてで同じ問題が発生**
   - residualNorm ≈ 0.46-0.48 で停滞
   - tolerance=0.1 に到達不可（4.6倍のギャップ）

2. **根本原因: 変数スケールの不均一性**
   - Ti/Te: O(10^3) eV
   - ne: O(10^19) m^-3
   - Jacobianのスケール差: 10^16倍

3. **メッシュ解像度だけでは解決不可**
   - Jacobian条件数は良好（κ=3.36e+04 @ nCells=75）
   - しかしNewton方向が不正確

**結論:** Diagonal Preconditioner実装が必須

詳細は以下を参照:
- `DIAGNOSTIC_RESULTS.md` (nCells=50)
- `DIAGNOSTIC_RESULTS_nCells100.md` (nCells=100)
- `DIAGNOSTIC_RESULTS_nCells75.md` (nCells=75, 最終)

---

## 📊 新しいPhase体系

### Phase 0-PRECONDITIONER（現在）

**目的:** Preconditioner実装まで一時的に動作させる

**設定:**
- nCells: **75** (条件数最良)
- tolerance: **2e-1** (一時的に緩和、0.462で収束判定)
- moderate profile: **1.5×, 1.2×** (維持)
- シミュレーション時間: **5ms**

**状態:** Newton法は動作するが、本来の目標には到達しない

---

## ✅ Phase 0-PRECONDITIONER → Phase 1 移行条件

**Phase 1への移行は Diagonal Preconditioner 実装完了後のみ可能です。**

### Preconditioner実装のチェックリスト

以下を**すべて完了**した場合、Phase 1へ移行可能：

#### 1. 実装完了の確認

- [ ] `NewtonRaphsonSolver.swift` にPreconditioner追加
- [ ] swift-gotenxのビルド成功
- [ ] 実装戦略ドキュメント（`PRECONDITIONER_IMPLEMENTATION_STRATEGY.md`）の全ステップ完了

#### 2. 条件数の改善確認

ログで以下を確認：

```
[DEBUG-JACOBIAN] Condition number (κ): X.XXe+03
```

**期待値:** κ < 1e+04（既存の3.36e+04より1桁以上改善）

**最低条件:** κ < 2e+04（改善傾向あり）

#### 3. 収束性能の改善確認

以下のいずれかを達成：

- [ ] **Option A:** residualNorm < 0.1 到達（本来の目標）
- [ ] **Option B:** residualNorm < 0.2 到達（改善傾向明確）
- [ ] **Option C:** Line search α=1.0 採用率 > 50%（方向が正確化）

#### 4. 安定性の確認

- [ ] NaN/Infが発生しない
- [ ] 発散しない（residualNorm < 10）
- [ ] 計算時間が2倍以内（Preconditionerオーバーヘッド許容範囲）

---

## 🔧 Phase 1 設定（Preconditioner検証、50ms）

**前提:** Preconditioner実装が完了し、Phase 0-PRECONDITIONERの移行条件を満たしている

`SimulationPresets.swift`の`.constant`ケースを以下のように変更：

```swift
// ========================================
// PHASE 1: Preconditioner検証（50ms）
// ========================================
// Preconditioner実装後の初期検証
//   - tolerance=1e-1に戻す（本来の目標値）
//   - time.end=50ms（Phase 0の10倍）
//   - 他のパラメータは維持
// ========================================

builder.time.end = 0.05  // ✅ PHASE 1: 50ms（Preconditioner検証）
builder.time.initialDt = 1.5e-4  // 維持

builder.time.adaptive = AdaptiveTimestepConfig(
    minDt: 1e-5,
    minDtFraction: nil,
    maxDt: 1e-3,  // 維持
    safetyFactor: 0.9,
    maxTimestepGrowth: 1.2
)

builder.runtime.static.mesh.nCells = 75  // 維持

builder.runtime.static.solver = SolverConfig(
    type: "newtonRaphson",
    tolerance: 1e-1,  // ✅ 本来の目標値に戻す（2e-1 → 1e-1）
    maxIterations: 50,  // 維持
    tolerances: nil,
    physicalThresholds: nil
)

// initialProfile, transport, boundaries等は Phase 0と同じ
```

### Phase 1の期待される挙動

- **総ステップ数：** 約300ステップ（dt=1.5e-4, 50ms）
- **Newton収束：** < 10回/ステップ（Preconditionerによる改善）
- **residualNorm:** < 0.1 到達（全ステップ）
- **Line search α:** 1.0 採用率 > 50%
- **総計算時間：** 1-2時間（Preconditionerオーバーヘッド含む）

---

## ✅ Phase 1 → Phase 2 移行条件

### 1. 50ms完走の確認

シミュレーションが `time.end = 0.05` まで到達すること。

### 2. 収束性能の確認

以下を**すべて満たす**こと：

- [ ] **全ステップ**で residualNorm < 0.1 到達
- [ ] 平均Newton収束回数 < 10回/ステップ
- [ ] Line search α=1.0 採用率 > 50%

### 3. 安定性の確認

- [ ] NaN/Infが発生しない
- [ ] 最終10ステップで残差が安定減少
  ```
  [DEBUG-NR] iter=5: residualNorm=8.5e-02  ← tolerance以下
  [DEBUG-NR] iter=6: residualNorm=7.3e-02  ← さらに減少
  ```

### 4. パフォーマンスの確認

- [ ] 計算時間が許容範囲（1ステップ < 30秒）
- [ ] Preconditionerオーバーヘッドが2倍以内

---

## 🚀 Phase 2 設定（実運用：2秒）

`SimulationPresets.swift`の`.constant`ケースを以下のように変更：

```swift
// ========================================
// PHASE 2: 実運用（2秒）
// ========================================
// Preconditioner検証成功後の実運用設定
//   - time.end=2.0s（40倍に延長）
//   - tolerance=5e-2（より厳しく）
//   - maxDt増加、safetyFactor引き上げ（収束安定性確認済み）
// ========================================

builder.time.end = 2.0  // ✅ PHASE 2: フル時間

builder.time.adaptive = AdaptiveTimestepConfig(
    minDt: 1e-5,
    minDtFraction: nil,
    maxDt: 5e-3,  // ✅ より大きく（1e-3 → 5e-3）
    safetyFactor: 0.95,  // ✅ より積極的に（0.9 → 0.95）
    maxTimestepGrowth: 1.5  // ✅ より積極的に（1.2 → 1.5）
)

builder.runtime.static.mesh.nCells = 75  // 維持

builder.runtime.static.solver = SolverConfig(
    type: "newtonRaphson",
    tolerance: 5e-2,  // ✅ より厳しく（1e-1 → 5e-2）
    maxIterations: 50,  // 維持
    tolerances: nil,  // TODO: Phase 3で.iterScaleに変更
    physicalThresholds: nil
)

// moderate profile維持（Preconditionerにより収束可能）
builder.runtime.dynamic.initialProfile = InitialProfileConfig(
    temperaturePeakRatio: 1.5,
    densityPeakRatio: 1.2,
    temperatureExponent: 2.0,
    densityExponent: 1.5
)
```

### Phase 2の期待される挙動

- **総ステップ数：** 約13,000ステップ（dt自動調整により変動）
- **Newton収束：** < 8回/ステップ（Preconditionerによる安定化）
- **residualNorm:** < 5e-2 到達（全ステップ）
- **Line search α:** 1.0 が主流（> 70%）
- **総計算時間：** 5-10時間（Newton収束速度とdt調整に依存）

---

## 🎯 Phase 3（将来）：恒久的最適化

Phase 2で安定稼働が確認できたら、以下の長期改善を実施：

### 1. NumericalTolerancesの有効化

```swift
builder.runtime.static.solver = SolverConfig(
    type: "newtonRaphson",
    tolerance: nil,  // ✅ legacyフィールド廃止
    maxIterations: 20,
    tolerances: .iterScale,  // ✅ 物理的に意味のある閾値
    physicalThresholds: .default
)
```

### 2. swift-gotenxの改善（要検討）

- [ ] vjp()のバッチ化実装（FlattenedState.swift:463の活用）
- [ ] 反復線形ソルバーの活用（HybridLinearSolver拡張）
- [ ] Jacobian計算の高速化（GPU最適化）

### 3. UIの改善

- [ ] Newton収束回数のリアルタイム表示
- [ ] 残差ノルムのグラフ表示
- [ ] Phase移行判定の自動化

---

## 📝 トラブルシューティング

### Phase 0で収束しない場合

**症状：** `Max iterations reached without convergence!` が表示される

**対策：**

1. **toleranceをさらに緩める：**
   ```swift
   tolerance: 5e-2,  // 1e-2 → 5e-2
   maxIterations: 50  // 30 → 50
   ```

2. **dtをさらに小さくする：**
   ```swift
   builder.time.initialDt = 3e-4  // 7e-4 → 3e-4
   ```

3. **初期プロファイルをflatに戻す：**
   ```swift
   builder.runtime.dynamic.initialProfile = .flat
   ```

### Phase 1で時間がかかりすぎる場合

**症状：** 1時間経過しても完了しない

**対策：**

1. **time.endを短縮：**
   ```swift
   builder.time.end = 0.05  // 0.1 → 0.05（50ms）
   ```

2. **nCellsを削減：**
   ```swift
   builder.runtime.static.mesh.nCells = 30  // 50 → 30
   ```

### Phase 2で精度が不足する場合

**症状：** プロファイルが物理的に不自然

**対策：**

1. **toleranceを厳しくする：**
   ```swift
   tolerance: 1e-4,  // 5e-4 → 1e-4
   ```

2. **適応dtのtargetIterationsを増やす：**
   ```swift
   targetIterations: 8,  // 6 → 8（より慎重にdtを増加）
   ```

---

## 📊 Phase別の計算時間見積もり

| Phase | 時間範囲 | 推定ステップ数 | Newton/ステップ | 推定総時間 | 目的 |
|-------|---------|--------------|----------------|-----------|------|
| **Phase 0** | 0-10ms | 14-20 | 10-15回 | **5-15分** | 収束確認 |
| **Phase 1** | 0-100ms | 100-200 | 8-15回 | **30分-2時間** | 安定化確認 |
| **Phase 2** | 0-2秒 | 1000-2000 | 5-10回 | **5-10時間** | 実運用 |

注：ステップ数と総時間はCFL条件（transport係数とグリッド間隔）とNewton収束速度に依存します。

---

## ✅ チェックリスト

### Phase 0完了時

- [ ] 全ステップでNewtonが収束
- [ ] 平均Newton収束回数 < 15回
- [ ] NaN/Inf が発生していない
- [ ] プロットが正常に表示される

### Phase 1完了時

- [ ] 100ms完走
- [ ] 平均Newton収束回数 < 10回
- [ ] dtの自動増加を確認
- [ ] 残差が安定して減少

### Phase 2完了時

- [ ] 2秒完走
- [ ] 物理的に妥当なプロファイル
- [ ] Newton収束が安定（5-8回）
- [ ] 適応dtが効果的に機能

---

**最終更新：** 2025-10-27
**バージョン：** Phase 0-PRECONDITIONER（改訂版）
**ステータス:** Preconditioner実装待ち
**次のアクション:** `PRECONDITIONER_IMPLEMENTATION_STRATEGY.md` に従って実装を開始
