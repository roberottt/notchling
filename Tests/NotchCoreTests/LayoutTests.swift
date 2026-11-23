import CoreGraphics
import Testing
@testable import NotchCore

private let laptop = CGRect(x: 1920, y: 98, width: 1512, height: 982)
private let notch = CGRect(x: 2583.5, y: 1048, width: 185, height: 32)

@Test(arguments: [0, 42, 56, 138, 160] as [CGFloat])
func wingsHugTheNotch(wing: CGFloat) {
    let layout = IslandLayout(screen: laptop, anchor: .notch(notch), wing: wing, rows: 3)
    #expect(layout.collapsed.minX == notch.minX - wing)
    #expect(layout.collapsed.maxX == notch.maxX + wing)
    #expect(layout.collapsed.maxY == laptop.maxY)
    #expect(layout.collapsed.height == notch.height)
}

@Test(arguments: [
    CGPoint(x: 0, y: 0), CGPoint(x: 960, y: 1074), CGPoint(x: 1920, y: 1080),
    CGPoint(x: 5, y: 540), CGPoint(x: 1900, y: 60), CGPoint(x: -500, y: 2000),
])
func everythingStaysOnScreen(point: CGPoint) {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    for rows in [1, 3, 6, 20] {
        let layout = IslandLayout(screen: screen, anchor: .floating(point), wing: 138, rows: rows)
        for box in [layout.collapsed, layout.expanded, layout.panel] { #expect(screen.contains(box)) }
        #expect(layout.panel.contains(layout.collapsed))
        #expect(layout.panel.contains(layout.expanded))
    }
}

@Test func opensUpwardNearTheBottom() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let layout = IslandLayout(screen: screen, anchor: .floating(CGPoint(x: 960, y: 80)), wing: 138, rows: 3)
    #expect(layout.opensUpward)
    #expect(layout.expanded.minY == layout.collapsed.minY)
}

@Test func rowsMatchWhatIsDrawn() {
    let layout = IslandLayout(screen: laptop, anchor: .notch(notch), wing: 138, rows: 3)
    let first = layout.expanded.maxY - layout.headerHeight - IslandLayout.padding
    for index in 0..<3 {
        let point = CGPoint(x: notch.midX, y: first - (CGFloat(index) + 0.5) * IslandLayout.rowHeight)
        #expect(layout.row(at: point) == index)
    }
    #expect(layout.row(at: CGPoint(x: notch.midX, y: laptop.maxY - 5)) == nil)
}
