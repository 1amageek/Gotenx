//
//  SidebarView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import SwiftData
import GotenxCore

struct SidebarView: View {
    let workspace: Workspace
    @Binding var selectedSimulation: Simulation?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(selection: $selectedSimulation) {
            Section("Simulations") {
                ForEach(workspace.simulations) { simulation in
                    SimulationRowView(simulation: simulation)
                        .tag(simulation)
                }
                .onDelete(perform: deleteSimulations)
            }
        }
        .navigationTitle(workspace.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    createNewSimulation()
                } label: {
                    Label("New Simulation", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func createNewSimulation() {
        // Create default configuration
        let config = SimulationConfiguration.build { builder in
            builder.time.start = 0.0
            builder.time.end = 2.0
            builder.time.initialDt = 1e-3

            builder.runtime.static.mesh.nCells = 100
            builder.runtime.static.mesh.majorRadius = 3.0
            builder.runtime.static.mesh.minorRadius = 1.0
            builder.runtime.static.mesh.toroidalField = 2.5

            builder.output.saveInterval = 0.1
        }

        guard let configData = try? JSONEncoder().encode(config) else { return }

        let simulation = Simulation(
            name: "New Simulation",
            configurationData: configData
        )
        simulation.workspace = workspace
        workspace.simulations.append(simulation)
        modelContext.insert(simulation)

        do {
            try modelContext.save()
            selectedSimulation = simulation
        } catch {
            print("Failed to create simulation: \(error)")
        }
    }

    private func deleteSimulations(at offsets: IndexSet) {
        for index in offsets {
            let simulation = workspace.simulations[index]
            modelContext.delete(simulation)
            workspace.simulations.remove(at: index)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete simulations: \(error)")
        }
    }
}

struct SimulationRowView: View {
    let simulation: Simulation

    var body: some View {
        HStack {
            StatusIndicator(status: simulation.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(simulation.name)
                    .font(.body)

                Text(simulation.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !simulation.snapshotMetadata.isEmpty {
                Text("\(simulation.snapshotMetadata.count) snapshots")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct StatusIndicator: View {
    let status: SimulationStatusEnum

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch status {
        case .draft:
            return .gray
        case .queued:
            return .yellow
        case .running:
            return .green
        case .paused:
            return .orange
        case .completed:
            return .blue
        case .failed:
            return .red
        case .cancelled:
            return .gray
        }
    }
}
