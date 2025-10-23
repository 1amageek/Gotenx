# Console View Design Specification

**Version**: 1.1 (Corrected)
**Date**: 2025-10-23
**Status**: DESIGN PHASE - REVIEW CORRECTIONS APPLIED

---

## Overview

Xcodeライクな縦分割コンソールビューを実装し、シミュレーション実行状況をリアルタイムで表示します。

### Goals

- シミュレーション実行の可視化
- デバッグとトラブルシューティングの容易化
- Xcodeに慣れた開発者への親和性

---

## Review Corrections Applied (v1.1)

The following critical issues identified in the design review have been corrected:

### Critical Fixes
1. **✅ DraggableDivider cumulative offset bug** - Added `dragStartRatio` state to capture initial position and calculate relative delta
2. **✅ MainCanvasView layout calculation** - Now accounts for TimeSlider height with `availableHeight` calculation
3. **✅ iOS compatibility** - Wrapped NSCursor code in `#if os(macOS)` guard

### High Priority
4. **✅ Codable documentation** - Added explicit documentation for LogEntry Codable requirement
5. **✅ Buffered logging** - Added `logAsync()` method with buffer and flush logic to reduce MainActor hopping
6. **✅ Auto-scroll monitoring** - Changed from `entries.count` to `entries.last?.id` to detect replacements

### Medium Priority
7. **✅ Liquid Glass integration** - Applied `.buttonStyle(.glass)` to LevelFilterButton
8. **✅ Color constants** - Added `Color+Gotenx.swift` documentation for centralized color management
9. **✅ Statistics optimization** - Replaced 4 separate filters with single-loop implementation
10. **✅ Time estimate** - Updated from 5-9h to realistic 12-18h based on complexity analysis

---

## Architecture

### Component Structure

```
MainCanvasView (縦分割)
├── Upper Panel (70%)
│   ├── ScrollView
│   │   ├── TemperaturePlotView
│   │   └── DensityPlotView
│   └── TimeSliderView (fixed)
│
├── Draggable Divider
│
└── Lower Panel (30%)
    └── ConsoleView
        ├── ConsoleToolbar
        │   ├── Level Filter Toggles
        │   ├── Search Field
        │   ├── Auto-scroll Toggle
        │   └── Clear Button
        └── ScrollView
            └── LazyVStack
                └── LogEntryRow[]
```

### Data Flow

```
AppViewModel
    ├─> logViewModel.log() ──> LogViewModel
    │                              │
    │                              ├─> entries: [LogEntry]
    │                              ├─> filteredEntries (computed)
    │                              └─> filters, search
    │
    └─> Simulation execution
        ├─> Start: log("Starting...", .info)
        ├─> Progress: log("Step 50/200", .debug)
        ├─> Error: log("Failed: ...", .error)
        └─> Complete: log("✓ Completed", .info)
```

---

## 1. Data Models

### 1.1 LogEntry

**File**: `Gotenx/Models/LogEntry.swift`

```swift
import Foundation
import SwiftUI

/// Single log entry
/// - Note: Codable conformance is required for log export/persistence features
struct LogEntry: Identifiable, Codable, Equatable {  // ✅ Codable required for log export
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

extension LogEntry {
    enum LogLevel: String, Codable, CaseIterable, Identifiable {
        case debug = "Debug"
        case info = "Info"
        case warning = "Warning"
        case error = "Error"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .debug: return .secondary
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }

        var priority: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            }
        }
    }
}
```

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `id` | UUID | Unique identifier for SwiftUI identity |
| `timestamp` | Date | Log creation time |
| `level` | LogLevel | Severity level (debug/info/warning/error) |
| `category` | String | Source category (e.g., "Simulation", "Storage") |
| `message` | String | Log message content |

**LogLevel Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `color` | Color | Display color for the level |
| `icon` | String | SF Symbol name |
| `priority` | Int | Sorting priority (0=lowest, 3=highest) |

---

### 1.2 Color Extensions

**File**: `Gotenx/Extensions/Color+Gotenx.swift`

```swift
import SwiftUI

/// ✅ Centralized color constants for Gotenx UI
/// - Note: Reduces duplication and ensures consistent theming
extension Color {
    // Plot colors (matching existing MainCanvasView)
    static let gotenxRed = Color(red: 1.0, green: 0.3, blue: 0.3)      // Ion temperature
    static let gotenxBlue = Color(red: 0.3, green: 0.6, blue: 1.0)     // Electron temperature
    static let gotenxGreen = Color(red: 0.2, green: 0.8, blue: 0.4)    // Density
}
```

