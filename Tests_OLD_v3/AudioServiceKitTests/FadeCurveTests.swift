import XCTest
@testable import AudioServiceCore
@testable import AudioServiceKit

final class FadeCurveTests: XCTestCase {
    
    // MARK: - Equal Power Tests
    
    func testEqualPowerFadeIn() {
        let curve = FadeCurve.equalPower
        
        // At 0% progress
        let vol0 = curve.volume(for: 0.0)
        XCTAssertEqual(vol0, 0.0, accuracy: 0.001)
        
        // At 50% progress (should be ~0.707, which is 1/√2)
        let vol50 = curve.volume(for: 0.5)
        XCTAssertEqual(vol50, 0.707, accuracy: 0.01)
        
        // At 100% progress
        let vol100 = curve.volume(for: 1.0)
        XCTAssertEqual(vol100, 1.0, accuracy: 0.001)
    }
    
    func testEqualPowerFadeOut() {
        let curve = FadeCurve.equalPower
        
        // At 0% progress (fade out starts at 1.0)
        let vol0 = curve.inverseVolume(for: 0.0)
        XCTAssertEqual(vol0, 1.0, accuracy: 0.001)
        
        // At 50% progress (should be ~0.707)
        let vol50 = curve.inverseVolume(for: 0.5)
        XCTAssertEqual(vol50, 0.707, accuracy: 0.01)
        
        // At 100% progress (fade out ends at 0.0)
        let vol100 = curve.inverseVolume(for: 1.0)
        XCTAssertEqual(vol100, 0.0, accuracy: 0.001)
    }
    
    func testEqualPowerMaintainsConstantPower() {
        let curve = FadeCurve.equalPower
        
        // Test at various points that fadeOut² + fadeIn² ≈ 1
        for i in stride(from: 0.0, through: 1.0, by: 0.1) {
            let fadeIn = curve.volume(for: Float(i))
            let fadeOut = curve.inverseVolume(for: Float(i))
            
            let totalPower = fadeIn * fadeIn + fadeOut * fadeOut
            
            // Should be very close to 1.0 (constant power)
            XCTAssertEqual(totalPower, 1.0, accuracy: 0.01, 
                          "Power should be constant at progress \(i)")
        }
    }
    
    // MARK: - Linear Tests
    
    func testLinearFade() {
        let curve = FadeCurve.linear
        
        // Linear should be exactly proportional
        XCTAssertEqual(curve.volume(for: 0.0), 0.0)
        XCTAssertEqual(curve.volume(for: 0.25), 0.25)
        XCTAssertEqual(curve.volume(for: 0.5), 0.5)
        XCTAssertEqual(curve.volume(for: 0.75), 0.75)
        XCTAssertEqual(curve.volume(for: 1.0), 1.0)
    }
    
    func testLinearHasPowerDip() {
        let curve = FadeCurve.linear
        
        // At 50% crossfade, total power drops
        let fadeIn = curve.volume(for: 0.5)
        let fadeOut = curve.inverseVolume(for: 0.5)
        
        let totalPower = fadeIn * fadeIn + fadeOut * fadeOut
        
        // Should be 0.5 (50% power loss = -3dB dip)
        XCTAssertEqual(totalPower, 0.5, accuracy: 0.01)
        
        // This is why linear is bad for audio!
        XCTAssertLessThan(totalPower, 1.0, "Linear fade has power dip")
    }
    
    // MARK: - Logarithmic Tests
    
    func testLogarithmicFade() {
        let curve = FadeCurve.logarithmic
        
        // Should start at 0
        XCTAssertEqual(curve.volume(for: 0.0), 0.0, accuracy: 0.01)
        
        // Should end at 1
        XCTAssertEqual(curve.volume(for: 1.0), 1.0, accuracy: 0.01)
        
        // Should be faster at start (high slope)
        let vol25 = curve.volume(for: 0.25)
        let vol50 = curve.volume(for: 0.5)
        
        // First quarter should gain more than second quarter
        let firstQuarterGain = vol25 - 0.0
        let secondQuarterGain = vol50 - vol25
        
        XCTAssertGreaterThan(firstQuarterGain, secondQuarterGain,
                            "Logarithmic should start fast")
    }
    
    // MARK: - Exponential Tests
    
