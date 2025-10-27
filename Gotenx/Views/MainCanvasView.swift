//
//  MainCanvasView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import Charts
import GotenxUI
import GotenxCore

struct MainCanvasView: View {
    let simulation: Simulation?
    @Bindable var plotViewModel: PlotViewModel
    @Bindable var logViewModel: LogViewModel
    let isRunning: Bool
    let currentSimulationTime: Float
    let totalSimulationTime: Float
    let liveProfiles: SerializableProfiles?
    let liveDerived: DerivedQuantities?

    @State private var splitRatio: CGFloat = 0.7
    @State private var isDraggingSplitter = false

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height

            VStack(spacing: 0) {
                if let simulation = simulation {
                    // Upper Panel: Plot area
                    ScrollView {
                        if let plotData = plotViewModel.plotData {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)
                                ],
                                spacing: 24
                            ) {
                                // Display selected profile plot types
                                ForEach(Array(plotViewModel.selectedPlotTypes.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { plotType in
                                    GenericProfilePlotView(
                                        plotData: plotData,
                                        plotType: plotType,
                                        timeIndex: plotViewModel.currentTimeIndex,
                                        showLegend: plotViewModel.showLegend,
                                        showGrid: plotViewModel.showGrid,
                                        lineWidth: plotViewModel.lineWidth,
                                        yAxisScale: plotViewModel.yAxisScale
                                    )
                                    .frame(height: 400)
                                }

                                // Display selected time series plots
                                if plotViewModel.showTimeSeriesPlots {
                                    ForEach(Array(plotViewModel.selectedScalarPlots.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { scalarType in
                                        TimeSeriesPlotView(
                                            plotData: plotData,
                                            scalarType: scalarType,
                                            currentTimeIndex: plotViewModel.currentTimeIndex,
                                            showGrid: plotViewModel.showGrid,
                                            lineWidth: plotViewModel.lineWidth,
                                            yAxisScale: plotViewModel.yAxisScale
                                        )
                                        .frame(height: 400)
                                    }
                                }
                            }
                            .padding(24)
                        } else {
                            // Show appropriate message based on simulation status
                            switch simulation.status {
                            case .completed:
                                PlaceholderView(message: "Loading plot data...", showSpinner: true)
                                    .frame(height: 500)
                                    .padding(24)
                                    .task {
                                        await plotViewModel.loadPlotData(for: simulation)
                                    }
                            case .running:
                                if let liveProfiles = liveProfiles {
                                    // 🐛 DEBUG: Log live profiles data
                                    let _ = print("[DEBUG-MainCanvas] liveProfiles received: Ti=\(liveProfiles.ionTemperature.first ?? -1)...\(liveProfiles.ionTemperature.last ?? -1) eV, ne=\(liveProfiles.electronDensity.first ?? -1)...\(liveProfiles.electronDensity.last ?? -1) m^-3, nCells=\(liveProfiles.ionTemperature.count)")

                                    // Show real-time charts during simulation
                                    LazyVGrid(
                                        columns: [
                                            GridItem(.flexible(), spacing: 16),
                                            GridItem(.flexible(), spacing: 16)
                                        ],
                                        spacing: 24
                                    ) {
                                        ForEach(Array(plotViewModel.selectedPlotTypes.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { plotType in
                                            GenericLiveProfilePlotView(
                                                profiles: liveProfiles,
                                                plotType: plotType,
                                                time: currentSimulationTime,
                                                showLegend: plotViewModel.showLegend,
                                                showGrid: plotViewModel.showGrid,
                                                lineWidth: plotViewModel.lineWidth,
                                                yAxisScale: plotViewModel.yAxisScale
                                            )
                                            .frame(height: 400)
                                        }
                                    }
                                    .padding(24)
                                } else {
                                    PlaceholderView(message: "Simulation running...", showSpinner: false)
                                        .frame(height: 500)
                                        .padding(24)
                                }
                            case .paused:
                                PlaceholderView(message: "Simulation paused", showSpinner: false)
                                    .frame(height: 500)
                                    .padding(24)
                            case .failed(let error):
                                PlaceholderView(message: "Simulation failed: \(error)", showSpinner: false)
                                    .frame(height: 500)
                                    .padding(24)
                            case .cancelled:
                                PlaceholderView(message: "Simulation cancelled", showSpinner: false)
                                    .frame(height: 500)
                                    .padding(24)
                            case .draft, .queued:
                                PlaceholderView(message: "Run simulation to view results", showSpinner: false)
                                    .frame(height: 500)
                                    .padding(24)
                            }
                        }
                    }
                    .frame(height: availableHeight * splitRatio)

                    // Draggable Divider
                    DraggableDivider(
                        isDragging: $isDraggingSplitter,
                        splitRatio: $splitRatio,
                        availableHeight: availableHeight
                    )

                    // Lower Panel: Console
                    ConsoleView(
                        logViewModel: logViewModel,
                        plotViewModel: plotViewModel,
                        currentTime: currentSimulationTime,
                        totalTime: totalSimulationTime,
                        isRunning: isRunning
                    )
                    .frame(height: availableHeight * (1 - splitRatio))
                } else {
                    VStack(spacing: 0) {
                        PlaceholderView(message: "Select a simulation", showSpinner: false)
                            .frame(height: availableHeight * splitRatio)
                            .padding(24)

                        DraggableDivider(
                            isDragging: $isDraggingSplitter,
                            splitRatio: $splitRatio,
                            availableHeight: availableHeight
                        )

                        ConsoleView(
                            logViewModel: logViewModel,
                            plotViewModel: plotViewModel,
                            currentTime: 0,
                            totalTime: 1.0,
                            isRunning: false
                        )
                        .frame(height: availableHeight * (1 - splitRatio))
                    }
                }
            }
        }
        .navigationTitle(simulation?.name ?? "Gotenx")
        .onChange(of: simulation?.id) { oldValue, newValue in
            // Clear plot data and logs when simulation changes
            if oldValue != newValue {
                plotViewModel.plotData = nil
                plotViewModel.currentTimeIndex = 0
                logViewModel.clear()
            }
        }
    }
}

struct TemperaturePlotView: View {
    let plotData: PlotData
    let timeIndex: Int
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature Profiles")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("t = \(currentTime, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showLegend {
                    CustomLegend(items: [
                        ("Ion Temperature", Color(red: 1.0, green: 0.3, blue: 0.3)),
                        ("Electron Temperature", Color(red: 0.3, green: 0.6, blue: 1.0))
                    ])
                }
            }