**Usage Example:**

```swift
// Before (in MainCanvasView):
.foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))

// After:
.foregroundStyle(.gotenxRed)
```

**Rationale:**
- Eliminates hardcoded RGB values throughout the codebase
- Simplifies future theme changes
- Improves code readability

---

## 2. View Models

### 2.1 LogViewModel

**File**: `Gotenx/ViewModels/LogViewModel.swift`

```swift
import SwiftUI
import Observation
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "console")

@MainActor
@Observable
final class LogViewModel {
    // MARK: - Properties

    /// All log entries
    private(set) var entries: [LogEntry] = []

    /// Active level filters
    var filteredLevels: Set<LogEntry.LogLevel> = Set(LogEntry.LogLevel.allCases)

    /// Search query
    var searchText: String = ""

    /// Auto-scroll to latest entry
    var autoScroll: Bool = true

    /// Maximum entries to keep (memory management)
    var maxEntries: Int = 1000

    // ✅ Performance optimization: Buffered logging
    private var logBuffer: [LogEntry] = []
    private var lastFlushTime: Date = Date()
    private let flushInterval: TimeInterval = 0.3  // 300ms flush interval

    // MARK: - Computed Properties

    /// Filtered and searched entries
    var filteredEntries: [LogEntry] {
        entries
            .filter { filteredLevels.contains($0.level) }
            .filter {
                searchText.isEmpty ||
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
    }

    /// Statistics for toolbar
    /// - Note: ✅ Optimized to single-pass calculation
    var statistics: LogStatistics {
        var levelCounts = [LogEntry.LogLevel: Int]()
        for entry in entries {
            levelCounts[entry.level, default: 0] += 1
        }
        return LogStatistics(
            total: entries.count,
            debug: levelCounts[.debug] ?? 0,
            info: levelCounts[.info] ?? 0,
            warning: levelCounts[.warning] ?? 0,
            error: levelCounts[.error] ?? 0
        )
    }

    // MARK: - Methods

    /// Add a log entry (synchronous, use for UI operations)
    func log(
        _ message: String,
        level: LogEntry.LogLevel = .info,
        category: String = "App"
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message
        )

        entries.append(entry)

        // Trim old entries
        if entries.count > maxEntries {
            let removeCount = entries.count - maxEntries
            entries.removeFirst(removeCount)
            logger.debug("Trimmed \(removeCount) old log entries")
        }

        // Also log to OSLog for system-level debugging
        switch level {
        case .debug:
            logger.debug("[\(category)] \(message)")
        case .info:
            logger.info("[\(category)] \(message)")
        case .warning:
            logger.warning("[\(category)] \(message)")
        case .error:
            logger.error("[\(category)] \(message)")
        }
    }

    /// ✅ Add a log entry asynchronously (buffered, use for high-frequency logging)
    /// - Note: Reduces MainActor hopping overhead by batching log entries
    nonisolated func logAsync(
        _ message: String,
        level: LogEntry.LogLevel = .info,
        category: String = "App"
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message
        )

        Task { @MainActor in
            logBuffer.append(entry)

            // Flush buffer if threshold reached or time elapsed
            if logBuffer.count >= 10 || Date().timeIntervalSince(lastFlushTime) > flushInterval {
                flushBuffer()
            }
        }
    }

    /// Flush buffered log entries to main entries array
    private func flushBuffer() {
        guard !logBuffer.isEmpty else { return }

        entries.append(contentsOf: logBuffer)
        logBuffer.removeAll(keepingCapacity: true)
        lastFlushTime = Date()

        // Trim old entries if needed
        if entries.count > maxEntries {
            let removeCount = entries.count - maxEntries
            entries.removeFirst(removeCount)
            logger.debug("Trimmed \(removeCount) old log entries during flush")
        }
    }

    /// Clear all entries
    func clear() {
        entries.removeAll()
        logger.info("Console cleared")
    }

    /// Toggle level filter
    func toggleLevel(_ level: LogEntry.LogLevel) {
        if filteredLevels.contains(level) {
            filteredLevels.remove(level)
        } else {
            filteredLevels.insert(level)
        }
    }

    /// Export logs to file
    func exportLogs() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return entries.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }
}

struct LogStatistics {
    let total: Int
    let debug: Int
    let info: Int
    let warning: Int
    let error: Int
}
```

