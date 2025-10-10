import Testing
import Foundation
@testable import AudioServiceCore

/// Test suite: Sendable types for actor-safe data passing
@Suite("Sendable Types")
struct SendableTypesTests {
    
    // MARK: - AudioFormat Tests
    
    @Test("AudioFormat: custom initialization")
    func testAudioFormatCustom() {
        let format = AudioFormat(
            sampleRate: 48000.0,
            channelCount: 2,
            bitDepth: 32,
            isInterleaved: false
        )
        
        #expect(format.sampleRate == 48000.0)
        #expect(format.channelCount == 2)
        #expect(format.bitDepth == 32)
        #expect(format.isInterleaved == false)
    }
    
    @Test("AudioFormat: standard preset")
    func testAudioFormatStandard() {
        let standard = AudioFormat.standard
        
        #expect(standard.sampleRate == 48000.0)
        #expect(standard.channelCount == 2)
        #expect(standard.bitDepth == 32)
        #expect(standard.isInterleaved == false)
    }
    
    @Test("AudioFormat: mono configuration")
    func testAudioFormatMono() {
        let mono = AudioFormat(
            sampleRate: 44100.0,
            channelCount: 1
        )
        
        #expect(mono.channelCount == 1)
        #expect(mono.sampleRate == 44100.0)
    }
    
    @Test("AudioFormat: different sample rates")
    func testAudioFormatSampleRates() {
        let rate44 = AudioFormat(sampleRate: 44100.0, channelCount: 2)
        #expect(rate44.sampleRate == 44100.0)
        
        let rate48 = AudioFormat(sampleRate: 48000.0, channelCount: 2)
        #expect(rate48.sampleRate == 48000.0)
        
        let rate96 = AudioFormat(sampleRate: 96000.0, channelCount: 2)
        #expect(rate96.sampleRate == 96000.0)
    }
    
    @Test("AudioFormat: equatable")
    func testAudioFormatEquatable() {
        let format1 = AudioFormat(sampleRate: 48000, channelCount: 2)
        let format2 = AudioFormat(sampleRate: 48000, channelCount: 2)
        let format3 = AudioFormat(sampleRate: 44100, channelCount: 2)
        
        #expect(format1 == format2)
        #expect(format1 != format3)
    }
    
    @Test("AudioFormat: sendable across actors")
    func testAudioFormatSendable() async {
        actor FormatHolder {
            var format: AudioFormat?
            
            func setFormat(_ f: AudioFormat) {
                format = f
            }
            
            func getFormat() -> AudioFormat? {
                return format
            }
        }
        
        let holder = FormatHolder()
        let format = AudioFormat.standard
        await holder.setFormat(format)
        let retrieved = await holder.getFormat()
        
        #expect(retrieved == format)
    }
    
    // MARK: - PlaybackPosition Tests
    
    @Test("PlaybackPosition: basic properties")
    func testPlaybackPositionBasic() {
        let position = PlaybackPosition(
            currentTime: 30.0,
            duration: 120.0
        )
        
        #expect(position.currentTime == 30.0)
        #expect(position.duration == 120.0)
    }
    
    @Test("PlaybackPosition: progress calculation")
    func testPlaybackPositionProgress() {
        let start = PlaybackPosition(currentTime: 0, duration: 100)
        #expect(start.progress == 0.0)
        
        let quarter = PlaybackPosition(currentTime: 25, duration: 100)
        #expect(quarter.progress == 0.25)
        
        let half = PlaybackPosition(currentTime: 50, duration: 100)
        #expect(half.progress == 0.5)
        
        let threeQuarter = PlaybackPosition(currentTime: 75, duration: 100)
        #expect(threeQuarter.progress == 0.75)
        
        let end = PlaybackPosition(currentTime: 100, duration: 100)
        #expect(end.progress == 1.0)
    }
    
    @Test("PlaybackPosition: progress beyond duration")
    func testPlaybackPositionProgressBeyond() {
        let beyond = PlaybackPosition(currentTime: 150, duration: 100)
        #expect(beyond.progress == 1.5)
    }
    
    @Test("PlaybackPosition: progress with zero duration")
    func testPlaybackPositionZeroDuration() {
        let zero = PlaybackPosition(currentTime: 10, duration: 0)
        #expect(zero.progress == 0.0)
    }
    
    @Test("PlaybackPosition: remaining time")
    func testPlaybackPositionRemainingTime() {
        let position = PlaybackPosition(currentTime: 45, duration: 120)
        #expect(position.remainingTime == 75.0)
        
        let nearEnd = PlaybackPosition(currentTime: 115, duration: 120)
        #expect(nearEnd.remainingTime == 5.0)
        
        let atEnd = PlaybackPosition(currentTime: 120, duration: 120)
        #expect(atEnd.remainingTime == 0.0)
    }
    
