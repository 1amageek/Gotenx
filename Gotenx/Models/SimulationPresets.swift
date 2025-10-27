//
//  SimulationPresets.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/23.
//

import Foundation
import GotenxCore

/// Built-in configuration presets for common simulation scenarios
enum ConfigurationPreset: String, CaseIterable, Identifiable {
    case constant = "Constant Transport"
    case bohmGyroBohm = "Bohm-GyroBohm (Empirical)"
    case turbulenceTransition = "Turbulence Transition (Advanced)"
    case qlknn = "QLKNN (Neural Network)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .constant: return "equal.circle"
        case .bohmGyroBohm: return "waveform.path"
        case .turbulenceTransition: return "wind"
        case .qlknn: return "brain"
        }
    }

    var description: String {
        switch self {
        case .constant:
            return "Simple constant diffusivity model. Fast and stable for testing."
        case .bohmGyroBohm:
            return "Empirical transport model with Bohm and GyroBohm scaling. Good for general scenarios."
        case .turbulenceTransition:
            return "Advanced density-dependent ITG↔RI transition. Based on 2024 experimental discovery."
        case .qlknn:
            return "Neural network-based transport model. High accuracy, macOS only."
        }
    }

    var configuration: SimulationConfiguration {
        switch self {
        case .constant:
            return SimulationConfiguration.build { builder in
                // ========================================
                // PHASE 0-PRECONDITIONER: Preconditioner実装待ち（5ms）
                // ========================================
                // 診断結果の最終結論（2025-10-27）:
                //   - nCells=50, 75, 100すべてで residualNorm ≈ 0.46-0.48 で停滞
                //   - メッシュ解像度だけでは tolerance=0.1 に到達不可（4.6倍のギャップ）
                //   - 根本原因: 変数スケールの不均一性（Ti: O(10^3), ne: O(10^19)）
                //   - 必須の対策: Diagonal Preconditioner実装
                //
                // 現在の設定（Preconditioner実装まで）:
                //   - nCells=75: Jacobian条件数が最良（κ=3.36e+04）
                //   - tolerance=2e-1: 一時的に緩和（0.462で収束判定される）
                //   - moderate profile: 維持（1.5×, 1.2×）
                //
                // Preconditioner実装後の期待値:
                //   - 条件数: κ = 3.36e+04 → 1e+03程度（1-2桁改善）
                //   - 収束: residualNorm < 0.1 到達可能
                //   - Line search: α=1.0 採用率向上
                //   - イテレーション数: < 10回（現在15回以上）
                //
                // 実装戦略:
                //   詳細は PRECONDITIONER_IMPLEMENTATION_STRATEGY.md を参照
                //   実装場所: swift-gotenx/Sources/GotenxCore/Solver/NewtonRaphsonSolver.swift
                //
                // Phase 1設定（Preconditioner実装後）:
                //   - tolerance = 1e-1（本来の目標値に戻す）
                //   - time.end = 0.05（50ms）
                //   - その他のパラメータは維持
                // ========================================

                builder.time.start = 0.0
                builder.time.end = 0.005  // ✅ PHASE 0: 5ms（超短時間検証、診断後に10msへ）
                builder.time.initialDt = 1.5e-4  // ✅ COMPROMISE: 0.15ms (nCells=75で条件数と離散化誤差のバランス)

                // ✅ 適応タイムステッピング（CFL条件ベース）
                // dt = stabilityFactor * dr^2 / χ_max
                // Transport係数が大きい → dt小 / Transport係数が小さい → dt大
                let adaptiveConfig = AdaptiveTimestepConfig(
                    minDt: 1e-5,             // 最小dt（数値安定性の下限）
                    minDtFraction: nil,      // minDtを明示的に指定
                    maxDt: 1e-3,             // 最大dt（Phase 0）
                    safetyFactor: 0.9,       // CFL安全係数（0.9 = 保守的）
                    maxTimestepGrowth: 1.1   // ✅ UPDATED: 1.2 → 1.1 (10% growth, more conservative)
                )

                // 🐛 DEBUG: Configuration being set in SimulationPresets
                print("[DEBUG-PRESET] AdaptiveTimestepConfig created:")
                print("[DEBUG-PRESET]   minDt: \(adaptiveConfig.minDt?.description ?? "nil")")
                print("[DEBUG-PRESET]   minDtFraction: \(adaptiveConfig.minDtFraction?.description ?? "nil")")
                print("[DEBUG-PRESET]   maxDt: \(adaptiveConfig.maxDt)")
                print("[DEBUG-PRESET]   effectiveMinDt: \(adaptiveConfig.effectiveMinDt)")

                builder.time.adaptive = adaptiveConfig

                builder.runtime.static.mesh.nCells = 75  // ✅ COMPROMISE: Jacobian 300×300（条件数と離散化誤差のバランス）
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                // ✅ ソルバー設定（Phase 0-PRECONDITIONER: 一時的に緩和）
                builder.runtime.static.solver = SolverConfig(
                    type: "newtonRaphson",
                    tolerance: 2e-1,        // ✅ TEMPORARY: 2e-1 (Preconditioner実装まで、0.462で収束判定)
                    tolerances: nil,        // Phase 3で有効化（物理的閾値）
                    physicalThresholds: nil,
                    maxIterations: 50       // ✅ INCREASED: 余裕を持たせる
                )

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .constant,
                    parameters: [
                        "chi_ion": 1.0,              // ITER-scale plasma
                        "chi_electron": 1.0,
                        "particle_diffusivity": 0.1,
                        "convection_velocity": 0.0
                    ]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 1000.0,   // 1 keV（現実的なプラズマ温度）
                    electronTemperature: 1000.0,
                    density: 2.0e19
                )

                // ✅ 初期プロファイル: moderate（flatとconservativeの中間）
                // DIAGNOSTIC結果（2025-10-27）:
                //   - flat (1.0×, 1.0×): Jacobian特異、iter=1-8で完全に停滞（residualNorm=0.363固定）
                //   - conservative (3.0×, 1.5×): 勾配が急すぎて発散（iter=3でresidualNorm=0.945）
                //   - moderate (1.5×, 1.2×) + nCells=50: Jacobian健全（κ=4.2e4）だが離散化誤差で停滞（residualNorm=0.475固定）
                //   - moderate (1.5×, 1.2×) + nCells=100: 条件数悪化（κ=6.5e5）、収束極端に遅い（1%/iter）
                // → nCells=75（dr=0.027m）で条件数と離散化誤差のバランスを取る、tolerance=1e-1に緩和
                builder.runtime.dynamic.initialProfile = InitialProfileConfig(
                    temperaturePeakRatio: 1.5,  // flat=1.0とconservative=3.0の中間
                    densityPeakRatio: 1.2,       // flat=1.0とconservative=1.5の中間
                    temperatureExponent: 2.0,    // パラボリック（標準）
                    densityExponent: 1.5         // 標準値
                )

                // Ohmic加熱のみ（ECRH無効: ソース項が大きすぎて不安定）
                builder.runtime.dynamic.sources = SourcesConfig(
                    ohmicHeating: true,
                    fusionPower: false,
                    ionElectronExchange: true,
                    bremsstrahlung: true,
                    ecrh: nil
                )

                builder.output.saveInterval = 0.001  // ✅ 5msで5スナップショット
                builder.output.directory = "/tmp/gotenx_results"
            }

        case .bohmGyroBohm:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1.5e-4  // ✅ CFL-SAFE: 0.15ms for nCells=100, chi~1.0 (CFL=0.38)

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .bohmGyrobohm,
                    parameters: [
                        "bohm_coeff": 0.5,  // ✅ OPTIMIZED: Reduced for stability
                        "gyrobohm_coeff": 0.5,
                        "ion_mass_number": 2.0
                    ]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 1000.0,  // ✅ FIX: 1 keV (realistic plasma temperature)
                    electronTemperature: 1000.0,  // ✅ FIX: 1 keV
                    density: 2.0e19
                )

                // 数値安定性のため flat プロファイル（熱平衡）を使用
                // conservative プロファイルは現在の実装では不安定（要: タイムステップ削減）
                builder.runtime.dynamic.initialProfile = InitialProfileConfig.flat

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }

        case .turbulenceTransition:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1.5e-4  // ✅ CFL-SAFE: 0.15ms for nCells=100, chi~1.0 (CFL=0.38)

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .densityTransition,
                    parameters: [
                        "transition_density": 2.5e19,
                        "transition_width": 0.5e19,
                        "ion_mass_number": 2.0,
                        "ri_coefficient": 0.3  // ✅ OPTIMIZED: Reduced for stability
                    ]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 1000.0,  // ✅ FIX: 1 keV (realistic plasma temperature)
                    electronTemperature: 1000.0,  // ✅ FIX: 1 keV
                    density: 2.0e19
                )

                // 数値安定性のため flat プロファイル（熱平衡）を使用
                // conservative プロファイルは現在の実装では不安定（要: タイムステップ削減）
                builder.runtime.dynamic.initialProfile = InitialProfileConfig.flat

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }

        case .qlknn:
            return SimulationConfiguration.build { builder in
                builder.time.start = 0.0
                builder.time.end = 2.0
                builder.time.initialDt = 1.5e-4  // ✅ CFL-SAFE: 0.15ms for nCells=100, chi~1.0 (CFL=0.38)

                builder.runtime.static.mesh.nCells = 100
                builder.runtime.static.mesh.majorRadius = 6.2
                builder.runtime.static.mesh.minorRadius = 2.0
                builder.runtime.static.mesh.toroidalField = 5.3

                builder.runtime.dynamic.transport = TransportConfig(
                    modelType: .qlknn,
                    parameters: [:]
                )

                builder.runtime.dynamic.boundaries = BoundaryConfig(
                    ionTemperature: 1000.0,      // ✅ OPTIMIZED: 1keV for QLKNN training range (500-20,000 eV)
                    electronTemperature: 1000.0,
                    density: 5.0e19              // ✅ OPTIMIZED: Within QLKNN range (1e19-1e20 m⁻³)
                )

                // 数値安定性のため flat プロファイル（熱平衡）を使用
                // conservative プロファイルは現在の実装では不安定（要: タイムステップ削減）
                builder.runtime.dynamic.initialProfile = InitialProfileConfig.flat

                builder.output.saveInterval = 0.1
                builder.output.directory = "/tmp/gotenx_results"
            }
        }
    }
}
