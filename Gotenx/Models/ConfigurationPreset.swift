//
//  ConfigurationPreset.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import Foundation
import SwiftData

/// Saved configuration preset
@Model
final class ConfigurationPreset {
    var id: UUID
    var name: String
    var configurationData: Data
    var presetDescription: String
    var isBuiltIn: Bool
    var createdAt: Date

    init(name: String, configurationData: Data, description: String = "", isBuiltIn: Bool = false) {
        self.id = UUID()
        self.name = name
        self.configurationData = configurationData
        self.presetDescription = description
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
    }
}
