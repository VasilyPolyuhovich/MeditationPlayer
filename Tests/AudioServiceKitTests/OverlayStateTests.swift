import Testing
import Foundation
@testable import AudioServiceCore

/// Test suite: OverlayState properties and queries (Feature #4)
@Suite("Overlay State")
struct OverlayStateTests {
    
    // MARK: - State Cases
    
    @Test("State: idle")
    func testStateIdle() {
        let state = OverlayState.idle
        
        #expect(state == .idle)
        #expect(state.description == "Idle")
    }
    
    @Test("State: preparing")
    func testStatePreparing() {
        let state = OverlayState.preparing
        
        #expect(state == .preparing)
        #expect(state.description == "Preparing")
    }
    
    @Test("State: playing")
    func testStatePlaying() {
        let state = OverlayState.playing
        
        #expect(state == .playing)
        #expect(state.description == "Playing")
    }
    
    @Test("State: paused")
    func testStatePaused() {
        let state = OverlayState.paused
        
        #expect(state == .paused)
        #expect(state.description == "Paused")
    }
    
    @Test("State: stopping")
    func testStateStopping() {
        let state = OverlayState.stopping
        
        #expect(state == .stopping)
        #expect(state.description == "Stopping")
    }
    
    // MARK: - State Query: isPlaying
    
    @Test("isPlaying: true for playing state")
    func testIsPlayingTrue() {
        let state = OverlayState.playing
        #expect(state.isPlaying == true)
    }
    
    @Test("isPlaying: false for idle state")
    func testIsPlayingFalseIdle() {
        let state = OverlayState.idle
        #expect(state.isPlaying == false)
    }
    
    @Test("isPlaying: false for preparing state")
    func testIsPlayingFalsePreparing() {
        let state = OverlayState.preparing
        #expect(state.isPlaying == false)
    }
    
    @Test("isPlaying: false for paused state")
    func testIsPlayingFalsePaused() {
        let state = OverlayState.paused
        #expect(state.isPlaying == false)
    }
    
    @Test("isPlaying: false for stopping state")
    func testIsPlayingFalseStopping() {
        let state = OverlayState.stopping
        #expect(state.isPlaying == false)
    }
    
    // MARK: - State Query: isPaused
    
    @Test("isPaused: true for paused state")
    func testIsPausedTrue() {
        let state = OverlayState.paused
        #expect(state.isPaused == true)
    }
    
    @Test("isPaused: false for all other states")
    func testIsPausedFalseOthers() {
        let states: [OverlayState] = [.idle, .preparing, .playing, .stopping]
        
        for state in states {
            #expect(state.isPaused == false)
        }
    }
    
    // MARK: - State Query: isTransitioning
    
    @Test("isTransitioning: true for preparing state")
    func testIsTransitioningPreparing() {
        let state = OverlayState.preparing
        #expect(state.isTransitioning == true)
    }
    
    @Test("isTransitioning: true for stopping state")
    func testIsTransitioningStopping() {
        let state = OverlayState.stopping
        #expect(state.isTransitioning == true)
    }
    
    @Test("isTransitioning: false for stable states")
    func testIsTransitioningFalseStable() {
        let states: [OverlayState] = [.idle, .playing, .paused]
        
        for state in states {
            #expect(state.isTransitioning == false)
        }
    }
    
    // MARK: - State Query: isIdle
    
    @Test("isIdle: true for idle state")
    func testIsIdleTrue() {
        let state = OverlayState.idle
        #expect(state.isIdle == true)
    }
    
    @Test("isIdle: false for all other states")
    func testIsIdleFalseOthers() {
        let states: [OverlayState] = [.preparing, .playing, .paused, .stopping]
        
        for state in states {
            #expect(state.isIdle == false)
        }
    }
    
    // MARK: - Equatable Tests
    
    @Test("Equatable: idle == idle")
    func testEquatableIdle() {
        #expect(OverlayState.idle == OverlayState.idle)
    }
    
    @Test("Equatable: playing == playing")
    func testEquatablePlaying() {
        #expect(OverlayState.playing == OverlayState.playing)
    }
    
    @Test("Equatable: idle != playing")
    func testEquatableDifferent() {
        #expect(OverlayState.idle != OverlayState.playing)
    }
    
    @Test("Equatable: all states different from each other")
    func testEquatableAllDifferent() {
        let states: [OverlayState] = [.idle, .preparing, .playing, .paused, .stopping]
        
        for (i, state1) in states.enumerated() {
            for (j, state2) in states.enumerated() {
                if i == j {
                    #expect(state1 == state2)
                } else {
                    #expect(state1 != state2)
                }
            }
        }
    }
    
    // MARK: - CustomStringConvertible Tests
    
    @Test("Description: all states have proper descriptions")
    func testDescriptions() {
        #expect(OverlayState.idle.description == "Idle")
        #expect(OverlayState.preparing.description == "Preparing")
        #expect(OverlayState.playing.description == "Playing")
        #expect(OverlayState.paused.description == "Paused")
        #expect(OverlayState.stopping.description == "Stopping")
    }
    
    // MARK: - Sendable Compliance
    
    @Test("Sendable: can be passed across actors")
    func testSendableCompliance() async {
        actor StateHolder {
            var state: OverlayState = .idle
            
            func setState(_ newState: OverlayState) {
                state = newState
            }
            
            func getState() -> OverlayState {
                return state
            }
        }
        
        let holder = StateHolder()
        await holder.setState(.playing)
        let state = await holder.getState()
        
        #expect(state == .playing)
    }
    
    // MARK: - State Combinations
    
    @Test("Only one state can be true at a time")
    func testMutuallyExclusiveStates() {
        let states: [OverlayState] = [.idle, .preparing, .playing, .paused, .stopping]
        
        for state in states {
            // Count how many query properties are true
            var trueCount = 0
            if state.isPlaying { trueCount += 1 }
            if state.isPaused { trueCount += 1 }
            if state.isIdle { trueCount += 1 }
            
            // isTransitioning can overlap with other states
            // so we only check the main state properties
            
            // Each state should have exactly one primary property true
            #expect(trueCount == 1)
        }
    }
    
    @Test("Transitioning states are not stable")
    func testTransitioningNotStable() {
        let transitioningStates: [OverlayState] = [.preparing, .stopping]
        
        for state in transitioningStates {
            #expect(state.isTransitioning == true)
            #expect(state.isPlaying == false)
            #expect(state.isPaused == false)
            #expect(state.isIdle == false)
        }
    }
    
    @Test("Stable states are not transitioning")
    func testStableNotTransitioning() {
        let stableStates: [OverlayState] = [.idle, .playing, .paused]
        
        for state in stableStates {
            #expect(state.isTransitioning == false)
        }
    }
}