**Key Methods:**

| Method | Description |
|--------|-------------|
| `log(_:level:category:)` | Add new log entry with optional level and category |
| `clear()` | Remove all log entries |
| `toggleLevel(_:)` | Toggle visibility of specific log level |
| `exportLogs()` | Export all logs as formatted string |

---

## 3. UI Components

### 3.1 ConsoleView

**File**: `Gotenx/Views/ConsoleView.swift`

```swift
import SwiftUI

struct ConsoleView: View {
    @Bindable var logViewModel: LogViewModel
    @State private var hoveredEntry: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ConsoleToolbar(logViewModel: logViewModel)

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
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
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .background(Color(nsColor: .textBackgroundColor))
                // ✅ FIXED: Monitor last entry ID instead of count (detects replacements)
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
    }
}
```

### 3.2 ConsoleToolbar

```swift
struct ConsoleToolbar: View {
    @Bindable var logViewModel: LogViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Level filter toggles (✅ Liquid Glass style applied)
            ForEach(LogEntry.LogLevel.allCases) { level in
                LevelFilterButton(
                    level: level,
                    isActive: logViewModel.filteredLevels.contains(level),
                    count: levelCount(level)
                ) {
                    logViewModel.toggleLevel(level)
                }
                .buttonStyle(.glass)  // ✅ Liquid Glass integration
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

            Spacer()

            // Statistics
            Text("\(logViewModel.filteredEntries.count)/\(logViewModel.entries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

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

    private func levelCount(_ level: LogEntry.LogLevel) -> Int {
        logViewModel.entries.filter { $0.level == level }.count
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
```

### 3.3 LogEntryRow

```swift
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
```

---

## 4. Integration

### 4.1 MainCanvasView Modifications

**File**: `Gotenx/Views/MainCanvasView.swift`

```swift
struct MainCanvasView: View {
    let simulation: Simulation?
    @Bindable var plotViewModel: PlotViewModel
    @Bindable var logViewModel: LogViewModel  // ✅ NEW
    let isRunning: Bool

    @AppStorage("consoleSplitRatio") private var splitRatio: CGFloat = 0.7  // ✅ Persistent split ratio
    @State private var isDraggingSplitter = false

    var body: some View {
        GeometryReader { geometry in
            // ✅ FIXED: Calculate available height excluding TimeSlider
            let hasTimeSlider = plotViewModel.plotData != nil
            let timeSliderHeight: CGFloat = 72
            let availableHeight = geometry.size.height - (hasTimeSlider ? timeSliderHeight : 0)

            VStack(spacing: 0) {
                if let simulation = simulation {
                    // Upper Panel: Plots
                    ScrollView {
                        VStack(spacing: 32) {
                            // ... existing plot code
                        }
                        .padding(24)
                    }
                    .frame(height: availableHeight * splitRatio)  // ✅ Use availableHeight

                    // Draggable Divider
                    DraggableDivider(
                        isDragging: $isDraggingSplitter,
                        splitRatio: $splitRatio,  // ✅ FIXED: Binding to splitRatio
                        availableHeight: availableHeight  // ✅ FIXED: Pass availableHeight
                    )

                    // Lower Panel: Console
                    ConsoleView(logViewModel: logViewModel)
                        .frame(height: availableHeight * (1 - splitRatio))  // ✅ Use availableHeight

                    // Time Slider (excluded from split calculation)
                    if hasTimeSlider, let plotData = plotViewModel.plotData {
                        TimeSliderView(
                            currentIndex: $plotViewModel.currentTimeIndex,
                            timePoints: plotData.time
                        )
                        .frame(height: timeSliderHeight)  // ✅ Fixed height
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial)
                    }
                } else {
                    PlaceholderView(message: "Select a simulation", showSpinner: false)
                }
            }
        }
        .navigationTitle(simulation?.name ?? "Gotenx")
        .onChange(of: simulation?.id) { oldValue, newValue in
            if oldValue != newValue {
                plotViewModel.plotData = nil
                plotViewModel.currentTimeIndex = 0
                logViewModel.clear()  // ✅ Clear logs on simulation change
            }
        }
    }
}

struct DraggableDivider: View {
    @Binding var isDragging: Bool
    @Binding var splitRatio: CGFloat
    let availableHeight: CGFloat

    @State private var dragStartRatio: CGFloat = 0  // ✅ FIXED: Capture initial position

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color.clear)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .fill(.clear)
                    .frame(height: 8)
                    .contentShape(Rectangle())
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // ✅ FIXED: Capture start position only once per drag
                        if !isDragging {
                            dragStartRatio = splitRatio
                        }
                        isDragging = true

                        // ✅ FIXED: Calculate relative delta from start position
                        let delta = value.translation.height / availableHeight
                        splitRatio = max(0.3, min(0.8, dragStartRatio + delta))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            #if os(macOS)  // ✅ FIXED: iOS compatibility
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
    }
}
```

