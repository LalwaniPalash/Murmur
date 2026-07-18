import CoreGraphics
import Testing
@testable import MurmurNext

struct FlowBarPlacementTests {
    @Test func clampsPlacementAndDocksNearScreenEdges() {
        let visible = CGRect(x: 100, y: 80, width: 1_000, height: 700)
        let size = CGSize(width: 140, height: 42)

        #expect(
            FlowBarPlacement.dockedOrigin(
                proposed: CGPoint(x: 108, y: 90),
                panelSize: size,
                visibleFrame: visible
            ) == CGPoint(x: 100, y: 80)
        )
        #expect(
            FlowBarPlacement.dockedOrigin(
                proposed: CGPoint(x: 2_000, y: 2_000),
                panelSize: size,
                visibleFrame: visible
            ) == CGPoint(x: 960, y: 738)
        )
        #expect(
            FlowBarPlacement.dockedOrigin(
                proposed: CGPoint(x: 500, y: 300),
                panelSize: size,
                visibleFrame: visible
            ) == CGPoint(x: 500, y: 300)
        )
    }
}
