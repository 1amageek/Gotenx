//
//  LogEntry.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/23.
//

import Foundation
import SwiftUI

/// Single log entry
/// - Note: Codable conformance is required for log export/persistence features
struct LogEntry: Identifiable, Codable, Equatable {
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
