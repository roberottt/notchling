import AppKit
import ColorSync

struct Display {
    let id: String
    let name: String
    let frame: CGRect
    /// Borde superior de la zona libre, bajo la barra de menús.
    let usableTop: CGFloat
    let notch: CGRect?
    let builtIn: Bool

    @MainActor
    static func current() -> [Display] { NSScreen.screens.map(Display.init(screen:)) }

    @MainActor
    private init(screen: NSScreen) {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) {
            id = text as String
        } else {
            id = String(number)
        }
        name = screen.localizedName
        frame = screen.frame
        usableTop = screen.visibleFrame.maxY
        builtIn = CGDisplayIsBuiltin(number) != 0

        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let height = screen.safeAreaInsets.top
            notch = CGRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height)
        } else {
            notch = nil
        }
    }
}
