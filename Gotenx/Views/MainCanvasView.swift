//
//  MainCanvasView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import Charts
import GotenxUI

struct MainCanvasView: View {
    let simulation: Simulation?
    @Bindable var plotViewModel: PlotViewModel
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let simulation = simulation {
                // Plot area
                ScrollView {
                    VStack(spacing: 32) {
                        if let plotData = plotViewModel.plotData {
                            TemperaturePlotView(
                                plotData: plotData,
                                timeIndex: plotViewModel.currentTimeIndex,
                                showLegend: plotViewModel.showLegend,
                                showGrid: plotViewModel.showGrid,
                                lineWidth: plotViewModel.lineWidth
                            )
                            .frame(height: 400)

                            DensityPlotView(
                                plotData: plotData,
                                timeIndex: plotViewModel.currentTimeIndex,
                                showLegend: plotViewModel.showLegend,
                                showGrid: plotViewModel.showGrid,
                                lineWidth: plotViewModel.lineWidth
                            )
                            .frame(height: 400)
                        } else {
                            PlaceholderView(message: "Loading plot data...")
                                .frame(height: 500)
                                .task {
                                    await plotViewModel.loadPlotData(for: simulation)
                                }
                        }
                    }
                    .padding(24)
                }

                // Time slider
                if let plotData = plotViewModel.plotData {
                    TimeSliderView(
                        currentIndex: $plotViewModel.currentTimeIndex,
                        timePoints: plotData.time
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                }
            } else {
                PlaceholderView(message: "Select a simulation")
            }
        }
        .navigationTitle(simulation?.name ?? "Gotenx")
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

struct TimeSliderView: View {
    @Binding var currentIndex: Int
    let timePoints: [Float]

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Simulation Time")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("\(currentTime, specifier: "%.3f") s")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { currentIndex = Int($0) }
                ),
                in: 0...Double(max(timePoints.count - 1, 0)),
                step: 1
            )
            .tint(Color(red: 0.3, green: 0.6, blue: 1.0))

            Text("\(currentIndex + 1)/\(timePoints.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var currentTime: Float {
        guard currentIndex < timePoints.count else { return 0 }
        return timePoints[currentIndex]
    }
}

struct PlaceholderView: View {
    let message: String
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
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

                Image(systemName: "chart.xyaxis.line")
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
            isAnimating = true
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