    func testExponentialFade() {
        let curve = FadeCurve.exponential
        
        // Should follow quadratic curve
        XCTAssertEqual(curve.volume(for: 0.0), 0.0)
        XCTAssertEqual(curve.volume(for: 0.5), 0.25, accuracy: 0.001)
        XCTAssertEqual(curve.volume(for: 1.0), 1.0, accuracy: 0.001)
        
        // Should be slower at start (low slope)
        let vol25 = curve.volume(for: 0.25)
        let vol50 = curve.volume(for: 0.5)
        
        // First quarter should gain less than second quarter
        let firstQuarterGain = vol25 - 0.0
        let secondQuarterGain = vol50 - vol25
        
        XCTAssertLessThan(firstQuarterGain, secondQuarterGain,
                         "Exponential should start slow")
    }
    
    // MARK: - S-Curve Tests
    
    func testSCurveFade() {
        let curve = FadeCurve.sCurve
        
        // Should start at 0 and end at 1
        XCTAssertEqual(curve.volume(for: 0.0), 0.0)
        XCTAssertEqual(curve.volume(for: 1.0), 1.0)
        
        // Should be exactly 0.5 at midpoint
        XCTAssertEqual(curve.volume(for: 0.5), 0.5, accuracy: 0.001)
        
        // Should be symmetric
        let vol25 = curve.volume(for: 0.25)
        let vol75 = curve.volume(for: 0.75)
        
        XCTAssertEqual(vol25, 1.0 - vol75, accuracy: 0.001,
                      "S-curve should be symmetric")
    }
    
    // MARK: - Edge Cases
    
    func testAllCurvesHandleBoundaries() {
        let curves: [FadeCurve] = [.linear, .equalPower, .logarithmic, .exponential, .sCurve]
        
        for curve in curves {
            // Should handle 0 and 1
            let vol0 = curve.volume(for: 0.0)
            let vol1 = curve.volume(for: 1.0)
            
            XCTAssertGreaterThanOrEqual(vol0, 0.0, "\(curve) should have vol >= 0 at start")
            XCTAssertLessThanOrEqual(vol0, 0.1, "\(curve) should start near 0")
            
            XCTAssertGreaterThanOrEqual(vol1, 0.9, "\(curve) should end near 1")
            XCTAssertLessThanOrEqual(vol1, 1.0, "\(curve) should have vol <= 1 at end")
            
            // Should clamp negative
            let volNeg = curve.volume(for: -0.5)
            XCTAssertGreaterThanOrEqual(volNeg, 0.0, "\(curve) should clamp negative")
            
            // Should clamp over 1
            let volOver = curve.volume(for: 1.5)
            XCTAssertLessThanOrEqual(volOver, 1.0, "\(curve) should clamp > 1")
        }
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationWithFadeCurve() {
        let config = PlayerConfiguration(
            crossfadeDuration: 10.0,
            fadeCurve: .equalPower
        )
        
        XCTAssertEqual(config.fadeCurve, .equalPower)
    }
    
    func testConfigurationDefaultFadeCurve() {
        let config = PlayerConfiguration()
        
        // Should default to equal-power
        XCTAssertEqual(config.fadeCurve, .equalPower)
    }
    
    // MARK: - Crossfade Calculator Tests
    
    func testCrossfadeCalculator() {
        let calculator = CrossfadeCalculator(
            curve: .equalPower,
            duration: 10.0,
            stepTime: 0.01
        )
        
        // Should have 1000 steps for 10s at 10ms per step
        XCTAssertEqual(calculator.steps, 1000)
        
        // At start, fadeOut should be 1, fadeIn should be 0
        let (fadeOut0, fadeIn0) = calculator.volumes(at: 0)
        XCTAssertEqual(fadeOut0, 1.0, accuracy: 0.01)
        XCTAssertEqual(fadeIn0, 0.0, accuracy: 0.01)
        
        // At midpoint, both should be ~0.707
        let (fadeOut500, fadeIn500) = calculator.volumes(at: 500)
        XCTAssertEqual(fadeOut500, 0.707, accuracy: 0.01)
        XCTAssertEqual(fadeIn500, 0.707, accuracy: 0.01)
        
        // At end, fadeOut should be 0, fadeIn should be 1
        let (fadeOut1000, fadeIn1000) = calculator.volumes(at: 1000)
        XCTAssertEqual(fadeOut1000, 0.0, accuracy: 0.01)
        XCTAssertEqual(fadeIn1000, 1.0, accuracy: 0.01)
    }
}
