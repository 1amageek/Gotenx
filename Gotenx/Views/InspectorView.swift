//
//  InspectorView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import GotenxCore

struct InspectorView: View {
    let simulation: Simulation?
    @Bindable var plotViewModel: PlotViewModel

    @State private var selectedTab: InspectorTab = .plot

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Inspector", selection: $selectedTab) {
                Label("Plot", systemImage: "chart.bar").tag(InspectorTab.plot)
                Label("Data", systemImage: "tablecells").tag(InspectorTab.data)
                Label("Config", systemImage: "gearshape").tag(InspectorTab.config)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content
            switch selectedTab {
            case .plot:
                PlotInspectorView(plotViewModel: plotViewModel)
            case .data:
                DataInspectorView(simulation: simulation)
            case .config:
                ConfigInspectorView(simulation: simulation)
            }
        }
        .navigationTitle("Inspector")
    }
}

enum InspectorTab {
    case plot
    case data
    case config
}

struct PlotInspectorView: View {
    @Bindable var plotViewModel: PlotViewModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { plotViewModel.isAnimating },
                    set: { isOn in
                        if isOn {
                            plotViewModel.startAnimation()
                        } else {
                            plotViewModel.stopAnimation()
                        }
                    }
                )) {
                    HStack {
                        Image(systemName: plotViewModel.isAnimating ? "play.circle.fill" : "play.circle")
                            .foregroundStyle(plotViewModel.isAnimating ? .green : .secondary)
                            .imageScale(.medium)

                        Text("Animate")
                    }
                }
                .toggleStyle(.switch)

                if plotViewModel.isAnimating {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speed")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(plotViewModel.animationSpeed, specifier: "%.1f")×")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        Slider(value: $plotViewModel.animationSpeed, in: 0.1...5.0, step: 0.1)
                            .tint(Color(.systemGreen))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Label("Animation", systemImage: "play.rectangle")
            }

            Section {
                Toggle(isOn: $plotViewModel.showLegend) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)

                        Text("Show Legend")
                    }
                }

                Toggle(isOn: $plotViewModel.showGrid) {
                    HStack {
                        Image(systemName: "grid")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)

                        Text("Show Grid")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lineweight")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)

                        Text("Line Width")
                            .font(.subheadline)

                        Spacer()

                        Text("\(plotViewModel.lineWidth, specifier: "%.1f") pt")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $plotViewModel.lineWidth, in: 1.0...5.0, step: 0.5)
                        .tint(Color(.systemBlue))
                }
            } header: {
                Label("Display Options", systemImage: "eye")
            }

            Section {
                Button {
                    plotViewModel.clearCache()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)

                        Text("Clear Cache")
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
                .buttonStyle(.glass)
            } header: {
                Label("Data Management", systemImage: "folder")
            }
        }
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.3), value: plotViewModel.isAnimating)
    }
}

struct DataInspectorView: View {
    let simulation: Simulation?

