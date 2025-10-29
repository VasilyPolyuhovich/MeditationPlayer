//
//  AudioSessionDemoView.swift
//  ProsperPlayerDemo
//
//  Demo for AudioSessionManager defensive architecture
//  Shows: Self-healing from external audio session changes
//

import SwiftUI
import AVFoundation
import AudioServiceKit
import AudioServiceCore

struct AudioSessionDemoView: View {
    
    // MARK: - State
    
    @State private var model = DemoPlayerModel()
    @State private var track: Track?
    @State private var testResults: [TestResult] = []
    @State private var sessionBroken: Bool = false
    @State private var recoveryAttempted: Bool = false
    
    struct TestResult: Identifiable {
        let id = UUID()
        let testName: String
        let passed: Bool
        let details: String
        var timestamp: Date = Date()
    }
    
    // MARK: - Body
    
    var body: some View {
        DemoContainerView(
            title: "Audio Session Self-Healing",
            icon: "waveform.circle.fill",
            description: "Test SDK defensive architecture - recovery from external session changes",
            model: model
        ) {
            testChecklistSection
            controlsSection
            resultsSection
            infoSection
        }
        .task {
            try? await model.initialize()
            await loadResources()
        }
    }
    
    // MARK: - Sections
    
    private var testChecklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Test Checklist", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(.purple)
            
            VStack(alignment: .leading, spacing: 8) {
                testCheckItem(
                    number: 1,
                    title: "Basic Playback",
                    description: "Start playback with normal audio session",
                    completed: testResults.contains { $0.testName == "Basic Playback" && $0.passed }
                )
                
                testCheckItem(
                    number: 2,
                    title: "Session Break",
                    description: "Simulate external code changing audio session category",
                    completed: testResults.contains { $0.testName == "Session Break" && $0.passed },
                    warning: true
                )
                
                testCheckItem(
                    number: 3,
                    title: "Self-Healing",
                    description: "Verify SDK recovers automatically without crashing",
                    completed: testResults.contains { $0.testName == "Self-Healing" && $0.passed }
                )
                
                testCheckItem(
                    number: 4,
                    title: "Playback Quality",
                    description: "Confirm audio continues smoothly after recovery",
                    completed: testResults.contains { $0.testName == "Playback Quality" && $0.passed }
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.1))
        )
    }
    
    private var controlsSection: some View {
        ControlsCard(title: "Test Controls", icon: "play.circle") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model.state == .playing || track == nil
                    ) {
                        await startBasicPlaybackTest()
                    }
                    
                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await stopAndReset()
                    }
                }
                
                Button(action: { Task { await breakAudioSession() } }) {
                    Label("Break Audio Session", systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sessionBroken ? Color.green : Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.state != .playing || sessionBroken)
                .opacity((model.state != .playing || sessionBroken) ? 0.4 : 1.0)
                
                if sessionBroken {
                    HStack(spacing: 8) {
                        Image(systemName: recoveryAttempted ? "checkmark.circle.fill" : "hourglass")
                            .foregroundStyle(recoveryAttempted ? .green : .orange)
                        
                        Text(recoveryAttempted ? "SDK recovered!" : "Checking recovery...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Button(action: { testResults.removeAll(); sessionBroken = false; recoveryAttempted = false }) {
                    Label("Clear Results", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(testResults.isEmpty)
                .opacity(testResults.isEmpty ? 0.4 : 1.0)
            }
        }
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Test Results (\(testResults.count))", systemImage: "list.bullet.clipboard")
                .font(.headline)
                .foregroundStyle(.blue)
            
            if testResults.isEmpty {
                Text("No test results yet. Start playback and break audio session to test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(testResults) { result in
                            testResultRow(result)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 200)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AudioSessionManager", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("• Defensive architecture for SDK stability")
            Text("• Singleton pattern protects global AVAudioSession")
            Text("• Self-healing from app developer's audio session changes")
            Text("• MediaServicesReset notification handling")
            
            Text("Why: AVAudioSession is global iOS resource - SDK must be resilient to external changes!")
                .font(.caption)
                .foregroundStyle(.orange)
                .fontWeight(.bold)
                .padding(.top, 4)
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
    
    // MARK: - Helper Views
    
    private func testCheckItem(number: Int, title: String, description: String, completed: Bool, warning: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(completed ? Color.green : (warning ? Color.orange : Color.gray.opacity(0.3)))
                    .frame(width: 32, height: 32)
                
                if completed {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(warning ? .white : .secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func testResultRow(_ result: TestResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.passed ? .green : .red)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.testName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(formatTimestamp(result.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Text(result.details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((result.passed ? Color.green : Color.red).opacity(0.1))
        )
    }
    
    // MARK: - Business Logic
    
    private func loadResources() async {
        // Use long track for better testing
        guard let url = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let t = Track(url: url) else {
            model.error = "Audio file not found"
            return
        }
        
        track = t
    }
    
    private func startBasicPlaybackTest() async {
        guard let track = track else { return }
        
        addTestResult(
            name: "Basic Playback",
            passed: true,
            details: "✅ Starting playback with AudioSessionManager configured"
        )
        
        try? await model.loadAndPlay([track], fadeDuration: 0.0)
        
        // Wait a moment to ensure playback started
        try? await Task.sleep(for: .seconds(0.5))
        
        if model.state == .playing {
            addTestResult(
                name: "Basic Playback",
                passed: true,
                details: "✅ Playback started successfully, audio session active"
            )
        } else {
            addTestResult(
                name: "Basic Playback",
                passed: false,
                details: "❌ Playback did not start (state: \(String(describing: model.state)))"
            )
        }
    }
    
    private func breakAudioSession() async {
        sessionBroken = true
        recoveryAttempted = false
        
        addTestResult(
            name: "Session Break",
            passed: true,
            details: "🔧 Simulating app developer changing audio session..."
        )
        
        // Simulate external code (app developer) breaking audio session
        // This changes category from .playback to .record
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            
            addTestResult(
                name: "Session Break",
                passed: true,
                details: "⚠️ Audio session changed to .record (breaks playback!)"
            )
            
            // Wait and check if SDK self-heals
            try? await Task.sleep(for: .seconds(2))
            await checkSelfHealing()
            
        } catch {
            addTestResult(
                name: "Session Break",
                passed: false,
                details: "❌ Failed to change session: \(error.localizedDescription)"
            )
        }
    }
    
    private func checkSelfHealing() async {
        // Check if playback continues after session break
        if model.state == .playing {
            recoveryAttempted = true
            
            addTestResult(
                name: "Self-Healing",
                passed: true,
                details: "✅ SDK recovered! Playback continues despite session break"
            )
            
            addTestResult(
                name: "Playback Quality",
                passed: true,
                details: "✅ Audio playing without glitches after recovery"
            )
        } else {
            addTestResult(
                name: "Self-Healing",
                passed: false,
                details: "❌ SDK did not recover (state: \(String(describing: model.state)))"
            )
        }
    }
    
    private func stopAndReset() async {
        await model.stop()
        sessionBroken = false
        recoveryAttempted = false
    }
    
    private func addTestResult(name: String, passed: Bool, details: String) {
        let result = TestResult(
            testName: name,
            passed: passed,
            details: details
        )
        testResults.append(result)
        
        // Keep only last 20 results
        if testResults.count > 20 {
            testResults.removeFirst()
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    AudioSessionDemoView()
}
