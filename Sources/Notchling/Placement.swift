import CoreGraphics
import Foundation
import NotchCore

enum Placement: Codable, Equatable {
    case automatic
    case notch(display: String)
    case topCenter(display: String)
    /// `x` relativa al ancho y `top` en puntos desde arriba, para sobrevivir a cambios de resolución.
    case custom(display: String, x: CGFloat, top: CGFloat)

    func resolve(in displays: [Display]) -> (display: Display, anchor: IslandAnchor)? {
        switch self {
        case .notch(let id):
            if let display = displays.first(where: { $0.id == id }), let notch = display.notch {
                return (display, .notch(notch))
            }
        case .topCenter(let id):
            if let display = displays.first(where: { $0.id == id }) {
                return (display, Self.topCenter(of: display))
            }
        case .custom(let id, let x, let top):
            if let display = displays.first(where: { $0.id == id }) {
                let point = CGPoint(x: display.frame.minX + x * display.frame.width, y: display.frame.maxY - top)
                return (display, .floating(point))
            }
        case .automatic:
            break
        }
        return Self.automaticChoice(in: displays)
    }

    /// Notch si se usa solo la pantalla del portátil; con una externa, ventanita en la externa.
    private static func automaticChoice(in displays: [Display]) -> (display: Display, anchor: IslandAnchor)? {
        // La primera pantalla es siempre la de la barra de menús.
        guard let main = displays.first else { return nil }
        if let external = displays.first(where: { !$0.builtIn }) { return (external, topCenter(of: external)) }
        if let notch = main.notch { return (main, .notch(notch)) }
        return (main, topCenter(of: main))
    }

    private static func topCenter(of display: Display) -> IslandAnchor {
        .floating(CGPoint(x: display.frame.midX, y: display.usableTop - 6))
    }
}
