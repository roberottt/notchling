import AppKit
import NotchCore
import QuartzCore

/// Icono animado de estado. Las animaciones las ejecuta el servidor de render, no la app.
@MainActor
final class StatusGlyph {
    static let size: CGFloat = 18
    let layer = CALayer()
    private var state: SessionState?

    init() {
        layer.bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
    }

    func show(_ new: SessionState, animated: Bool) {
        guard new != state else { return }
        state = new
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let body = CALayer()
        body.frame = layer.bounds
        layer.addSublayer(body)

        switch new {
        case .working: addSpinner(to: body, color: new.color, period: 1.1, core: true)
        case .background: addSpinner(to: body, color: new.color, period: 2.8, core: false)
        case .done: addCheck(to: body, color: new.color)
        case .idle: addResting(to: body, color: new.color)
        default: addSymbol(to: body, state: new)
        }

        guard animated, !Motion.reduced else { return }
        let pop = CASpringAnimation(perceptualDuration: 0.4, bounce: 0.45)
        pop.keyPath = "transform.scale"
        pop.fromValue = 0.3
        pop.toValue = 1
        pop.duration = pop.settlingDuration
        layer.add(pop, forKey: "pop")
    }

    private func circle(radius: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.bounds = layer.bounds
        shape.position = CGPoint(x: Self.size / 2, y: Self.size / 2)
        let inset = Self.size / 2 - radius
        shape.path = CGPath(ellipseIn: layer.bounds.insetBy(dx: inset, dy: inset), transform: nil)
        return shape
    }

    private func addSpinner(to body: CALayer, color: NSColor, period: CFTimeInterval, core: Bool) {
        let track = circle(radius: 7)
        track.fillColor = nil
        track.strokeColor = color.withAlphaComponent(0.22).cgColor
        track.lineWidth = 2
        body.addSublayer(track)

        let arc = circle(radius: 7)
        arc.fillColor = nil
        arc.strokeColor = color.cgColor
        arc.lineWidth = 2
        arc.lineCap = .round
        arc.strokeEnd = 0.3
        body.addSublayer(arc)
        Motion.loop(arc, "transform.rotation.z", values: [0, CGFloat.pi * 2], duration: period, timing: .linear)
        Motion.loop(arc, "strokeEnd", values: [0.15, 0.5, 0.15], duration: period * 1.6)

        guard core else { return }
        let dot = circle(radius: 2.8)
        dot.fillColor = color.cgColor
        body.addSublayer(dot)
        Motion.loop(dot, "transform.scale", values: [0.65, 1.15, 0.65], duration: 1.4)
    }

    private func addResting(to body: CALayer, color: NSColor) {
        let ring = circle(radius: 6.5)
        ring.fillColor = nil
        ring.strokeColor = color.withAlphaComponent(0.45).cgColor
        ring.lineWidth = 1.5
        body.addSublayer(ring)
        let dot = circle(radius: 2.5)
        dot.fillColor = color.cgColor
        body.addSublayer(dot)
    }

    private func addCheck(to body: CALayer, color: NSColor) {
        let disc = circle(radius: 8)
        disc.fillColor = color.cgColor
        body.addSublayer(disc)

        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 5.3, y: 9.3), CGPoint(x: 7.9, y: 11.9), CGPoint(x: 12.8, y: 6.5)])
        let tick = CAShapeLayer()
        tick.frame = layer.bounds
        tick.path = path
        tick.fillColor = nil
        tick.strokeColor = NSColor.black.cgColor
        tick.lineWidth = 2
        tick.lineCap = .round
        tick.lineJoin = .round
        body.addSublayer(tick)

        guard !Motion.reduced else { return }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.45
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        tick.add(draw, forKey: "draw")
    }

    private func addSymbol(to body: CALayer, state: SessionState) {
        if state.needsUser {
            let halo = circle(radius: 8)
            halo.fillColor = state.color.withAlphaComponent(0.35).cgColor
            halo.opacity = 0
            body.addSublayer(halo)
            Motion.loop(halo, "opacity", values: [0.9, 0, 0], times: [0, 0.7, 1], duration: 1.6)
            Motion.loop(halo, "transform.scale", values: [0.6, 1.7, 1.7], times: [0, 0.7, 1], duration: 1.6)
        }

        guard let name = state.symbol, let image = Self.render(symbol: name, color: state.color) else { return }
        let icon = CALayer()
        icon.frame = layer.bounds
        icon.contents = image
        icon.contentsGravity = .resizeAspect
        body.addSublayer(icon)

        switch state {
        case .permission:
            Motion.loop(
                icon, "transform.rotation.z", values: [0, -0.28, 0.24, -0.16, 0.08, 0, 0],
                times: [0, 0.07, 0.15, 0.22, 0.29, 0.36, 1], duration: 1.6)
        case .question, .input:
            Motion.loop(
                icon, "transform.translation.y", values: [0, -3, 0, -1.2, 0, 0],
                times: [0, 0.14, 0.28, 0.38, 0.48, 1], duration: 1.6)
        case .plan:
            Motion.loop(icon, "transform.scale", values: [1, 1.15, 1], duration: 1.6)
        default:
            break
        }
    }

    private static func render(symbol: String, color: NSColor) -> CGImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.preferringMonochrome())
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return nil }

        let pixels = Int(size * 3)
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: 3, y: 3)

        let scale = min(1, (size - 2) / max(image.size.width, image.size.height))
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2, width: drawn.width, height: drawn.height))
        // Tintar después conserva los huecos del símbolo (el «?» del bocadillo).
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}
