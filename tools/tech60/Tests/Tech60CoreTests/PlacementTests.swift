import XCTest
@testable import Tech60Core

final class PlacementTests: XCTestCase {
    // A 1440x900 display with a 25 pt menu bar and a 75 pt Dock.
    private let visible = CGRect(x: 0, y: 75, width: 1440, height: 800)
    private let pill = CGSize(width: 620, height: 36)

    func testFirstUseDocksToTheBottomCentered() {
        let f = Placement.frame(for: .firstUse, size: pill, in: visible)
        XCTAssertEqual(f.minY, visible.minY + Placement.edgeGap, "just above the Dock")
        XCTAssertEqual(f.midX, visible.midX, accuracy: 0.5)
    }

    func testTopDockSitsBelowTheMenuBar() {
        let f = Placement.frame(for: SpotOnScreen(dock: .top), size: pill, in: visible)
        XCTAssertEqual(f.maxY, visible.maxY - Placement.edgeGap)
    }

    func testDroppingNearAnEdgeSnaps() {
        let nearBottom = CGRect(x: 300, y: visible.minY + 10, width: pill.width, height: pill.height)
        XCTAssertEqual(Placement.spot(afterDropping: nearBottom, in: visible).dock, .bottom)
        let nearTop = CGRect(x: 300, y: visible.maxY - pill.height - 5, width: pill.width, height: pill.height)
        XCTAssertEqual(Placement.spot(afterDropping: nearTop, in: visible).dock, .top)
    }

    func testOptionKeySkipsSnapping() {
        let nearBottom = CGRect(x: 300, y: visible.minY + 10, width: pill.width, height: pill.height)
        XCTAssertEqual(Placement.spot(afterDropping: nearBottom, in: visible, snapping: false).dock, .float)
    }

    func testFloatingSpotComesBackWhereItWasDropped() {
        let dropped = CGRect(x: 400, y: 420, width: pill.width, height: pill.height)
        let spot = Placement.spot(afterDropping: dropped, in: visible)
        XCTAssertEqual(spot.dock, .float)
        let restored = Placement.frame(for: spot, size: pill, in: visible)
        XCTAssertEqual(restored.minX, dropped.minX, accuracy: 0.5)
        XCTAssertEqual(restored.minY, dropped.minY, accuracy: 0.5)
    }

    func testNeverRestoresOffScreen() {
        let smaller = CGRect(x: 0, y: 0, width: 800, height: 600)
        let spot = SpotOnScreen(dock: .float, centerX: 0.99, bottomY: 1)
        let f = Placement.frame(for: spot, size: pill, in: smaller)
        XCTAssertTrue(smaller.contains(f), "\(f) should fit inside \(smaller)")
    }

    func testMissingDisplayFallsBackToMain() {
        var book = PlacementBook()
        book.remember(SpotOnScreen(dock: .top), on: "external")
        XCTAssertEqual(book.display(connected: ["built-in", "external"], main: "built-in"), "external")
        XCTAssertEqual(book.display(connected: ["built-in"], main: "built-in"), "built-in")
        XCTAssertEqual(book.spot(on: "built-in"), .firstUse, "an unseen display starts at the bottom")
    }

    func testPlacementIsRememberedPerDisplay() throws {
        var book = PlacementBook()
        book.remember(SpotOnScreen(dock: .top), on: "a")
        book.remember(SpotOnScreen(dock: .float, centerX: 0.2, bottomY: 0.4), on: "b")
        let copy = try JSONDecoder().decode(PlacementBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(copy.spot(on: "a").dock, .top)
        XCTAssertEqual(copy.spot(on: "b").dock, .float)
        XCTAssertEqual(copy.lastDisplay, "b")
    }

    func testDotRestoresWhateverItCameFrom() {
        var state = PresentationState()
        state.show(.ticker)
        state.show(.dot)
        state.expand()
        XCTAssertEqual(state.current, .ticker, "dot from ticker goes back to the ticker")
        state.expand()
        XCTAssertEqual(state.current, .card, "ticker expands to the card")

        state.show(.dot)
        state.expand()
        XCTAssertEqual(state.current, .card, "dot from card goes back to the card")
    }
}
