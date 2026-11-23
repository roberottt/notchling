import AppKit
import NotchCore
import QuartzCore

extension SessionState {
    var color: NSColor {
        switch self {
        case .working: NSColor(srgbRed: 0.95, green: 0.56, blue: 0.40, alpha: 1)
        case .permission, .input: NSColor(srgbRed: 1.00, green: 0.76, blue: 0.24, alpha: 1)
        case .question: NSColor(srgbRed: 0.36, green: 0.70, blue: 1.00, alpha: 1)
        case .plan: NSColor(srgbRed: 0.73, green: 0.56, blue: 1.00, alpha: 1)
        case .error: NSColor(srgbRed: 1.00, green: 0.38, blue: 0.36, alpha: 1)
        case .done: NSColor(srgbRed: 0.30, green: 0.85, blue: 0.47, alpha: 1)
        case .background: NSColor(srgbRed: 0.38, green: 0.82, blue: 0.82, alpha: 1)
        case .dialog: NSColor(white: 0.85, alpha: 1)
        case .idle, .unknown: NSColor(white: 0.56, alpha: 1)
        }
    }

    var symbol: String? {
        switch self {
        case .permission: "lock.fill"
        case .question: "questionmark.bubble.fill"
        case .plan: "list.bullet.clipboard.fill"
        case .input: "exclamationmark.bubble.fill"
        case .error: "exclamationmark.triangle.fill"
        case .dialog: "ellipsis.rectangle.fill"
        case .unknown: "questionmark.circle"
        case .working, .background, .done, .idle: nil
        }
    }
}

@MainActor
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Cambia una propiedad con muelle, partiendo de donde esté ahora en pantalla.
    static func set(_ layer: CALayer, _ key: String, to value: Any?, animated: Bool, bounce: CGFloat = 0.22) {
        let previous = layer.value(forKeyPath: key)
        if let previous = previous as? NSObject, let value = value as? NSObject, previous.isEqual(value) {
            if !animated { layer.removeAnimation(forKey: "move." + key) }
            return
        }
        let current = layer.presentation()?.value(forKeyPath: key) ?? previous
        layer.setValue(value, forKeyPath: key)

        guard animated, let current else {
            layer.removeAnimation(forKey: "move." + key)
            return
        }
        let animation: CABasicAnimation
        if reduced || key == "opacity" {
            animation = CABasicAnimation(keyPath: key)
            animation.duration = reduced ? 0.1 : 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        } else {
            let spring = CASpringAnimation(perceptualDuration: 0.42, bounce: bounce)
            spring.keyPath = key
            spring.duration = spring.settlingDuration
            animation = spring
        }
        animation.fromValue = current
        animation.toValue = value
        layer.add(animation, forKey: "move." + key)
    }

    static func loop(
        _ layer: CALayer, _ key: String, values: [Any], times: [NSNumber]? = nil, duration: CFTimeInterval,
        timing: CAMediaTimingFunctionName = .easeInEaseOut
    ) {
        guard !reduced else { return }
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: timing), count: values.count - 1)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "loop." + key)
    }
}

/// Texto de una línea con fundido al cambiar.
@MainActor
final class Label {
    let layer = CATextLayer()
    let height: CGFloat
    private let font: NSFont
    private var text = ""

    init(size: CGFloat, weight: NSFont.Weight, color: NSColor = .white, align: CATextLayerAlignmentMode = .left, digits: Bool = false) {
        font = digits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        height = ceil(font.ascender - font.descender + font.leading) + 1
        layer.font = font
        layer.fontSize = size
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = align
        layer.truncationMode = .end
        layer.anchorPoint = CGPoint(x: align == .right ? 1 : 0, y: 0.5)
        layer.contentsScale = 2
    }

    func set(_ value: String, color: NSColor? = nil, animated: Bool) {
        if let color { layer.foregroundColor = color.cgColor }
        guard value != text else { return }
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            layer.add(fade, forKey: "text")
        }
        text = value
        layer.string = value
    }

    /// `x` es el borde izquierdo, o el derecho si el texto va alineado a la derecha.
    func place(x: CGFloat, midY: CGFloat, width: CGFloat, animated: Bool) {
        layer.bounds = CGRect(x: 0, y: 0, width: max(width, 0), height: height)
        Motion.set(layer, "position", to: NSValue(point: CGPoint(x: x, y: midY)), animated: animated)
    }

    func width(of value: String) -> CGFloat {
        ceil((value as NSString).size(withAttributes: [.font: font]).width) + 2
    }
}
