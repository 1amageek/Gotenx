//
//  Workspace.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import Foundation
import SwiftData

/// Top-level container for simulations and comparisons
@Model
final class Workspace {
    var id: UUID
    var name: String
    var simulations: [Simulation] = []
    var comparisons: [Comparison] = []
    var createdAt: Date
    var modifiedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
