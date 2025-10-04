import XCTest
@testable import AudioServiceCore

final class SendableTypesTests: XCTestCase {
    
    func testAudioFormat() {
        let format = AudioFormat(
            sampleRate: 48000.0,
            channelCount: 2,
            bitDepth: 32,
            isInterleaved: false
        )
        
        XCTAssertEqual(format.sampleRate, 48000.0)
        XCTAssertEqual(format.channelCount, 2)
        XCTAssertEqual(format.bitDepth, 32)
        XCTAssertFalse(format.isInterleaved)
    }
    
    func testAudioFormatStandard() {
        let standard = AudioFormat.standard
        
        XCTAssertEqual(standard.sampleRate, 48000.0)
        XCTAssertEqual(standard.channelCount, 2)
        XCTAssertEqual(standard.bitDepth, 32)
        XCTAssertFalse(standard.isInterleaved)
    }
    
    func testPlaybackPosition() {
        let position = PlaybackPosition(
            currentTime: 30.0,
            duration: 120.0
        )
        
        XCTAssertEqual(position.currentTime, 30.0)
        XCTAssertEqual(position.duration, 120.0)
        XCTAssertEqual(position.progress, 0.25, accuracy: 0.001)
        XCTAssertEqual(position.remainingTime, 90.0, accuracy: 0.001)
    }
    
    func testPlaybackPositionProgress() {
        // Start
        let start = PlaybackPosition(currentTime: 0, duration: 100)
        XCTAssertEqual(start.progress, 0.0)
        
        // Middle
        let middle = PlaybackPosition(currentTime: 50, duration: 100)
        XCTAssertEqual(middle.progress, 0.5)
        
        // End
        let end = PlaybackPosition(currentTime: 100, duration: 100)
        XCTAssertEqual(end.progress, 1.0)
        
        // Beyond end
        let beyond = PlaybackPosition(currentTime: 150, duration: 100)
        XCTAssertEqual(beyond.progress, 1.5)
    }
    
    func testPlaybackPositionRemainingTime() {
        let position = PlaybackPosition(currentTime: 45, duration: 120)
        XCTAssertEqual(position.remainingTime, 75.0)
        
        // When current exceeds duration
        let exceeded = PlaybackPosition(currentTime: 130, duration: 120)
        XCTAssertEqual(exceeded.remainingTime, 0.0)
    }
    
    func testTrackInfo() {
        let format = AudioFormat.standard
        let track = TrackInfo(
            title: "Meditation Music",
            artist: "Calm Sounds",
            duration: 600.0,
            format: format
        )
        
        XCTAssertEqual(track.title, "Meditation Music")
        XCTAssertEqual(track.artist, "Calm Sounds")
        XCTAssertEqual(track.duration, 600.0)
        XCTAssertEqual(track.format, format)
    }
    
    func testTrackInfoOptionalFields() {
        let format = AudioFormat.standard
        let track = TrackInfo(
            duration: 300.0,
            format: format
        )
        
        XCTAssertNil(track.title)
        XCTAssertNil(track.artist)
        XCTAssertEqual(track.duration, 300.0)
    }
}
