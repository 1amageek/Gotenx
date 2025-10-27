//
//  GenericProfilePlotView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import SwiftUI
import Charts
import GotenxUI
import GotenxCore

/// Generic profile plot view that can display any plot type
struct GenericProfilePlotView: View {
    let plotData: PlotData
    let plotType: PlotType
    let timeIndex: Int
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double
    let yAxisScale: AxisScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and time
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plotType.rawValue)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("t = \(currentTime, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showLegend {
                    CustomLegend(items: plotType.legendItems)
                }
            }

            // Chart
            if timeIndex < plotData.nTime {
                // Check if all data is zero (unimplemented feature)
                let allDataIsZero = plotType.dataFields.allSatisfy { field in
                    let data = field.extractData(from: plotData, at: timeIndex)
                    return data.allSatisfy { $0 == 0 }
                }

                if allDataIsZero {
                    // Show placeholder for unimplemented data
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)

                        Text("Data Not Available")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("This plot type is not yet populated with data from the simulation.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(height: 300)
                } else {
                    Chart {
                        // Plot each data field for this plot type
                        ForEach(Array(plotType.dataFields.enumerated()), id: \.offset) { fieldIndex, field in
                            let data = field.extractData(from: plotData, at: timeIndex)

                        // Area fill
                        ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                            AreaMark(
                                x: .value("ρ", rho),
                                yStart: .value("Zero", 0),
                                yEnd: .value(field.label, data[index])
                            )
                            .foregroundStyle(field.gradient)
                            .interpolationMethod(.catmullRom)
                        }

                        // Line
                        ForEach(Array(plotData.rho.enumerated()), id: \.offset) { index, rho in
                            LineMark(
                                x: .value("ρ", rho),
                                y: .value(field.label, data[index])
                            )
                            .foregroundStyle(field.color)
                            .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                        }
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
                    .chartYAxisLabel(plotType.yAxisLabel, alignment: .center)
                    .chartYScale(type: yAxisScale == .logarithmic ? .log : .linear)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                    }
                    .animation(.easeInOut(duration: 0.3), value: timeIndex)
                }
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

/// Live version for real-time simulation data
struct GenericLiveProfilePlotView: View {
    let profiles: SerializableProfiles
    let plotType: PlotType
    let time: Float
    let showLegend: Bool
    let showGrid: Bool
    let lineWidth: Double
    let yAxisScale: AxisScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(plotType.rawValue) (Live)")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("t = \(time, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showLegend {
                    CustomLegend(items: plotType.legendItems)
                }
            }

            // Generate normalized radial coordinate
            let nCells = profiles.ionTemperature.count
            let rho = (0..<nCells).map { Float($0) / Float(nCells - 1) }

            // Convert data based on plot type
            let datasets = extractLiveData(from: profiles, plotType: plotType)

            Chart {
                ForEach(Array(datasets.enumerated()), id: \.offset) { fieldIndex, dataset in
                    let field = plotType.dataFields[fieldIndex]

                    // Area fill
                    ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                        AreaMark(
                            x: .value("ρ", r),
                            yStart: .value("Zero", 0),
                            yEnd: .value(field.label, dataset[index])
                        )
                        .foregroundStyle(field.gradient)
                        .interpolationMethod(.catmullRom)
                    }

                    // Line
                    ForEach(Array(rho.enumerated()), id: \.offset) { index, r in
                        LineMark(
                            x: .value("ρ", r),
                            y: .value(field.label, dataset[index])
                        )
                        .foregroundStyle(field.color)
                        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    }
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
            .chartYAxisLabel(plotType.yAxisLabel, alignment: .center)
            .chartYScale(type: yAxisScale == .logarithmic ? .log : .linear)
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

    /// Extract and convert live data for the given plot type
    private func extractLiveData(from profiles: SerializableProfiles, plotType: PlotType) -> [[Float]] {
        switch plotType {
        case .temperature:
            // Convert eV to keV
            return [
                profiles.ionTemperature.map { $0 / 1000.0 },
                profiles.electronTemperature.map { $0 / 1000.0 }
            ]

        case .density:
            // Convert m^-3 to 10^20 m^-3
            return [profiles.electronDensity.map { $0 / 1e20 }]

        case .poloidalFlux:
            return [profiles.poloidalFlux]

        default:
            // Other plot types not available in live mode
            // Return zeros as placeholder
            let nCells = profiles.ionTemperature.count
            let zeroData = Array(repeating: Float(0.0), count: nCells)
            return plotType.dataFields.map { _ in zeroData }
        }
    }
}
