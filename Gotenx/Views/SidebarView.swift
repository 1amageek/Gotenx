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
    var runningSimulation: Simulation?  // Current running simulation
    @Environment(\.modelContext) private var modelContext

    /// Simulations sorted by modification date (most recent first)
    private var sortedSimulations: [Simulation] {
        workspace.simulations.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        List(selection: $selectedSimulation) {
            Section("Simulations") {
                ForEach(sortedSimulations) { simulation in
                    SimulationRowView(
                        simulation: simulation,
                        isRunning: runningSimulation?.id == simulation.id
                    )
                    .tag(simulation)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteSimulation(simulation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteSimulations)
            }
        }
        .navigationTitle(workspace.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(ConfigurationPreset.allCases) { preset in
                        Button {
                            createSimulation(with: preset)
                        } label: {
                            Label(preset.rawValue, systemImage: preset.icon)
                        }
                    }
                } label: {
                    Label("New Simulation", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func createSimulation(with preset: ConfigurationPreset) {
        let config = preset.configuration
        guard let configData = try? JSONEncoder().encode(config) else { return }

        let simulation = Simulation(
            name: "New \(preset.rawValue)",
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

    private func deleteSimulation(_ simulation: Simulation) {
        // Remove from workspace and delete from context
        if let index = workspace.simulations.firstIndex(where: { $0.id == simulation.id }) {
            workspace.simulations.remove(at: index)
        }
        modelContext.delete(simulation)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete simulation: \(error)")
        }
    }

    private func deleteSimulations(at offsets: IndexSet) {
        // Get simulations to delete from sorted array
        let simulationsToDelete = offsets.map { sortedSimulations[$0] }

        for simulation in simulationsToDelete {
            deleteSimulation(simulation)
        }
    }
}

struct SimulationRowView: View {
    let simulation: Simulation
    let isRunning: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Only show indicator for running simulation
            if isRunning {
                RunningIndicator()
            } else {
                // Spacer to maintain alignment
                Color.clear
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(simulation.name)
                    .font(.body)
                    .fontWeight(isHovered ? .medium : .regular)

                HStack(spacing: 8) {
                    if !simulation.snapshotMetadata.isEmpty {
                        Text("\(simulation.snapshotMetadata.count) snapshots")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("No data")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            Spacer()

            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

/// Running indicator with pulse animation
struct RunningIndicator: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(Color.green)
                .frame(width: 16, height: 16)
                .blur(radius: 4)
                .opacity(isPulsing ? 0.8 : 0.4)

            // Main indicator
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .shadow(color: Color.green.opacity(0.5), radius: 2, x: 0, y: 1)

            // Pulse animation
            Circle()
                .stroke(Color.green, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0 : 1)
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}