### 4.2 AppViewModel Integration

**File**: `Gotenx/ViewModels/AppViewModel.swift`

```swift
@MainActor
@Observable
final class AppViewModel {
    // ... existing properties

    var logViewModel: LogViewModel = LogViewModel()  // ✅ NEW

    func runSimulation(_ simulation: Simulation) {
        guard simulationTask == nil else {
            logViewModel.log("Cannot start: Another simulation is running", level: .warning, category: "Simulation")
            return
        }

        guard let configData = simulation.configurationData else {
            logViewModel.log("Cannot start: No configuration data", level: .error, category: "Simulation")
            return
        }

        logViewModel.log("Starting simulation: \(simulation.name)", level: .info, category: "Simulation")

        simulationTask = Task {
            defer {
                Task { @MainActor in
                    isSimulationRunning = false
                    simulationTask = nil
                    logViewModel.log("Simulation task cleanup completed", level: .debug, category: "Simulation")
                }
            }

            do {
                logViewModel.log("Decoding configuration...", level: .debug, category: "Config")
                let config = try JSONDecoder().decode(SimulationConfiguration.self, from: configData)

                await MainActor.run {
                    isSimulationRunning = true
                    isPaused = false
                    simulationProgress = 0.0
                    simulation.status = .running(progress: 0.0)
                    totalSimulationTime = config.time.end
                    lastUpdateTime = .distantPast
                }

                logViewModel.log("Simulation initialized (duration: \(config.time.end)s, cells: 100)", level: .info, category: "Simulation")

                // Get data store
                logViewModel.log("Initializing data store...", level: .debug, category: "Storage")
                let store = try getDataStore()

                // Create initial profiles
                logViewModel.log("Creating initial profiles...", level: .debug, category: "Simulation")
                let initialProfiles = createDefaultProfiles(nCells: 100)

                logViewModel.log("⚠ Using placeholder execution (orchestrator not yet integrated)", level: .warning, category: "Simulation")

                // Create placeholder result
                let result = SimulationResult(
                    finalProfiles: initialProfiles,
                    statistics: SimulationStatistics(
                        totalIterations: 0,
                        totalSteps: 0,
                        converged: true,
                        maxResidualNorm: 0.0,
                        wallTime: 0.0
                    ),
                    timeSeries: [
                        TimePoint(
                            time: 0.0,
                            profiles: initialProfiles,
                            derived: nil,
                            diagnostics: nil
                        )
                    ]
                )

                logViewModel.log("Saving simulation results...", level: .info, category: "Storage")
                try await saveResults(simulation: simulation, result: result, store: store)

                logViewModel.log("✓ Simulation completed successfully", level: .info, category: "Simulation")

            } catch is CancellationError {
                await MainActor.run {
                    simulation.status = .cancelled
                    logViewModel.log("⚠ Simulation cancelled by user", level: .warning, category: "Simulation")
                }
            } catch {
                await MainActor.run {
                    simulation.status = .failed(error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    logViewModel.log("✗ Simulation failed: \(error.localizedDescription)", level: .error, category: "Simulation")
                }
            }
        }
    }

    func stopSimulation() {
        guard let task = simulationTask else { return }

        logViewModel.log("Stopping simulation...", level: .warning, category: "Simulation")
        task.cancel()
        isPaused = false

        if let simulation = selectedSimulation {
            simulation.status = .cancelled
        }
    }
}
```

### 4.3 ContentView Binding

**File**: `Gotenx/ContentView.swift`

