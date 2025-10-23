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
                Button {
                    viewModel.runSimulation(simulation)
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isSimulationRunning || simulation.status.isRunning)

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
                }
            }
        }

        // Center: Progress
        ToolbarItem(placement: .principal) {
            if viewModel.isSimulationRunning {
                VStack(spacing: 6) {
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
                    }

                    ProgressView(value: viewModel.simulationProgress)
                        .frame(width: 200)
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

                    Text("t = \(viewModel.currentSimulationTime, specifier: "%.3f") / \(viewModel.totalSimulationTime, specifier: "%.3f") s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                }
            }
        }

        // Right: View controls
        ToolbarItemGroup(placement: .automatic) {
            Button {
                viewModel.showSidebar.toggle()
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
            .buttonStyle(.glass)

            Button {
                viewModel.showInspector.toggle()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .buttonStyle(.glass)
        }
    }
}
