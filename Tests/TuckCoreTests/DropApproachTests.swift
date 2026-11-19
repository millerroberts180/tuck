import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Drop approach")
struct DropApproachTests {
    // A 1500 × 982 display with a 300 × 32 surface at the top centre (AppKit coordinates, y up).
    let surface = CGRect(x: 600, y: 950, width: 300, height: 32)
    var zone: DropApproach.Zone {
        DropApproach.Zone(surface: surface, approach: CGRect(x: 520, y: 862, width: 460, height: 120),
                          display: CGRect(x: 0, y: 0, width: 1500, height: 982))
    }

    @Test func theRangeIsAGenerousTopCentreAreaInsideTheDisplay() {
        let range = zone.range
        #expect(range.minX == 600 - DropApproach.rangeReach.width)
        #expect(range.maxX == 900 + DropApproach.rangeReach.width)
        #expect(range.minY == 950 - DropApproach.rangeReach.height)
        #expect(range.maxY == 982)
    }

    @Test func noInvitationOutsideTheRange() {
        #expect(DropApproach.invitation(pointer: CGPoint(x: 100, y: 100), zone: zone, wasInviting: false) == nil)
        // Level with the surface but far to the side.
        #expect(DropApproach.invitation(pointer: CGPoint(x: 200, y: 960), zone: zone, wasInviting: false) == nil)
        // Centred, but further down than the range reaches.
        #expect(DropApproach.invitation(pointer: CGPoint(x: 750, y: 700), zone: zone, wasInviting: false) == nil)
    }

    @Test func theInvitationAppearsBeforeTheNotchAndStrengthensAsItNears() {
        let edge = DropApproach.invitation(pointer: CGPoint(x: 750, y: 740), zone: zone, wasInviting: false)
        let middle = DropApproach.invitation(pointer: CGPoint(x: 750, y: 850), zone: zone, wasInviting: false)
        let close = DropApproach.invitation(pointer: CGPoint(x: 750, y: 915), zone: zone, wasInviting: false)
        #expect(edge != nil)
        #expect(edge! <= middle! && middle! < close!)
        #expect(close! < DropApproach.levels)
    }

    @Test func overThePoppedOutTargetIsTheAcceptedState() {
        // On the surface, and in the band it pops out by below it.
        #expect(DropApproach.invitation(pointer: CGPoint(x: 750, y: 960), zone: zone, wasInviting: false) == DropApproach.levels)
        #expect(DropApproach.invitation(pointer: CGPoint(x: 750, y: 930), zone: zone, wasInviting: false) == DropApproach.levels)
        #expect(DropApproach.invitation(pointer: CGPoint(x: 590, y: 960), zone: zone, wasInviting: false) == DropApproach.levels)
    }

    @Test func leavingTheRangeNeedsTheRetreatMargin() {
        let justOutside = CGPoint(x: 750, y: zone.range.minY - 20)
        #expect(DropApproach.invitation(pointer: justOutside, zone: zone, wasInviting: false) == nil)
        #expect(DropApproach.invitation(pointer: justOutside, zone: zone, wasInviting: true) != nil)
        let wellOutside = CGPoint(x: 750, y: zone.range.minY - 60)
        #expect(DropApproach.invitation(pointer: wellOutside, zone: zone, wasInviting: true) == nil)
    }

    @Test func armingUsesALargerZoneToDisarm() {
        let edge = CGPoint(x: 750, y: 850) // just below the approach zone, inside the retreat margin
        #expect(!DropApproach.isArmed(pointer: edge, zone: zone, wasArmed: false))
        #expect(DropApproach.isArmed(pointer: edge, zone: zone, wasArmed: true))
        #expect(DropApproach.isArmed(pointer: CGPoint(x: 750, y: 900), zone: zone, wasArmed: false))
        #expect(!DropApproach.isArmed(pointer: CGPoint(x: 750, y: 600), zone: zone, wasArmed: true))
    }

    @Test func theInvitationRangeIsWiderThanThePanelsOpeningZone() {
        // The invitation shows well before the deliberate dwell that opens the panel can begin.
        #expect(zone.range.contains(zone.approach))
        let invitedButNotArming = CGPoint(x: 750, y: 760)
        #expect(DropApproach.invitation(pointer: invitedButNotArming, zone: zone, wasInviting: false) != nil)
        #expect(!DropApproach.isArmed(pointer: invitedButNotArming, zone: zone, wasArmed: false))
    }
}

@Suite("Drag classification")
struct DragClassificationTests {
    @Test func aDragStaysPendingUntilItsSourceWritesThePasteboard() {
        #expect(DragClassification.classify(changeCountAtMouseDown: 4, changeCount: 4, advertisesSupportedType: true,
                                            elapsed: 0.05) == .pending)
        #expect(DragClassification.classify(changeCountAtMouseDown: 4, changeCount: 5, advertisesSupportedType: true,
                                            elapsed: 0.12) == .content)
    }

    @Test func unsupportedOrSilentDragsAreLeftAlone() {
        #expect(DragClassification.classify(changeCountAtMouseDown: 4, changeCount: 5, advertisesSupportedType: false,
                                            elapsed: 0.1) == .other)
        // A window move or text selection never writes the drag pasteboard.
        #expect(DragClassification.classify(changeCountAtMouseDown: 4, changeCount: 4, advertisesSupportedType: false,
                                            elapsed: DragClassification.decisionWindow) == .other)
    }
}
