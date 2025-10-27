//
//  ToolbarView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI

struct ToolbarView: ToolbarContent {
    @Bindable var viewModel: AppViewModel
    @Bindable var plotViewModel: PlotViewModel

    var body: some ToolbarContent {
        // Left: Simulation controls
        ToolbarItemGroup(placement: .navigation) {
            if let simulation = viewModel.selectedSimulation {

                GlassEffectContainer {
                    if viewModel.isSimulationRunning {
                        Button {
                            if viewModel.isPaused {
                                viewModel.resumeSimulation()
                            } else {
                                viewModel.pauseSimulation()
                            }
                        } label: {
                            Label(
                                viewModel.isPaused ? "Resume" : "Pause",
                                systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                            )
                        }
                        .buttonStyle(.glass)

                        Button {
                            viewModel.stopSimulation()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button {
                            viewModel.runSimulation(simulation)
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(viewModel.isSimulationRunning || simulation.status.isRunning)
                    }
                }
                .controlSize(.regular)
            }
        }

        // Center: Progress
        ToolbarItem(placement: .principal) {
            if viewModel.isSimulationRunning {
                HStack(spacing: 8) {
                    Text("Running")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)

                    Text("\(Int(viewModel.simulationProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    ProgressView(value: viewModel.simulationProgress)
                        .frame(width: 120)
                        .tint(
                            LinearGradient(
                                colors: [
                                    Color(.systemGreen),
                                    Color(.systemBlue)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                }
            }
        }

        // Right: View controls
        ToolbarItemGroup(placement: .automatic) {
            Button {
                viewModel.showInspector.toggle()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .buttonStyle(.glass)
        }
    }
}