```swift
MainCanvasView(
    simulation: viewModel.selectedSimulation,
    plotViewModel: plotViewModel,
    logViewModel: viewModel.logViewModel,  // ✅ NEW
    isRunning: viewModel.isSimulationRunning
)
```

---

## 5. Design Specifications

### 5.1 Layout

| Element | Height | Constraints |
|---------|--------|-------------|
| Upper Panel (Plots) | 70% (default) | 30% - 80% |
| Divider | 1px + 8px hitbox | Fixed |
| Lower Panel (Console) | 30% (default) | 20% - 70% |
| Time Slider | Fixed | Always at bottom |

### 5.2 Colors

| Level | Foreground | Background |
|-------|-----------|------------|
| Debug | `.secondary` | `.secondary.opacity(0.15)` |
| Info | `.primary` | `.primary.opacity(0.15)` |
| Warning | `.orange` | `.orange.opacity(0.15)` |
| Error | `.red` | `.red.opacity(0.15)` |

### 5.3 Typography

| Element | Font |
|---------|------|
| Log entries | `.caption`, `.monospaced` |
| Toolbar | `.caption`, `.system` |
| Timestamp | `.caption`, `.monospaced` |
| Category | `.caption`, `.monospaced` |

### 5.4 Icons (SF Symbols)

| Level | Icon |
|-------|------|
| Debug | `ladybug` |
| Info | `info.circle` |
| Warning | `exclamationmark.triangle` |
| Error | `xmark.octagon` |
| Auto-scroll | `arrow.down.to.line` |
| Clear | `trash` |
| Search | `magnifyingglass` |

---

## 6. Behavior Specifications

### 6.1 Auto-scroll

- **Default**: ON
- **Trigger**: New entry added
- **Condition**: Only if user hasn't manually scrolled away
- **Animation**: `.easeOut(duration: 0.2)`

### 6.2 Level Filtering

- **Default**: All levels visible
- **Toggle**: Click level button to show/hide
- **Visual**: Active filters highlighted with colored background
- **Persistence**: Filters remain active across simulations

### 6.3 Search

- **Target**: Message and category text
- **Match**: Case-insensitive substring
- **Clear**: X button appears when text entered
- **Performance**: Computed property (no debouncing needed for <1000 entries)

### 6.4 Splitter Dragging

- **Cursor**: `resizeUpDown` on hover
- **Range**: 30% - 80% for upper panel
- **Visual**: Blue highlight while dragging
- **Hitbox**: 8px tall (1px visible divider + padding)

### 6.5 Entry Limit

- **Maximum**: 1000 entries
- **Behavior**: FIFO (remove oldest when limit reached)
- **Notification**: Debug log when trimming occurs

---

## 7. Performance Considerations

### 7.1 Lazy Loading

```swift
LazyVStack {
    ForEach(logViewModel.filteredEntries) { entry in
        LogEntryRow(entry: entry)
    }
}
```

**Rationale**: Only render visible entries for large log files.

### 7.2 Computed Filtering

```swift
var filteredEntries: [LogEntry] {
    entries
        .filter { filteredLevels.contains($0.level) }
        .filter { searchText.isEmpty || ... }
}
```

**Performance**: O(n) filtering is acceptable for <1000 entries. Consider optimization if performance issues occur.

### 7.3 Memory Management

- Maximum 1000 entries in memory
- Older entries automatically removed
- No persistent storage (logs cleared on app restart)
- Future: Optional log export to file

---

## 8. Future Enhancements

### Phase 2 (Post-MVP)

- [ ] **Export to file** - Save logs as `.log` file
- [ ] **Timestamp format selector** - Relative vs absolute time
- [ ] **Color themes** - Light/dark/custom
- [ ] **Copy selection** - Right-click context menu
- [ ] **Entry detail view** - Click to expand with stack trace
- [ ] **Persistent filters** - Save filter preferences
- [ ] **Log streaming** - Real-time updates during simulation
- [ ] **Performance metrics** - Show FPS, memory usage in console

### Phase 3 (Advanced)

- [ ] **Regular expression search** - Advanced filtering
- [ ] **Log bookmarks** - Mark important entries
- [ ] **Time-based filtering** - Show logs from specific time range
- [ ] **Category management** - Add/remove custom categories
- [ ] **Log replay** - Step through logs with timeline
- [ ] **Multi-simulation logs** - Compare logs from multiple runs

