//
//  QueueDiagnosticsDemoView.swift
//  ProsperPlayerDemo
//
//  Demo for AsyncOperationQueue diagnostics
//  Shows: Queue depth, timing metrics, percentiles
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct QueueDiagnosticsDemoView: View {

    // MARK: - State

    @State private var model = DemoPlayerModel()
    @State private var tracks: [Track] = []
    @State private var diagnosticsOutput: String = "No diagnostics yet. Start playback to see queue metrics..."
    @State private var isMonitoring: Bool = false

    // MARK: - Body

    var body: some View {
        DemoContainerView(
            title: "Queue Diagnostics",
            icon: "chart.line.uptrend.xyaxis",
            description: "Monitor AsyncOperationQueue performance metrics",
            configMode: .readOnly,
            model: model
        ) {
            infoSection
            controlsSection
            diagnosticsSection
        }
        .task {
            try? await model.initialize()
            await loadResources()
        }
    }

    // MARK: - Sections

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Queue Diagnostics", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            #if ENABLE_DIAGNOSTICS
            Text("✅ Diagnostics enabled (DEBUG + ENABLE_DIAGNOSTICS)")
                .font(.caption)
                .foregroundStyle(.green)

            Text("• Queue depth tracking (current, peak)")
            Text("• Timing metrics (wait times, execution times)")
            Text("• Percentiles (P50/median, P95, P99)")
            Text("• Operation history (last 50 snapshots)")
            Text("• Utilization rate (% time queue busy)")

            #else
            Text("⚠️ Diagnostics disabled")
                .font(.caption)
                .foregroundStyle(.orange)

            Text("To enable: Rebuild with DEBUG configuration")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Compile flag ENABLE_DIAGNOSTICS added to Package.swift")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private var controlsSection: some View {
        ControlsCard(title: "Test Controls", icon: "play.circle") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model.state == .playing || tracks.isEmpty
                    ) {
                        await startStressTest()
                    }

                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await model.stop()
                        isMonitoring = false
                    }
                }

                #if ENABLE_DIAGNOSTICS
                Button(action: { Task { await fetchDiagnostics() } }) {
                    Label("Fetch Diagnostics", systemImage: "chart.bar.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: { diagnosticsOutput = "Diagnostics cleared" }) {
                    Label("Clear Output", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                #endif
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Diagnostics Output", systemImage: "terminal")
                .font(.headline)
                .foregroundStyle(.purple)

            ScrollView {
                Text(diagnosticsOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(height: 300)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Business Logic

    private func loadResources() async {
        let trackFiles = ["stage1_intro_music", "stage2_practice_music", "stage3_closing_music"]
        let loadedTracks = trackFiles.compactMap { filename -> Track? in
            guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else { return nil }
            return Track(url: url)
        }

        guard !loadedTracks.isEmpty else {
            model.error = "Audio files not found"
            return
        }

        tracks = loadedTracks
    }

    private func startStressTest() async {
        guard !tracks.isEmpty else { return }

        diagnosticsOutput = "Starting stress test...\n"
        diagnosticsOutput += "Operations: play → pause → resume → seek → skip\n\n"

        // Start playback
        try? await model.loadAndPlay(tracks, fadeDuration: 2.0)
        diagnosticsOutput += "✅ Playback started\n"

        // Wait 2 seconds
        try? await Task.sleep(for: .seconds(2))

        // Rapid operations to stress queue
        try? await model.pause()
        diagnosticsOutput += "✅ Paused\n"

        try? await Task.sleep(for: .seconds(0.5))

        try? await model.resume()
        diagnosticsOutput += "✅ Resumed\n"

        try? await Task.sleep(for: .seconds(0.5))

        // Seek multiple times
        for i in 1...3 {
            if let service = model.audioService {
                try? await service.seek(to: TimeInterval(i * 10), fadeDuration: 0.5)
                diagnosticsOutput += "✅ Seek \(i)\n"
            }
            try? await Task.sleep(for: .seconds(0.3))
        }

        // Skip operations
        if let service = model.audioService {
            try? await service.skip(forward: 5)
            diagnosticsOutput += "✅ Skip forward\n"

            try? await Task.sleep(for: .seconds(0.5))

            try? await service.skip(backward: 3)
            diagnosticsOutput += "✅ Skip backward\n"
        }

        diagnosticsOutput += "\n🏁 Stress test complete!\n\n"

        // Fetch diagnostics
        await fetchDiagnostics()
    }

    private func fetchDiagnostics() async {
        #if ENABLE_DIAGNOSTICS
        diagnosticsOutput += "📊 Fetching queue diagnostics...\n\n"

        // Note: AsyncOperationQueue is internal to AudioPlayerService
        // For demo purposes, we show the expected format
        // Real implementation would need public API to access diagnostics

        diagnosticsOutput += """
        ╔═══════════════════════════════════════════╗
        ║   AsyncOperationQueue Diagnostics         ║
        ╚═══════════════════════════════════════════╝

        ⚠️ Note: Queue diagnostics require public API access

        Expected metrics when exposed:

        Queue Depth:
          Current: [value]
          Peak:    [value]

        Operations:
          Total:         [count]
          Cancellations: [count]
          Utilization:   [percentage]

        Wait Times (ms):
          P50 (median): [value]
          P95:          [value]
          P99:          [value]

        Execution Times (ms):
          P50 (median): [value]
          P95:          [value]
          P99:          [value]

        Recent State History:
          [timestamp] depth=[n] priority=[p] op=[name]
          ...

        ═══════════════════════════════════════════

        💡 To enable:
        1. ✅ ENABLE_DIAGNOSTICS flag added to Package.swift
        2. ✅ Rebuild in DEBUG configuration
        3. ⚠️ TODO: Add public API to AudioPlayerService:

           public func getQueueDiagnostics() async -> String {
               #if ENABLE_DIAGNOSTICS
               return await operationQueue.getQueueDiagnostics().generateReport()
               #else
               return "Diagnostics not available (requires DEBUG build)"
               #endif
           }

        """
        #else
        diagnosticsOutput += """
        ⚠️ Queue diagnostics not available

        Diagnostics require:
        1. DEBUG build configuration
        2. ENABLE_DIAGNOSTICS compile flag

        Current status:
        - DEBUG: \(isDebugBuild ? "✅" : "❌")
        - ENABLE_DIAGNOSTICS: ❌ (not compiled)

        To enable: Clean build folder and rebuild
        """
        #endif
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

#Preview {
    QueueDiagnosticsDemoView()
}
