//
//  Simulation.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import Foundation
import SwiftData

/// Simulation metadata (lightweight - actual data stored in files)
@Model
final class Simulation {
    var id: UUID
    var name: String
    var configurationData: Data?
    var status: SimulationStatusEnum
    var createdAt: Date
    var modifiedAt: Date
    var tags: [String] = []
    var notes: String = ""

    /// Lightweight snapshot metadata for quick preview
    var snapshotMetadata: [SnapshotMetadata] = []

    /// Final profiles (encoded SerializableProfiles)
    var finalProfiles: Data?

    /// Statistics (encoded SimulationStatistics)
    var statistics: Data?

    /// Reference to workspace
    var workspace: Workspace?

    init(name: String, configurationData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.configurationData = configurationData
        self.status = .draft
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

/// Simulation status enum
enum SimulationStatusEnum: Codable, Equatable {
    case draft
    case queued
    case running(progress: Double)
    case paused(at: Double)
    case completed
    case failed(error: String)
    case cancelled

    var displayText: String {
        switch self {
        case .draft: return "Draft"
        case .queued: return "Queued"
        case .running(let progress): return "Running (\(Int(progress * 100))%)"
        case .paused(let progress): return "Paused (\(Int(progress * 100))%)"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Snapshot metadata (lightweight summary for quick preview)
struct SnapshotMetadata: Codable, Equatable {
    var time: Float
    var index: Int

    // Summary statistics
    var coreTi: Float      // Core ion temperature [keV]
    var edgeTi: Float      // Edge ion temperature [keV]
    var avgNe: Float       // Average density [10^20 m^-3]
    var peakNe: Float      // Peak density [10^20 m^-3]

    // Derived quantities summary
    var plasmaCurrentMA: Float?
    var fusionGainQ: Float?

    var isBookmarked: Bool = false
}
