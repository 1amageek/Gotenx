//
//  CustomLogHandler.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/27.
//

import Foundation
import Logging

/// Custom log handler that bridges swift-log to Gotenx LogViewModel
///
/// This handler intercepts logs from swift-gotenx (SimulationOrchestrator, NewtonRaphsonSolver, etc.)
/// and forwards them to the ConsoleView via LogViewModel.
struct CustomLogHandler: LogHandler {
    // MARK: - Properties

    /// Weak reference to LogViewModel to prevent retain cycles
    weak var logViewModel: LogViewModel?

    /// Logger label (e.g., "com.gotenx.core.orchestrator")
    let label: String

    /// Current log level
    var logLevel: Logger.Level = .debug

    /// Metadata storage
    var metadata = Logger.Metadata()

    // MARK: - Initialization

    init(label: String, logViewModel: LogViewModel?) {
        self.label = label
        self.logViewModel = logViewModel
    }

    // MARK: - LogHandler Protocol

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Extract category from label
        // e.g., "com.gotenx.core.orchestrator" → "Orchestrator"
        let category = extractCategory(from: label)

        // Map swift-log level to LogViewModel level
        let appLevel = mapLogLevel(level)

        // Combine default metadata with message metadata
        let combinedMetadata = self.metadata.merging(metadata ?? [:]) { _, new in new }

        // Format message with metadata if present
        let formattedMessage = formatMessage(message, metadata: combinedMetadata)

        // Forward to LogViewModel on MainActor
        guard let logViewModel = logViewModel else {
            // Fallback to print if LogViewModel is nil
            print("[\(category)] \(formattedMessage)")
            return
        }

        // Use logAsync for high-frequency logs (debug)
        if level == .debug || level == .trace {
            logViewModel.logAsync(formattedMessage, level: appLevel, category: category)
        } else {
            // Use synchronous log for important messages (info, warning, error)
            Task { @MainActor in
                logViewModel.log(formattedMessage, level: appLevel, category: category)
            }
        }
    }

    // MARK: - Helper Methods

    /// Extract category name from logger label
    /// Example: "com.gotenx.core.orchestrator" → "Orchestrator"
    private func extractCategory(from label: String) -> String {
        let components = label.split(separator: ".")
        guard let last = components.last else { return "Core" }
        return String(last).capitalized
    }

    /// Map swift-log level to app LogEntry.LogLevel
    private func mapLogLevel(_ level: Logger.Level) -> LogEntry.LogLevel {
        switch level {
        case .trace, .debug:
            return .debug
        case .info, .notice:
            return .info
        case .warning:
            return .warning
        case .error, .critical:
            return .error
        }
    }

    /// Format message with metadata
    private func formatMessage(_ message: Logger.Message, metadata: Logger.Metadata?) -> String {
        var result = message.description

        // Append metadata if present
        if let metadata = metadata, !metadata.isEmpty {
            let metadataStr = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            result += " | \(metadataStr)"
        }

        return result
    }
}