---

## 9. Testing Checklist

### Unit Tests

- [ ] LogViewModel.log() adds entry
- [ ] LogViewModel.clear() removes all entries
- [ ] LogViewModel.toggleLevel() updates filter
- [ ] LogViewModel.filteredEntries returns correct subset
- [ ] LogViewModel enforces maxEntries limit
- [ ] LogEntry.LogLevel colors are correct

### UI Tests

- [ ] Console view renders with mock data
- [ ] Level filter buttons toggle correctly
- [ ] Search field filters entries
- [ ] Auto-scroll works when enabled
- [ ] Clear button removes all entries
- [ ] Splitter drags within bounds (30-80%)
- [ ] Hover effects work on divider
- [ ] Entry rows highlight on hover

### Integration Tests

- [ ] Logs appear when simulation starts
- [ ] Logs clear when simulation changes
- [ ] Error logs show for failed simulations
- [ ] Console persists split ratio across sessions
- [ ] Console toolbar responds to keyboard shortcuts

---

## 10. Implementation Checklist

### Phase 1: Core Models & Extensions (2-3 hours)

- [ ] Create `Models/LogEntry.swift` with Codable support
- [ ] Create `ViewModels/LogViewModel.swift` with buffered logging
- [ ] Create `Extensions/Color+Gotenx.swift`
- [ ] Add unit tests for LogViewModel

### Phase 2: UI Components (3-5 hours)

- [ ] Create `Views/ConsoleView.swift` with auto-scroll fix
- [ ] Implement `ConsoleToolbar` with Liquid Glass styles
- [ ] Implement `LogEntryRow`
- [ ] Implement `LevelFilterButton`
- [ ] Implement `DraggableDivider` with cumulative offset fix

### Phase 3: Integration (2-3 hours)

- [ ] Modify `MainCanvasView.swift` for split view with corrected layout
- [ ] Add `logViewModel` to `AppViewModel`
- [ ] Update `ContentView.swift` bindings
- [ ] Add log calls throughout simulation lifecycle
- [ ] Apply @AppStorage for split ratio persistence

### Phase 4: Polish & Testing (3-5 hours)

- [ ] Test all filter combinations
- [ ] Test splitter edge cases (boundary limits, iOS compatibility)
- [ ] Test with 1000+ entries
- [ ] Verify auto-scroll behavior (replacement detection)
- [ ] Performance test with high-frequency logging
- [ ] Integration test with actual simulations
- [ ] Add keyboard shortcuts (optional)

### Phase 5: Refinement (2-2 hours)

- [ ] Refactor MainCanvasView to use Color+Gotenx constants
- [ ] Add missing error handling
- [ ] Update documentation
- [ ] Code review and cleanup

**Total Estimated Time**: 12-18 hours (revised from 5-9h based on design review)

---

## 11. Example Usage

### Basic Logging

```swift
// In AppViewModel.runSimulation()
logViewModel.log("Starting simulation", level: .info, category: "Simulation")
logViewModel.log("Step 50/200 completed", level: .debug, category: "Progress")
logViewModel.log("High temperature detected", level: .warning, category: "Physics")
logViewModel.log("Convergence failed", level: .error, category: "Solver")
```

### With Context

```swift
logViewModel.log(
    "Mesh initialization: \(config.mesh.nCells) cells, R=\(config.mesh.majorRadius)m",
    level: .info,
    category: "Mesh"
)

logViewModel.log(
    "Transport model: \(config.transport.modelType)",
    level: .info,
    category: "Transport"
)
```

### Error Handling

```swift
catch {
    logViewModel.log(
        "Configuration decode failed: \(error.localizedDescription)",
        level: .error,
        category: "Config"
    )
}
```

---

## 12. References

### Apple Documentation

- [Logger (OSLog)](https://developer.apple.com/documentation/os/logger)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [DragGesture](https://developer.apple.com/documentation/swiftui/draggesture)
- [LazyVStack](https://developer.apple.com/documentation/swiftui/lazyvstack)

### Design Inspiration

- Xcode Console
- Visual Studio Code Output Panel
- Chrome DevTools Console
- Terminal.app

---

**Document Version**: 1.1 (Review Corrections Applied)
**Last Updated**: 2025-10-23
**Status**: ✅ Ready for Implementation - All Review Issues Resolved
