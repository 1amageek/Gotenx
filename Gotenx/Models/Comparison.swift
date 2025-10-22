//
//  Comparison.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import Foundation
import SwiftData

/// Comparison between multiple simulations
@Model
final class Comparison {
    var id: UUID
    var name: String
    var simulationIDs: [UUID] = []
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
