//
//  ConfigurationEditView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/26.
//

import SwiftUI
import GotenxCore

struct ConfigurationEditView: View {
    @Bindable var configViewModel: ConfigViewModel

    var body: some View {
        Form {
            Section {
                Stepper(value: $configViewModel.cellCount, in: 10...500, step: 10) {
                    HStack {
                        Text("Radial Cells")

                        Spacer()

                        Text("\(configViewModel.cellCount)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = configViewModel.meshValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(error.hasPrefix("Warning") ? .orange : .red)
                }

                HStack {
                    Text("Jacobian Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(configViewModel.cellCount * 4) × \(configViewModel.cellCount * 4)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Estimated Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(configViewModel.estimatedJacobianTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Mesh Parameters", systemImage: "grid.circle")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Major Radius")

                        Spacer()

                        Text("\(configViewModel.majorRadius, specifier: "%.2f") m")
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $configViewModel.majorRadius, in: 1.0...10.0, step: 0.1)
                        .tint(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Minor Radius")

                        Spacer()

                        Text("\(configViewModel.minorRadius, specifier: "%.2f") m")
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $configViewModel.minorRadius, in: 0.5...5.0, step: 0.1)
                        .tint(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Toroidal Field")

                        Spacer()

                        Text("\(configViewModel.toroidalField, specifier: "%.2f") T")
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $configViewModel.toroidalField, in: 1.0...10.0, step: 0.1)
                        .tint(.blue)
                }
            } header: {
                Label("Geometry", systemImage: "circle.hexagongrid")
            }

            Section {
                Stepper(value: $configViewModel.maximumIterations, in: 10...500, step: 10) {
                    HStack {
                        Text("Max Iterations")

                        Spacer()

                        Text("\(configViewModel.maximumIterations)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = configViewModel.solverValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(error.hasPrefix("Warning") ? .orange : .red)
                }

                HStack {
                    Text("Tolerance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("System default")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("Solver Settings", systemImage: "function")
            } footer: {
                Text("Newton-Raphson solver with per-equation tolerances (ionTemperature/electronTemperature: 10eV, electronDensity: 1e17m⁻³, ψ: 1mWb absolute + 0.01% relative). Higher iterations allow more time for convergence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ConfigurationEditView(configViewModel: ConfigViewModel())
}
