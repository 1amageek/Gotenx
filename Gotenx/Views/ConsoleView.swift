//
//  ConsoleView.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/23.
//

import SwiftUI
import GotenxUI
import AppKit

struct ConsoleView: View {
    @Bindable var logViewModel: LogViewModel
    @Bindable var plotViewModel: PlotViewModel
    let currentTime: Float
    let totalTime: Float
    let isRunning: Bool
    @State private var hoveredEntry: UUID?
    @State private var displayMode: DisplayMode = .structured
    @State private var showCopySuccess: Bool = false

    enum DisplayMode {
        case structured  // Individual rows with hover effects
        case plainText   // Single text block, easy to copy
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ConsoleToolbar(
                logViewModel: logViewModel,
                plotViewModel: plotViewModel,
                currentTime: currentTime,
                totalTime: totalTime,
                isRunning: isRunning,
                displayMode: $displayMode,
                showCopySuccess: $showCopySuccess
            )

            Divider()

            // Log entries - display based on mode
            ScrollViewReader { proxy in
                ScrollView {
                    if displayMode == .structured {
                        // Structured view with individual rows
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(logViewModel.filteredEntries) { entry in
                                LogEntryRow(
                                    entry: entry,
                                    isHovered: hoveredEntry == entry.id
                                )
                                .id(entry.id)
                                .onHover { hovering in
                                    hoveredEntry = hovering ? entry.id : nil
                                }
                            }
                        }
                    } else {
                        // Plain text view - easy to copy
                        Text(formattedLogsText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .background(Color(nsColor: .textBackgroundColor))
                // Monitor last entry ID instead of count (detects replacements)
                .onChange(of: logViewModel.entries.last?.id) { _, _ in
                    if logViewModel.autoScroll,
                       let lastEntry = logViewModel.filteredEntries.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .topTrailing) {
            // Copy success indicator
            if showCopySuccess {
                Text("Copied!")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.8))
                    .foregroundStyle(.white)
                    .cornerRadius(6)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// Format all filtered logs as plain text
    private var formattedLogsText: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        return logViewModel.filteredEntries.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let levelIcon = entry.level.icon
            return "[\(timestamp)] \(levelIcon) [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
}

struct ConsoleToolbar: View {
    @Bindable var logViewModel: LogViewModel
    @Bindable var plotViewModel: PlotViewModel
    let currentTime: Float
    let totalTime: Float
    let isRunning: Bool
    @Binding var displayMode: ConsoleView.DisplayMode
    @Binding var showCopySuccess: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Level filter toggles (Liquid Glass style applied)
            ForEach(LogEntry.LogLevel.allCases) { level in
                LevelFilterButton(
                    level: level,
                    isActive: logViewModel.filteredLevels.contains(level),
                    count: levelCount(level)
                ) {
                    logViewModel.toggleLevel(level)
                }
                .buttonStyle(.glass)
            }

            Divider()
                .frame(height: 20)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Filter logs...", text: $logViewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)

                if !logViewModel.searchText.isEmpty {
                    Button {
                        logViewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.3))
            .cornerRadius(6)
            .frame(width: 200)

            // Time Slider (Plot time navigation)
            if let plotData = plotViewModel.plotData {
                Divider()
                    .frame(height: 20)

                HStack(spacing: 8) {
                    Text("t = \(currentPlotTime, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(plotViewModel.currentTimeIndex) },
                            set: { plotViewModel.currentTimeIndex = Int($0) }
                        ),
                        in: 0...Double(max(plotData.time.count - 1, 0)),
                        step: 1
                    )
                    .tint(.gotenxBlue)
                    .frame(width: 200)

                    Text("\(plotViewModel.currentTimeIndex + 1)/\(plotData.time.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 50, alignment: .leading)
                }
            } else if isRunning {
                // Show simulation time when running but no plot data yet
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text("t = \(currentTime, specifier: "%.3f") / \(totalTime, specifier: "%.3f") s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3))
                .cornerRadius(6)
            }

            Spacer()

            // Statistics
            Text("\(logViewModel.filteredEntries.count)/\(logViewModel.entries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Divider()
                .frame(height: 20)

            // Display mode toggle
            Button {
                displayMode = displayMode == .structured ? .plainText : .structured
            } label: {
                Image(systemName: displayMode == .structured ? "list.bullet" : "doc.plaintext")
            }
            .buttonStyle(.borderless)
            .help(displayMode == .structured ? "Switch to plain text mode" : "Switch to structured mode")

            // Copy all logs button
            Button {
                copyAllLogs()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy all logs to clipboard")
            .disabled(logViewModel.filteredEntries.isEmpty)

            Divider()
                .frame(height: 20)

            // Auto-scroll toggle
            Toggle(isOn: $logViewModel.autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Auto-scroll to latest log")

            // Clear button
            Button {
                logViewModel.clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear all logs")
            .disabled(logViewModel.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Copy all filtered logs to clipboard
    private func copyAllLogs() {
        // Format filtered entries
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        let text = logViewModel.filteredEntries.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Show success indicator
        withAnimation {
            showCopySuccess = true
        }

        // Hide after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation {
                    showCopySuccess = false
                }
            }
        }
    }

    private func levelCount(_ level: LogEntry.LogLevel) -> Int {
        logViewModel.entries.filter { $0.level == level }.count
    }

    private var currentPlotTime: Float {
        guard let plotData = plotViewModel.plotData,
              plotViewModel.currentTimeIndex < plotData.time.count else {
            return 0
        }
        return plotData.time[plotViewModel.currentTimeIndex]
    }
}

struct LevelFilterButton: View {
    let level: LogEntry.LogLevel
    let isActive: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: level.icon)
                    .font(.caption)

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(isActive ? level.color : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? level.color.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help("\(level.rawValue) logs (\(count))")
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    let isHovered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Level icon
            Image(systemName: entry.level.icon)
                .foregroundStyle(entry.level.color)
                .frame(width: 16)

            // Category
            Text(entry.category)
                .foregroundStyle(.tertiary)
                .frame(width: 100, alignment: .leading)

            // Message
            Text(entry.message)
                .foregroundStyle(entry.level.color.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
