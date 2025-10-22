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
    @Query private var workspaces: [Workspace]

    @State private var viewModel: AppViewModel
    @State private var plotViewModel = PlotViewModel()
    @State private var configViewModel = ConfigViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        // Will be properly initialized in onAppear
        let workspace = Workspace(name: "Default")
        _viewModel = State(initialValue: AppViewModel(workspace: workspace))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left: Sidebar
            SidebarView(
                workspace: viewModel.workspace,
                selectedSimulation: $viewModel.selectedSimulation
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)

        } content: {
            // Center: Main Canvas
            MainCanvasView(
                simulation: viewModel.selectedSimulation,
                plotViewModel: plotViewModel,
                isRunning: viewModel.isSimulationRunning
            )
            .toolbar {
                ToolbarView(
                    viewModel: viewModel,
                    plotViewModel: plotViewModel
                )
            }

        } detail: {
            // Right: Inspector
            if viewModel.showInspector {
                InspectorView(
                    simulation: viewModel.selectedSimulation,
                    plotViewModel: plotViewModel
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 500)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Inject model context
            viewModel.modelContext = modelContext

            // Initialize workspace
            if workspaces.isEmpty {
                createDefaultWorkspace()
            } else {
                viewModel.workspace = workspaces[0]
            }
        }
    }

    private func createDefaultWorkspace() {
        let workspace = Workspace(name: "Default")
        modelContext.insert(workspace)

        do {
            try modelContext.save()
            viewModel.workspace = workspace
        } catch {
            print("Failed to create default workspace: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Workspace.self, Simulation.self], inMemory: true)
}
