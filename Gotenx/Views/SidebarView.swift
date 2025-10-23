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
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            StatusIndicator(status: simulation.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(simulation.name)
                    .font(.body)
                    .fontWeight(isHovered ? .medium : .regular)

                HStack(spacing: 8) {
                    Text(simulation.status.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !simulation.snapshotMetadata.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.quaternary)

                        Text("\(simulation.snapshotMetadata.count) snapshots")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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

struct StatusIndicator: View {
    let status: SimulationStatusEnum
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Glow effect for running status
            if case .running = status {
                Circle()
                    .fill(statusColor)
                    .frame(width: 16, height: 16)
                    .blur(radius: 4)
                    .opacity(isPulsing ? 0.8 : 0.4)
            }

            // Main indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 2, x: 0, y: 1)

            // Pulse animation for running
            if case .running = status {
                Circle()
                    .stroke(statusColor, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
            }
        }
        .frame(width: 20, height: 20)
        .onAppear {
            if case .running = status {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    isPulsing = true
                }
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .draft:
            return Color(.systemGray)
        case .queued:
            return Color(.systemYellow)
        case .running:
            return Color(.systemGreen)
        case .paused:
            return Color(.systemOrange)
        case .completed:
            return Color(.systemBlue)
        case .failed:
            return Color(.systemRed)
        case .cancelled:
            return Color(.systemGray)
        }
    }
}