    var body: some View {
        if let simulation = simulation {
            Form {
                Section {
                    LabeledContent {
                        Text(simulation.name)
                            .fontWeight(.medium)
                    } label: {
                        HStack {
                            Image(systemName: "text.cursor")
                                .foregroundStyle(.secondary)
                            Text("Name")
                        }
                    }

                    LabeledContent {
                        Text(simulation.status.displayText)
                            .fontWeight(.medium)
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(statusColor(for: simulation.status))
                                .imageScale(.small)
                            Text("Status")
                        }
                    }

                    LabeledContent {
                        Text(simulation.createdAt.formatted(date: .numeric, time: .shortened))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text("Created")
                        }
                    }
                } header: {
                    Label("Simulation Info", systemImage: "info.circle")
                }

                Section {
                    LabeledContent {
                        Text("\(simulation.snapshotMetadata.count)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } label: {
                        HStack {
                            Image(systemName: "camera")
                                .foregroundStyle(.secondary)
                            Text("Snapshots")
                        }
                    }

                    if let first = simulation.snapshotMetadata.first,
                       let last = simulation.snapshotMetadata.last {
                        LabeledContent {
                            Text("\(first.time, specifier: "%.3f") - \(last.time, specifier: "%.3f") s")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        } label: {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(.secondary)
                                Text("Time Range")
                            }
                        }
                    }
                } header: {
                    Label("Data Summary", systemImage: "chart.bar.doc.horizontal")
                }

                if let metadata = simulation.snapshotMetadata.last {
                    Section {
                        LabeledContent("Core Ti") {
                            Text("\(metadata.coreTi, specifier: "%.2f") keV")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        LabeledContent("Edge Ti") {
                            Text("\(metadata.edgeTi, specifier: "%.2f") keV")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        LabeledContent("Avg ne") {
                            Text("\(metadata.avgNe, specifier: "%.2f") ×10²⁰ m⁻³")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        LabeledContent("Peak ne") {
                            Text("\(metadata.peakNe, specifier: "%.2f") ×10²⁰ m⁻³")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        if let Ip = metadata.plasmaCurrentMA {
                            LabeledContent("Plasma Current") {
                                Text("\(Ip, specifier: "%.2f") MA")
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }

                        if let Q = metadata.fusionGainQ {
                            LabeledContent("Fusion Gain Q") {
                                Text("\(Q, specifier: "%.2f")")
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Label("Final State", systemImage: "flag.checkered")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            PlaceholderView(message: "No simulation selected")
        }
    }

    private func statusColor(for status: SimulationStatusEnum) -> Color {
        switch status {
        case .draft: return .gray
        case .queued: return .yellow
        case .running: return .green
        case .paused: return .orange
        case .completed: return .blue
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

struct ConfigInspectorView: View {
    let simulation: Simulation?

    var body: some View {
        if let simulation = simulation,
           let configData = simulation.configurationData,
           let config = try? JSONDecoder().decode(SimulationConfiguration.self, from: configData) {

            Form {
                Section {
                    LabeledContent {
                        Text("\(config.time.start, specifier: "%.3f") s")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("Start")
                    }

                    LabeledContent {
                        Text("\(config.time.end, specifier: "%.3f") s")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("End")
                    }

                    LabeledContent {
                        Text("\(config.time.initialDt, specifier: "%.1e") s")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("Initial Δt")
                    }
                } header: {
                    Label("Time Configuration", systemImage: "clock.arrow.circlepath")
                }

                Section {
                    LabeledContent {
                        Text("\(config.runtime.static.mesh.nCells)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } label: {
                        Text("Cells")
                    }

                    LabeledContent {
                        Text("\(config.runtime.static.mesh.majorRadius, specifier: "%.2f") m")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("Major Radius")
                    }

                    LabeledContent {
                        Text("\(config.runtime.static.mesh.minorRadius, specifier: "%.2f") m")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("Minor Radius")
                    }

                    LabeledContent {
                        Text("\(config.runtime.static.mesh.toroidalField, specifier: "%.2f") T")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("Toroidal Field")
                    }
                } header: {
                    Label("Mesh Parameters", systemImage: "grid.circle")
                }

                Section {
                    LabeledContent {
                        Text(config.runtime.dynamic.transport.modelType.rawValue)
                            .fontWeight(.medium)
                    } label: {
                        Text("Model")
                    }
                } header: {
                    Label("Transport", systemImage: "arrow.triangle.swap")
                }

                Section {
                    LabeledContent {
                        Text("\(config.runtime.static.solver.maxIterations)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } label: {
                        Text("Max Iterations")
                    }

                    LabeledContent {
                        let tol = config.runtime.static.solver.effectiveTolerances
                        let relTol = tol.ionTemperature.relativeTolerance
                        return Text("\(relTol, specifier: "%.1e") (relative)")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    } label: {
                        Text("Tolerance")
                    }

                    if config.runtime.static.solver.lineSearchEnabled {
                        LabeledContent {
                            Text("Enabled")
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                        } label: {
                            Text("Line Search")
                        }
                    }
                } header: {
                    Label("Solver Settings", systemImage: "function")
                } footer: {
                    Text("Per-equation tolerances: Ti/Te=10eV, ne=1e17m⁻³, ψ=1mWb absolute")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if let interval = config.output.saveInterval {
                        LabeledContent {
                            Text("\(interval, specifier: "%.3f") s")
                                .fontWeight(.medium)
                                .monospacedDigit()
                        } label: {
                            Text("Save Interval")
                        }
                    }

                    LabeledContent {
                        Text(config.output.format.rawValue.uppercased())
                            .fontWeight(.medium)
                    } label: {
                        Text("Format")
                    }
                } header: {
                    Label("Output Settings", systemImage: "doc.badge.gearshape")
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            PlaceholderView(message: "No configuration available")
        }
    }
}
