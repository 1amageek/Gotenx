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
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.simulationProgress)
                        .frame(width: 200)

                    Text("t = \(viewModel.currentSimulationTime, specifier: "%.3f") / \(viewModel.totalSimulationTime, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
