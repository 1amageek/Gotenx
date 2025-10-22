//
//  SimulationDataStore.swift
//  Gotenx
//
//  Created by Claude Code on 2025/10/22.
//

import Foundation
import GotenxCore
import OSLog

private let logger = Logger(subsystem: "com.gotenx.app", category: "datastore")

/// File-based storage for simulation results
///
/// Stores complete SimulationResult objects (with timeSeries) in JSON files.
/// SwiftData only stores lightweight metadata.
actor SimulationDataStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    enum StorageError: LocalizedError {
        case directoryCreationFailed(URL)
        case fileWriteFailed(URL, Error)
        case fileReadFailed(URL, Error)
        case simulationNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let url):
                return "Failed to create directory at \(url.path)"
            case .fileWriteFailed(let url, let error):
                return "Failed to write file at \(url.path): \(error.localizedDescription)"
            case .fileReadFailed(let url, let error):
                return "Failed to read file at \(url.path): \(error.localizedDescription)"
            case .simulationNotFound(let id):
                return "Simulation \(id.uuidString) not found"
            }
        }
    }

    init() throws {
        // Get Application Support directory
        baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Gotenx/simulations", isDirectory: true)

        // Create base directory
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Configure encoder/decoder
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        logger.info("SimulationDataStore initialized at \(self.baseURL.path)")
    }

    // MARK: - Write Operations

    /// Save complete simulation result
    func saveSimulationResult(_ result: SimulationResult, simulationID: UUID) throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        // Create simulation directory if needed
        if !fileManager.fileExists(atPath: simDir.path) {
            do {
                try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
                logger.debug("Created simulation directory: \(simDir.path)")
            } catch {
                logger.error("Failed to create directory: \(error.localizedDescription)")
                throw StorageError.directoryCreationFailed(simDir)
            }
        }

        let resultFile = simDir.appendingPathComponent("result.json")

        do {
            let data = try encoder.encode(result)
            try data.write(to: resultFile, options: .atomic)
            logger.notice("Saved simulation result: \(simulationID.uuidString)")
        } catch {
            logger.error("Failed to save result: \(error.localizedDescription)")
            throw StorageError.fileWriteFailed(resultFile, error)
        }
    }

    /// Save configuration to human-readable JSON
    func saveConfiguration(_ config: SimulationConfiguration, for simulationID: UUID) throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString, isDirectory: true)

        if !fileManager.fileExists(atPath: simDir.path) {
            try fileManager.createDirectory(at: simDir, withIntermediateDirectories: true)
        }

        let configFile = simDir.appendingPathComponent("config.json")

        do {
            let data = try encoder.encode(config)
            try data.write(to: configFile, options: .atomic)
            logger.debug("Saved configuration for simulation \(simulationID.uuidString)")
        } catch {
            throw StorageError.fileWriteFailed(configFile, error)
        }
    }

    // MARK: - Read Operations

    /// Load complete simulation result
    func loadSimulationResult(simulationID: UUID) throws -> SimulationResult {
        let resultFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("result.json")

        guard fileManager.fileExists(atPath: resultFile.path) else {
            logger.warning("Result file not found for simulation \(simulationID.uuidString)")
            throw StorageError.simulationNotFound(simulationID)
        }

        do {
            let data = try Data(contentsOf: resultFile)
            let result = try decoder.decode(SimulationResult.self, from: data)
            logger.info("Loaded simulation result: \(simulationID.uuidString)")
            return result
        } catch {
            logger.error("Failed to load result: \(error.localizedDescription)")
            throw StorageError.fileReadFailed(resultFile, error)
        }
    }

    /// Load configuration
    func loadConfiguration(simulationID: UUID) throws -> SimulationConfiguration {
        let configFile = baseURL
            .appendingPathComponent(simulationID.uuidString)
            .appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configFile.path) else {
            throw StorageError.simulationNotFound(simulationID)
        }

        do {
            let data = try Data(contentsOf: configFile)
            return try decoder.decode(SimulationConfiguration.self, from: data)
        } catch {
            throw StorageError.fileReadFailed(configFile, error)
        }
    }

    // MARK: - Delete Operations

    /// Delete all data for a simulation
    func deleteSimulation(_ simulationID: UUID) throws {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)

        guard fileManager.fileExists(atPath: simDir.path) else {
            logger.warning("Simulation directory not found: \(simDir.path)")
            return
        }

        do {
            try fileManager.removeItem(at: simDir)
            logger.info("Deleted simulation data: \(simulationID.uuidString)")
        } catch {
            logger.error("Failed to delete simulation: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Utility

    /// Get file size for a simulation
    func getStorageSize(for simulationID: UUID) throws -> Int64 {
        let simDir = baseURL.appendingPathComponent(simulationID.uuidString)

        guard fileManager.fileExists(atPath: simDir.path) else {
            return 0
        }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: simDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }
}
