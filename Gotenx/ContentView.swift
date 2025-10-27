//
//  ContentView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LogViewModel.self) private var logViewModel
    @Query private var workspaces: [Workspace]

    @State private var viewModel: AppViewModel?
    @State private var plotViewModel = PlotViewModel()
    @State private var configViewModel = ConfigViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if let viewModel = viewModel {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    // Sidebar: Simulation list
                    SidebarView(
                        workspace: viewModel.workspace,
                        selectedSimulation: Binding(
                            get: { viewModel.selectedSimulation },
                            set: { viewModel.selectedSimulation = $0 }
                        ),
                        runningSimulation: viewModel.isSimulationRunning ? viewModel.selectedSimulation : nil
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)

                } detail: {
                    // Detail: Main Canvas with Inspector
                    MainCanvasView(
                        simulation: viewModel.selectedSimulation,
                        plotViewModel: plotViewModel,
                        logViewModel: viewModel.logViewModel,
                        isRunning: viewModel.isSimulationRunning,
                        currentSimulationTime: viewModel.currentSimulationTime,
                        totalSimulationTime: viewModel.totalSimulationTime,
                        liveProfiles: viewModel.liveProfiles,
                        liveDerived: viewModel.liveDerived
                    )
                    .toolbar {
                        ToolbarView(
                            viewModel: viewModel,
                            plotViewModel: plotViewModel
                        )
                    }
                    .inspector(isPresented: Binding(
                        get: { viewModel.showInspector },
                        set: { viewModel.showInspector = $0 }
                    )) {
                        // Inspector (context-dependent: trailing column or sheet)
                        InspectorView(
                            simulation: viewModel.selectedSimulation,
                            plotViewModel: plotViewModel
                        )
                        .inspectorColumnWidth(min: 250, ideal: 300, max: 500)
                    }
                }
                .alert("Error", isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button("OK") {
                        viewModel.errorMessage = nil
                    }
                } message: {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                    }
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            // Initialize viewModel with logViewModel from environment
            if viewModel == nil {
                let workspace = workspaces.isEmpty ? Workspace(name: "Default") : workspaces[0]
                var vm = AppViewModel(workspace: workspace, logViewModel: logViewModel)
                vm.modelContext = modelContext
                viewModel = vm

                // Create default workspace if needed
                if workspaces.isEmpty {
                    createDefaultWorkspace()
                }
            }
        }
    }

    private func createDefaultWorkspace() {
        let workspace = Workspace(name: "Default")
        modelContext.insert(workspace)

        do {
            try modelContext.save()
            viewModel?.workspace = workspace
        } catch {
            print("Failed to create default workspace: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Workspace.self, Simulation.self], inMemory: true)
        .environment(LogViewModel())
}
