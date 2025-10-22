//
//  InspectorView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI

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
            Section("Animation") {
                Toggle("Animate", isOn: Binding(
                    get: { plotViewModel.isAnimating },
                    set: { isOn in
                        if isOn {
                            plotViewModel.startAnimation()
                        } else {
                            plotViewModel.stopAnimation()
                        }
                    }
                ))

                if plotViewModel.isAnimating {
                    VStack(alignment: .leading) {
                        Text("Speed: \(plotViewModel.animationSpeed, specifier: "%.1f")x")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $plotViewModel.animationSpeed, in: 0.1...5.0, step: 0.1)
                    }
                }
            }

            Section("Display") {
                Toggle("Show Legend", isOn: $plotViewModel.showLegend)
                Toggle("Show Grid", isOn: $plotViewModel.showGrid)

                VStack(alignment: .leading) {
                    Text("Line Width: \(plotViewModel.lineWidth, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: $plotViewModel.lineWidth, in: 1.0...5.0, step: 0.5)
                }
            }

            Section {
                Button("Clear Cache") {
                    plotViewModel.clearCache()
                }
                .buttonStyle(.glass)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

struct DataInspectorView: View {
    let simulation: Simulation?

    var body: some View {
        if let simulation = simulation {
            Form {
                Section("Simulation Info") {
                    LabeledContent("Name", value: simulation.name)
                    LabeledContent("Status", value: simulation.status.displayText)
                    LabeledContent("Created", value: simulation.createdAt.formatted(date: .numeric, time: .shortened))
                }

                Section("Snapshots") {
                    LabeledContent("Count", value: "\(simulation.snapshotMetadata.count)")

                    if let first = simulation.snapshotMetadata.first,
                       let last = simulation.snapshotMetadata.last {
                        LabeledContent("Time Range", value: "\(first.time, specifier: "%.3f") - \(last.time, specifier: "%.3f") s")
                    }
                }

                if let metadata = simulation.snapshotMetadata.last {
                    Section("Final State") {
                        LabeledContent("Core Ti", value: "\(metadata.coreTi, specifier: "%.2f") keV")
                        LabeledContent("Edge Ti", value: "\(metadata.edgeTi, specifier: "%.2f") keV")
                        LabeledContent("Avg ne", value: "\(metadata.avgNe, specifier: "%.2f") ×10²⁰ m⁻³")
                        LabeledContent("Peak ne", value: "\(metadata.peakNe, specifier: "%.2f") ×10²⁰ m⁻³")

                        if let Ip = metadata.plasmaCurrentMA {
                            LabeledContent("Plasma Current", value: "\(Ip, specifier: "%.2f") MA")
                        }

                        if let Q = metadata.fusionGainQ {
                            LabeledContent("Fusion Gain Q", value: "\(Q, specifier: "%.2f")")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            PlaceholderView(message: "No simulation selected")
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
                Section("Time") {
                    LabeledContent("Start", value: "\(config.time.start) s")
                    LabeledContent("End", value: "\(config.time.end) s")
                    LabeledContent("Initial Δt", value: "\(config.time.initialDt) s")
                }

                Section("Mesh") {
                    LabeledContent("Cells", value: "\(config.runtime.static.mesh.nCells)")
                    LabeledContent("Major Radius", value: "\(config.runtime.static.mesh.majorRadius) m")
                    LabeledContent("Minor Radius", value: "\(config.runtime.static.mesh.minorRadius) m")
                    LabeledContent("Toroidal Field", value: "\(config.runtime.static.mesh.toroidalField) T")
                }

                Section("Transport") {
                    LabeledContent("Model", value: config.runtime.dynamic.transport.modelType.rawValue)
                }

                Section("Output") {
                    if let interval = config.output.saveInterval {
                        LabeledContent("Save Interval", value: "\(interval) s")
                    }
                    LabeledContent("Format", value: config.output.format.rawValue)
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            PlaceholderView(message: "No configuration available")
        }
    }
}
