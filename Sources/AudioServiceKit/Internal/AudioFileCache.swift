//
// AudioFileCache.swift
// AudioServiceKit
//
// Created by Claude on 2025-10-24.
//

import Foundation
@preconcurrency import AVFoundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Metrics for cache performance monitoring
public struct CacheMetrics: Sendable {
    public var cacheHits: Int
    public var cacheMisses: Int
    public var preloadSuccesses: Int
    public var preloadFailures: Int
    public var instantCuts: Int

    public init(
        cacheHits: Int = 0,
        cacheMisses: Int = 0,
        preloadSuccesses: Int = 0,
        preloadFailures: Int = 0,
        instantCuts: Int = 0
    ) {
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.preloadSuccesses = preloadSuccesses
        self.preloadFailures = preloadFailures
        self.instantCuts = instantCuts
    }

    public var hitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }

    public var preloadSuccessRate: Double {
        let total = preloadSuccesses + preloadFailures
        return total > 0 ? Double(preloadSuccesses) / Double(total) : 0.0
    }
}

/// Minimal cache strategy: current track + async preload
/// Memory footprint: 50-100 MB idle, 100-200 MB peak during crossfade
actor AudioFileCache {
    private let logger = Logger(category: "AudioFileCache")

    // MARK: - State

    /// Currently cached file
    private var currentFile: AVAudioFile?
    private var currentURL: URL?

    /// Preload task for next track
    private var preloadTask: Task<AVAudioFile, Error>?

    /// Performance metrics
    private var metrics: CacheMetrics

    /// Memory warning monitoring task
    private var memoryWarningTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        self.metrics = CacheMetrics()

        // For now, cache clears on manual clear() calls only
    }

    // MARK: - Public API

    /// Get audio file from cache or load from disk
    /// - Parameters:
    ///   - url: File URL to load
    ///   - priority: Task priority for loading (default: .userInitiated)
    /// - Returns: Loaded AVAudioFile instance
    /// - Throws: File loading errors
    func get(url: URL, priority: TaskPriority = .userInitiated) async throws -> AVAudioFile {
        // Cache hit - return immediately
        if currentURL == url, let file = currentFile {
            logger.debug("Cache hit for \(url.lastPathComponent)")
            metrics.cacheHits += 1
            return file
        }

        // Check if preload task completed for this URL
        if let task = preloadTask {
            do {
                let file = try await task.value
                if currentURL == url {
                    logger.debug("Preload success for \(url.lastPathComponent)")
                    metrics.preloadSuccesses += 1
                    return file
                }
            } catch {
                logger.warning("Preload failed: \(error.localizedDescription)")
                metrics.preloadFailures += 1
            }
            preloadTask = nil
        }

        // Cache miss - load from disk with priority
        logger.debug("Cache miss for \(url.lastPathComponent), loading from disk")
        metrics.cacheMisses += 1

        let file = try await Task(priority: priority) {
            try AVAudioFile(forReading: url)
        }.value

        // Update cache
        currentFile = file
        currentURL = url

        return file
    }

    /// Preload audio file asynchronously for future use
    /// - Parameter url: File URL to preload
    func preload(url: URL) async {
        // Cancel existing preload if any
        preloadTask?.cancel()

        // Don't preload if already cached
        if currentURL == url {
            logger.debug("Skipping preload - already cached: \(url.lastPathComponent)")
            return
        }

        logger.debug("Starting preload for \(url.lastPathComponent)")

        // Create new preload task with userInitiated priority
        preloadTask = Task(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            self.currentFile = file
            self.currentURL = url
            return file
        }
    }

    /// Clear cache and cancel preload
    func clear() {
        logger.debug("Clearing cache")
        currentFile = nil
        currentURL = nil
        preloadTask?.cancel()
        preloadTask = nil
    }

    /// Get current cache metrics
    /// - Returns: Copy of current metrics
    func getMetrics() -> CacheMetrics {
        return metrics
    }

    /// Reset metrics (for testing)
    func resetMetrics() {
        metrics = CacheMetrics()
    }

    // MARK: - Memory Warning Handling

    private func monitorMemoryWarnings() async {
        #if canImport(UIKit)
        let notificationName = UIApplication.didReceiveMemoryWarningNotification
        #elseif canImport(AppKit)
        // macOS doesn't have direct memory warning notifications like iOS
        // We could monitor NSProcessInfo.processInfo.systemUptime and memory pressure
        // For now, skip monitoring on macOS
        return
        #else
        return
        #endif

        let notifications = NotificationCenter.default.notifications(named: notificationName)

        for await _ in notifications {
            await handleMemoryWarning()
        }
    }

    private func handleMemoryWarning() async {
        logger.warning("Received memory warning - clearing cache")
        clear()
    }
}