            if timeIndex < plotData.nTime {
                Chart {
                    // Ion temperature - Area + Line
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        AreaMark(
                            x: .value("ρ", rho),
                            yStart: .value("Zero", 0),
                            yEnd: .value("Ti", plotData.Ti[timeIndex][index])
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.3),
                                    Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(
                            x: .value("ρ", rho),
                            y: .value("Ti", plotData.Ti[timeIndex][index])
                        )
                        .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    // Electron temperature - Area + Line
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        AreaMark(
                            x: .value("ρ", rho),
                            yStart: .value("Zero", 0),
                            yEnd: .value("Te", plotData.Te[timeIndex][index])
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3),
                                    Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(
                            x: .value("ρ", rho),
                            y: .value("Te", plotData.Te[timeIndex][index])
                        )
                        .foregroundStyle(Color(red: 0.3, green: 0.6, blue: 1.0))
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                            .foregroundStyle(.quaternary)
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                            .foregroundStyle(.quaternary)
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartXAxisLabel("Normalized Radius ρ", alignment: .center)
                .chartYAxisLabel("Temperature [keV]", alignment: .center)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .animation(.easeInOut(duration: 0.3), value: timeIndex)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        }
    }

    private var currentTime: Float {
        guard timeIndex < plotData.time.count else { return 0 }
        return plotData.time[timeIndex]
    }
}

struct DensityPlotView: View {
    let plotData: PlotData
    let timeIndex: Int
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Electron Density Profile")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("t = \(currentTime, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showLegend {
                    CustomLegend(items: [
                        ("Electron Density", Color(red: 0.2, green: 0.8, blue: 0.4))
                    ])
                }
            }

            if timeIndex < plotData.nTime {
                Chart {
                    // Area fill
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        AreaMark(
                            x: .value("ρ", rho),
                            yStart: .value("Zero", 0),
                            yEnd: .value("ne", plotData.ne[timeIndex][index])
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.3),
                                    Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    // Line
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(
                            x: .value("ρ", rho),
                            y: .value("ne", plotData.ne[timeIndex][index])
                        )
                        .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                            .foregroundStyle(.quaternary)
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                            .foregroundStyle(.quaternary)
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartXAxisLabel("Normalized Radius ρ", alignment: .center)
                .chartYAxisLabel("Density [10²⁰ m⁻³]", alignment: .center)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .animation(.easeInOut(duration: 0.3), value: timeIndex)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        }
    }

    private var currentTime: Float {
        guard timeIndex < plotData.time.count else { return 0 }
        return plotData.time[timeIndex]
    }
}

struct PlaceholderView: View {
    let message: String
    var showSpinner: Bool = false
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                if showSpinner {
                    Circle()
                        .stroke(lineWidth: 3)
                        .foregroundStyle(.quaternary)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.6, blue: 1.0),
                                    Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            .linear(duration: 1.0).repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }

