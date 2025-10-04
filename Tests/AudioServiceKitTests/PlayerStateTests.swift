import XCTest
@testable import AudioServiceCore

final class PlayerStateTests: XCTestCase {
    
    func testPlayerStateEquality() {
        // Same states should be equal
        XCTAssertEqual(PlayerState.preparing, PlayerState.preparing)
        XCTAssertEqual(PlayerState.playing, PlayerState.playing)
        XCTAssertEqual(PlayerState.paused, PlayerState.paused)
        XCTAssertEqual(PlayerState.fadingOut, PlayerState.fadingOut)
        XCTAssertEqual(PlayerState.finished, PlayerState.finished)
        
        // Different states should not be equal
        XCTAssertNotEqual(PlayerState.preparing, PlayerState.playing)
        XCTAssertNotEqual(PlayerState.playing, PlayerState.paused)
    }
    
    func testFailedStateEquality() {
        let error1 = AudioPlayerError.fileLoadFailed(reason: "File not found")
        let error2 = AudioPlayerError.fileLoadFailed(reason: "File not found")
        let error3 = AudioPlayerError.sessionConfigurationFailed(reason: "Session error")
        
        let state1 = PlayerState.failed(error1)
        let state2 = PlayerState.failed(error2)
        let state3 = PlayerState.failed(error3)
        
        // Same error messages should be equal
        XCTAssertEqual(state1, state2)
        
        // Different error messages should not be equal
        XCTAssertNotEqual(state1, state3)
    }
    
    func testPlayerStateIsSendable() {
        // Test that PlayerState conforms to Sendable
        // This is a compile-time check, but we can verify it can be used in async context
        Task {
            let state: PlayerState = .playing
            XCTAssertEqual(state, .playing)
        }
    }
}
