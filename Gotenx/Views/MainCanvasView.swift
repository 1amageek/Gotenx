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
                    VStack(spacing: 20) {
                        if let plotData = plotViewModel.plotData {
                            TemperaturePlotView(
                                plotData: plotData,
                                timeIndex: plotViewModel.currentTimeIndex
                            )
                            .frame(height: 300)

                            DensityPlotView(
                                plotData: plotData,
                                timeIndex: plotViewModel.currentTimeIndex
                            )
                            .frame(height: 300)
                        } else {
                            PlaceholderView(message: "Loading plot data...")
                                .frame(height: 400)
                                .task {
                                    await plotViewModel.loadPlotData(for: simulation)
                                }
                        }
                    }
                    .padding()
                }

                // Time slider
                if let plotData = plotViewModel.plotData {
                    TimeSliderView(
                        currentIndex: $plotViewModel.currentTimeIndex,
                        timePoints: plotData.time
                    )
                    .padding()
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

    var body: some View {
        VStack(alignment: .leading) {
            Text("Temperature Profiles")
                .font(.headline)

            if timeIndex < plotData.nTime {
                Chart {
                    // Ion temperature
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(
                            x: .value("ρ", rho),
                            y: .value("Ti", plotData.Ti[timeIndex][index])
                        )
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Electron temperature
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(
                            x: .value("ρ", rho),
                            y: .value("Te", plotData.Te[timeIndex][index])
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxisLabel("Normalized Radius ρ")
                .chartYAxisLabel("Temperature [keV]")
            }
        }
    }
}

struct DensityPlotView: View {
    let plotData: PlotData
    let timeIndex: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text("Density Profile")
                .font(.headline)

            if timeIndex < plotData.nTime {
                Chart {
                    ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                        LineMark(
                            x: .value("ρ", rho),
                            y: .value("ne", plotData.ne[timeIndex][index])
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxisLabel("Normalized Radius ρ")
                .chartYAxisLabel("Density [10²⁰ m⁻³]")
            }
        }
    }
}

struct TimeSliderView: View {
    @Binding var currentIndex: Int
    let timePoints: [Float]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time: \(currentTime, specifier: "%.3f") s")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { currentIndex = Int($0) }
                ),
                in: 0...Double(max(timePoints.count - 1, 0)),
                step: 1
            )
        }
    }

    private var currentTime: Float {
        guard currentIndex < timePoints.count else { return 0 }
        return timePoints[currentIndex]
    }
}

struct PlaceholderView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
