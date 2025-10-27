//
//  TimeSeriesPlotView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import SwiftUI
import Charts
import GotenxUI

/// Time series plot for scalar quantities
struct TimeSeriesPlotView: View {
    let plotData: PlotData
    let scalarType: ScalarPlotType
    let currentTimeIndex: Int
    let showGrid: Bool
    let lineWidth: Double
    let yAxisScale: AxisScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            chartView
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        }
    }

    private var headerView: some View {
        HStack {
            titleView
            Spacer()
            if let stats = computeStats() {
                statsView(stats)
            }
        }
    }

    private var titleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scalarType.rawValue)
                .font(.title3)
                .fontWeight(.semibold)

            if let currentValue = scalarData[safe: currentTimeIndex] {
                Text("Current: \(currentValue, specifier: "%.3f") at t = \(currentTime, specifier: "%.3f") s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statsView(_ stats: (min: Float, max: Float, avg: Float)) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            statRow(label: "Max:", value: stats.max)
            statRow(label: "Min:", value: stats.min)
            statRow(label: "Avg:", value: stats.avg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
        }
    }

    private func statRow(label: String, value: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private var chartView: some View {
        Chart {
            areaMarks
            lineMarks
            currentTimeMarks
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
        .chartXAxisLabel("Time [s]", alignment: .center)
        .chartYAxisLabel(scalarType.yAxisLabel, alignment: .center)
        .chartYScale(type: yAxisScale == .logarithmic ? .log : .linear)
        .chartPlotStyle { plotArea in
            plotArea
                .background(.ultraThinMaterial)
                .cornerRadius(12)
        }
        .animation(.easeInOut(duration: 0.3), value: currentTimeIndex)
        .frame(height: 300)
    }

    @ChartContentBuilder
    private var areaMarks: some ChartContent {
        ForEach(Array(plotData.time.enumerated()), id: \.offset) { index, time in
            if let value = scalarData[safe: index] {
                AreaMark(
                    x: .value("Time", time),
                    yStart: .value("Zero", 0),
                    yEnd: .value(scalarType.rawValue, value)
                )
                .foregroundStyle(scalarType.gradient)
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(Array(plotData.time.enumerated()), id: \.offset) { index, time in
            if let value = scalarData[safe: index] {
                LineMark(
                    x: .value("Time", time),
                    y: .value(scalarType.rawValue, value)
                )
                .foregroundStyle(scalarType.color)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var currentTimeMarks: some ChartContent {
        if currentTimeIndex < plotData.time.count,
           let currentValue = scalarData[safe: currentTimeIndex] {
            RuleMark(x: .value("Current Time", plotData.time[currentTimeIndex]))
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .annotation(position: .top, alignment: .center) {
                    currentTimeAnnotation
                }

            PointMark(
                x: .value("Time", plotData.time[currentTimeIndex]),
                y: .value(scalarType.rawValue, currentValue)
            )
            .foregroundStyle(.red)
            .symbolSize(100)
        }
    }


    private var currentTimeAnnotation: some View {
        Text("Now")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(.red.opacity(0.8))
            }
            .foregroundStyle(.white)
    }

    private var scalarData: [Float] {
        scalarType.extractData(from: plotData)
    }

    private var currentTime: Float {
        guard currentTimeIndex < plotData.time.count else { return 0 }
        return plotData.time[currentTimeIndex]
    }

    private func computeStats() -> (min: Float, max: Float, avg: Float)? {
        guard !scalarData.isEmpty else { return nil }
        let min = scalarData.min() ?? 0
        let max = scalarData.max() ?? 0
        let avg = scalarData.reduce(0, +) / Float(scalarData.count)
        return (min: min, max: max, avg: avg)
    }
}

// MARK: - Helper Extension

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
