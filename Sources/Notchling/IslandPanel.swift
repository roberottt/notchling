import AppKit

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Por encima de la barra de menús para poder ocupar los lados del notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        title = "Notchling"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit empuja las ventanas por debajo de la barra de menús si no se anula esto.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