    @Test("PlaybackPosition: remaining time when exceeded")
    func testPlaybackPositionRemainingTimeExceeded() {
        let exceeded = PlaybackPosition(currentTime: 130, duration: 120)
        #expect(exceeded.remainingTime == 0.0)
    }
    
    @Test("PlaybackPosition: equatable")
    func testPlaybackPositionEquatable() {
        let pos1 = PlaybackPosition(currentTime: 30, duration: 120)
        let pos2 = PlaybackPosition(currentTime: 30, duration: 120)
        let pos3 = PlaybackPosition(currentTime: 60, duration: 120)
        
        #expect(pos1 == pos2)
        #expect(pos1 != pos3)
    }
    
    // MARK: - TrackInfo Tests
    
    @Test("TrackInfo: full initialization")
    func testTrackInfoFull() {
        let format = AudioFormat.standard
        let track = TrackInfo(
            title: "Meditation Music",
            artist: "Calm Sounds",
            duration: 600.0,
            format: format
        )
        
        #expect(track.title == "Meditation Music")
        #expect(track.artist == "Calm Sounds")
        #expect(track.duration == 600.0)
        #expect(track.format == format)
    }
    
    @Test("TrackInfo: optional fields nil")
    func testTrackInfoOptionalFields() {
        let format = AudioFormat.standard
        let track = TrackInfo(
            duration: 300.0,
            format: format
        )
        
        #expect(track.title == nil)
        #expect(track.artist == nil)
        #expect(track.duration == 300.0)
        #expect(track.format == format)
    }
    
    @Test("TrackInfo: only title")
    func testTrackInfoOnlyTitle() {
        let format = AudioFormat.standard
        let track = TrackInfo(
            title: "Ambient Sounds",
            duration: 450.0,
            format: format
        )
        
        #expect(track.title == "Ambient Sounds")
        #expect(track.artist == nil)
    }
    
    @Test("TrackInfo: equatable")
    func testTrackInfoEquatable() {
        let format = AudioFormat.standard
        
        let track1 = TrackInfo(
            title: "Track",
            artist: "Artist",
            duration: 300,
            format: format
        )
        
        let track2 = TrackInfo(
            title: "Track",
            artist: "Artist",
            duration: 300,
            format: format
        )
        
        let track3 = TrackInfo(
            title: "Different",
            artist: "Artist",
            duration: 300,
            format: format
        )
        
        #expect(track1 == track2)
        #expect(track1 != track3)
    }
    
    @Test("TrackInfo: sendable across actors")
    func testTrackInfoSendable() async {
        actor TrackHolder {
            var track: TrackInfo?
            
            func setTrack(_ t: TrackInfo) {
                track = t
            }
            
            func getTrack() -> TrackInfo? {
                return track
            }
        }
        
        let holder = TrackHolder()
        let track = TrackInfo(
            title: "Test",
            duration: 100,
            format: .standard
        )
        
        await holder.setTrack(track)
        let retrieved = await holder.getTrack()
        
        #expect(retrieved == track)
    }
    
    // MARK: - Edge Cases
    
    @Test("PlaybackPosition: negative current time")
    func testPlaybackPositionNegativeCurrent() {
        let negative = PlaybackPosition(currentTime: -10, duration: 100)
        #expect(negative.currentTime == -10)
        #expect(negative.progress < 0)
    }
    
    @Test("PlaybackPosition: very large values")
    func testPlaybackPositionLargeValues() {
        let large = PlaybackPosition(
            currentTime: 3600.0, // 1 hour
            duration: 7200.0      // 2 hours
        )
        
        #expect(large.progress == 0.5)
        #expect(large.remainingTime == 3600.0)
    }
    
    @Test("TrackInfo: very long duration")
    func testTrackInfoLongDuration() {
        let format = AudioFormat.standard
        let long = TrackInfo(
            duration: 36000.0, // 10 hours
            format: format
        )
        
        #expect(long.duration == 36000.0)
    }
    
    @Test("AudioFormat: high sample rate")
    func testAudioFormatHighSampleRate() {
        let high = AudioFormat(
            sampleRate: 192000.0,
            channelCount: 2
        )
        
        #expect(high.sampleRate == 192000.0)
    }
    
    @Test("AudioFormat: many channels")
    func testAudioFormatManyChannels() {
        let surround = AudioFormat(
            sampleRate: 48000.0,
            channelCount: 6  // 5.1 surround
        )
        
        #expect(surround.channelCount == 6)
    }
}
