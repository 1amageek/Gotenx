//
//  LogViewModel.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/23.
//

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

    // Performance optimization: Buffered logging
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
    /// - Note: Optimized to single-pass calculation
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

    /// Add a log entry asynchronously (buffered, use for high-frequency logging)
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
        logBuffer.removeAll()
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
