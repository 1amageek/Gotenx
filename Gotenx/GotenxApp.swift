//
//  GotenxApp.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import SwiftUI
import SwiftData
import Logging

@main
struct GotenxApp: App {
    /// Shared LogViewModel for console logging
    /// Created at app level to enable swift-log integration
    @State private var logViewModel = LogViewModel()

    /// Track whether logging has been bootstrapped
    private static var loggingBootstrapped = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            Simulation.self,
            Comparison.self,
            SavedPreset.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(logViewModel)
                .onAppear {
                    // Bootstrap swift-log system on first appearance
                    bootstrapLogging(logViewModel: logViewModel)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Bootstrap swift-log system with custom handler
    /// Connects swift-gotenx logs to ConsoleView via LogViewModel
    private func bootstrapLogging(logViewModel: LogViewModel) {
        // Check if already bootstrapped (onAppear can be called multiple times)
        guard !Self.loggingBootstrapped else {
            return
        }

        LoggingSystem.bootstrap { label in
            CustomLogHandler(label: label, logViewModel: logViewModel)
        }

        Self.loggingBootstrapped = true
    }
}
