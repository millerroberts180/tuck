import Foundation
import Testing
@testable import TuckCore

@Suite("Spring parameters")
struct SpringParametersTests {
    func close(_ a: Double, _ b: Double, within tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    @Test func durationAndBounceBecomeStiffnessAndDamping() {
        let spring = SpringParameters(duration: 0.5, bounce: 0.25)
        let omega = 2 * Double.pi / 0.5
        #expect(close(spring.stiffness, omega * omega))
        #expect(close(spring.dampingRatio, 0.75))
    }

    @Test func zeroBounceAndFullDampingSettleWithoutOvershoot() {
        #expect(close(SpringParameters(duration: 0.4, bounce: 0).dampingRatio, 1))
        #expect(close(SpringParameters(response: 0.4, dampingFraction: 1).dampingRatio, 1))
        #expect(SurfaceMotion.close.overshoot == 0)
        #expect(SurfaceMotion.settle.overshoot == 0)
    }

    @Test func negativeBounceIsOverdamped() {
        #expect(close(SpringParameters(duration: 0.35, bounce: -0.2).dampingRatio, 1.25))
    }

    @Test func openingOvershootsByAboutATenth() {
        #expect(close(SurfaceMotion.open.dampingRatio, 0.6))
        #expect(close(SurfaceMotion.open.overshoot, 0.0948, within: 0.001))
    }

    @Test func durationAndResponseAgreeForTheSamePeriod() {
        let a = SpringParameters(duration: 0.4, bounce: 0)
        let b = SpringParameters(response: 0.4, dampingFraction: 1)
        #expect(close(a.stiffness, b.stiffness))
        #expect(close(a.damping, b.damping))
    }
}
