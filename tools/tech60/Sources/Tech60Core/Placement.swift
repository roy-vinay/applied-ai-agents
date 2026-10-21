import Foundation

/// Which window Tech60 is showing: the full card, the one-line ticker, or the small dot.
public enum Presentation: String, Codable, Sendable {
    case card, ticker, dot
}

/// Where the ticker sits: docked to the top or bottom edge, or floating anywhere.
public enum Dock: String, Codable, Sendable, CaseIterable {
    case top, bottom, float
}

/// A remembered spot on one display, stored as fractions of that display's usable area
/// so it survives resolution changes and different window sizes.
public struct SpotOnScreen: Codable, Equatable, Sendable {
    public var dock: Dock
    /// Horizontal center, 0 = left edge of the usable area, 1 = right edge.
    public var centerX: Double
    /// Floating only: bottom of the window, 0 = lowest possible, 1 = highest possible.
    public var bottomY: Double

    public init(dock: Dock, centerX: Double = 0.5, bottomY: Double = 0) {
        self.dock = dock
        self.centerX = centerX
        self.bottomY = bottomY
    }

    /// The first-ever placement: docked to the bottom edge, centered.
    public static let firstUse = SpotOnScreen(dock: .bottom)
}

/// Spots remembered per display, plus the display used last.
public struct PlacementBook: Codable, Equatable, Sendable {
    public var byDisplay: [String: SpotOnScreen] = [:]
    public var lastDisplay: String?

    public init() {}

    /// The display to use now: the last one if it's still connected, otherwise the main display.
    public func display(connected: [String], main: String) -> String {
        if let last = lastDisplay, connected.contains(last) { return last }
        return main
    }

    public func spot(on display: String) -> SpotOnScreen {
        byDisplay[display] ?? .firstUse
    }

    public mutating func remember(_ spot: SpotOnScreen, on display: String) {
        byDisplay[display] = spot
        lastDisplay = display
    }
}

/// Geometry for the ticker and the dot. Rectangles use macOS screen coordinates (origin bottom-left).
public enum Placement {
    /// Gap between a docked ticker and the edge of the usable area.
    public static let edgeGap: CGFloat = 8
    /// How close to an edge a drop has to be to snap to it.
    public static let snapDistance: CGFloat = 24

    /// The frame for a spot, inside the usable area of a display.
    public static func frame(for spot: SpotOnScreen, size: CGSize, in visible: CGRect) -> CGRect {
        let w = min(size.width, visible.width)
        let h = min(size.height, visible.height)
        let x = visible.minX + CGFloat(spot.centerX) * visible.width - w / 2
        let y: CGFloat
        switch spot.dock {
        case .bottom: y = visible.minY + edgeGap
        case .top: y = visible.maxY - h - edgeGap
        case .float: y = visible.minY + CGFloat(spot.bottomY) * max(visible.height - h, 0)
        }
        return clamp(CGRect(x: x, y: y, width: w, height: h), in: visible)
    }

    /// Keeps a frame fully inside the usable area, shrinking it only if it can't fit.
    public static func clamp(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let w = min(frame.width, visible.width)
        let h = min(frame.height, visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - w)
        let y = min(max(frame.minY, visible.minY), visible.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Which edge a frame being dragged would snap to, or nil if it would float.
    public static func snapTarget(for frame: CGRect, in visible: CGRect, snapping: Bool = true) -> Dock? {
        guard snapping else { return nil }
        if frame.minY - visible.minY <= snapDistance { return .bottom }
        if visible.maxY - frame.maxY <= snapDistance { return .top }
        return nil
    }

    /// The spot to remember after the user drops the window at `frame`.
    public static func spot(afterDropping frame: CGRect, in visible: CGRect, snapping: Bool = true) -> SpotOnScreen {
        let f = clamp(frame, in: visible)
        let centerX = visible.width > 0 ? Double((f.midX - visible.minX) / visible.width) : 0.5
        if let edge = snapTarget(for: f, in: visible, snapping: snapping) {
            return SpotOnScreen(dock: edge, centerX: centerX)
        }
        let room = visible.height - f.height
        let bottomY = room > 0 ? Double((f.minY - visible.minY) / room) : 0
        return SpotOnScreen(dock: .float, centerX: centerX, bottomY: bottomY)
    }

    /// The spot for a dock chosen from the menu, keeping the current horizontal position.
    public static func spot(docking dock: Dock, from current: SpotOnScreen) -> SpotOnScreen {
        SpotOnScreen(dock: dock, centerX: current.centerX, bottomY: dock == .float ? 0.5 : current.bottomY)
    }
}

/// Remembers which presentation to come back to, so the dot restores whatever it came from.
public struct PresentationState: Codable, Equatable, Sendable {
    public private(set) var current: Presentation
    /// What the dot (or the ticker) returns to.
    public private(set) var previous: Presentation

    public init(current: Presentation = .card, previous: Presentation = .card) {
        self.current = current
        self.previous = previous
    }

    /// Switches to `next`, remembering where we came from.
    public mutating func show(_ next: Presentation) {
        guard next != current else { return }
        previous = current
        current = next
    }

    /// The dot restores its previous state. The ticker always expands to the card.
    public mutating func expand() {
        switch current {
        case .dot: show(previous == .dot ? .card : previous)
        case .ticker: show(.card)
        case .card: break
        }
    }
}