                Image(systemName: iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }

            Text(message)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
        }
        .onAppear {
            if showSpinner {
                isAnimating = true
            }
        }
    }

    private var iconName: String {
        if message.contains("Loading") {
            return "chart.xyaxis.line"
        } else if message.contains("running") || message.contains("paused") {
            return "hourglass"
        } else if message.contains("failed") {
            return "exclamationmark.triangle"
        } else if message.contains("cancelled") {
            return "xmark.circle"
        } else {
            return "play.circle"
        }
    }
}

struct CustomLegend: View {
    let items: [(String, Color)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.1)
                        .frame(width: 16, height: 3)

                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Live Plot Views (Real-time during simulation)

struct LiveTemperaturePlotView: View {
    let profiles: SerializableProfiles
    let time: Float
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature Profiles (Live)")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("t = \(time, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showLegend {
                    CustomLegend(items: [
                        ("Ion Temperature", Color(red: 1.0, green: 0.3, blue: 0.3)),
                        ("Electron Temperature", Color(red: 0.3, green: 0.6, blue: 1.0))
                    ])
                }
            }

            // Generate normalized radial coordinate
            let nCells = profiles.ionTemperature.count
            let rho = (0..<nCells).map { Float($0) / Float(nCells - 1) }

            // Convert temperature from eV to keV
            let Ti_keV = profiles.ionTemperature.map { $0 / 1000.0 }
            let Te_keV = profiles.electronTemperature.map { $0 / 1000.0 }

            Chart {
                // Ion temperature - Area + Line
                ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                    AreaMark(
                        x: .value("ρ", r),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Ti", Ti_keV[index])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.3),
                                Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                    LineMark(
                        x: .value("ρ", r),
                        y: .value("Ti", Ti_keV[index])
                    )
                    .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Electron temperature - Area + Line
                ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                    AreaMark(
                        x: .value("ρ", r),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Te", Te_keV[index])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3),
                                Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                    LineMark(
                        x: .value("ρ", r),
                        y: .value("Te", Te_keV[index])
                    )
                    .foregroundStyle(Color(red: 0.3, green: 0.6, blue: 1.0))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                        .foregroundStyle(.quaternary)
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                        .foregroundStyle(.quaternary)
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("Normalized Radius ρ", alignment: .center)
            .chartYAxisLabel("Temperature [keV]", alignment: .center)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        }
    }
}

struct LiveDensityPlotView: View {
    let profiles: SerializableProfiles
    let time: Float
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Electron Density Profile (Live)")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("t = \(time, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showLegend {
                    CustomLegend(items: [
                        ("Electron Density", Color(red: 0.2, green: 0.8, blue: 0.4))
                    ])
                }
            }

            // Generate normalized radial coordinate
            let nCells = profiles.electronDensity.count
            let rho = (0..<nCells).map { Float($0) / Float(nCells - 1) }

            // Convert density from m^-3 to 10^20 m^-3
            let ne_normalized = profiles.electronDensity.map { $0 / 1e20 }

            Chart {
                // Area fill
                ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                    AreaMark(
                        x: .value("ρ", r),
                        yStart: .value("Zero", 0),
                        yEnd: .value("ne", ne_normalized[index])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.3),
                                Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Line
                ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                    LineMark(
                        x: .value("ρ", r),
                        y: .value("ne", ne_normalized[index])
                    )
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                        .foregroundStyle(.quaternary)
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: showGrid ? 0.5 : 0))
                        .foregroundStyle(.quaternary)
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("Normalized Radius ρ", alignment: .center)
            .chartYAxisLabel("Density [10²⁰ m⁻³]", alignment: .center)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        }
    }
}

struct DraggableDivider: View {
    @Binding var isDragging: Bool
    @Binding var splitRatio: CGFloat
    let availableHeight: CGFloat

    @State private var dragStartRatio: CGFloat = 0
    @State private var isHovering: Bool = false

    var body: some View {
        ZStack {
            // Visible divider line
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            // Hit area (larger for easier grabbing)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 16)
                .contentShape(Rectangle())
        }
        .background(
            Rectangle()
                .fill(isHovering || isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Capture start position only once per drag
                    if !isDragging {
                        dragStartRatio = splitRatio
                    }
                    isDragging = true

                    // Calculate relative delta from start position
                    let delta = value.translation.height / availableHeight
                    splitRatio = max(0.3, min(0.8, dragStartRatio + delta))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        #if os(macOS)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }

    private var dividerColor: Color {
        if isDragging {
            return .accentColor
        } else if isHovering {
            return .gray
        } else {
            return .gray.opacity(0.3)
        }
    }
}
