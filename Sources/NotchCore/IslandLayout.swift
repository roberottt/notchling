import CoreGraphics

public enum IslandAnchor: Equatable {
    /// El rectángulo físico del notch, en coordenadas globales (Y hacia arriba).
    case notch(CGRect)
    /// Centro horizontal y borde superior de la ventanita.
    case floating(CGPoint)
}

/// Toda la geometría, sin estado ni AppKit.
public struct IslandLayout: Equatable {
    public static let rowHeight: CGFloat = 58
    public static let maxRows = 6
    public static let padding: CGFloat = 8
    public static let floatingHeight: CGFloat = 34
    public static let expandedWidth: CGFloat = 440
    public static let margin: CGFloat = 32

    public let screen: CGRect
    public let anchor: IslandAnchor
    public let wing: CGFloat
    public let rows: Int

    public init(screen: CGRect, anchor: IslandAnchor, wing: CGFloat, rows: Int) {
        self.screen = screen
        self.anchor = anchor
        self.wing = wing
        self.rows = min(max(rows, 1), Self.maxRows)
    }

    public var isNotch: Bool {
        if case .notch = anchor { true } else { false }
    }

    /// Hueco central en el que no se puede pintar.
    public var gap: CGFloat {
        if case .notch(let notch) = anchor { notch.width } else { 4 }
    }

    public var headerHeight: CGFloat {
        if case .notch(let notch) = anchor { notch.height } else { Self.floatingHeight }
    }

    private var top: CGPoint {
        switch anchor {
        case .notch(let notch): CGPoint(x: notch.midX, y: screen.maxY)
        case .floating(let point): point
        }
    }

    public var collapsed: CGRect {
        let width = wing * 2 + gap
        let height = headerHeight
        if isNotch { return CGRect(x: top.x - width / 2, y: top.y - height, width: width, height: height) }
        return CGRect(
            x: Self.clamp(top.x - width / 2, screen.minX, screen.maxX - width),
            y: Self.clamp(top.y - height, screen.minY, screen.maxY - height),
            width: width, height: height)
    }

    private var tallest: CGFloat { headerHeight + CGFloat(Self.maxRows) * Self.rowHeight + Self.padding * 2 }

    /// Se decide con la altura máxima para que no cambie de lado al llegar una sesión.
    public var opensUpward: Bool {
        !isNotch && collapsed.maxY - tallest < screen.minY
    }

    public var expanded: CGRect {
        let width = max(isNotch ? gap + 320 : 0, Self.expandedWidth)
        let height = headerHeight + CGFloat(rows) * Self.rowHeight + Self.padding * 2
        let base = collapsed
        let x = isNotch ? top.x - width / 2 : Self.clamp(base.midX - width / 2, screen.minX + 4, screen.maxX - width - 4)
        let y = opensUpward ? base.minY : base.maxY - height
        return CGRect(x: x, y: Self.clamp(y, screen.minY, screen.maxY - height), width: width, height: height)
    }

    /// La ventana no cambia de tamaño al animar: es transparente y cubre el despliegue máximo.
    public var panel: CGRect {
        let width = min(Self.expandedWidth + 200, screen.width)
        let height = min(tallest + Self.margin * 2, screen.height)
        let x = Self.clamp(top.x - width / 2, screen.minX, screen.maxX - width)
        let y = opensUpward ? collapsed.minY - Self.margin : collapsed.maxY + (isNotch ? 0 : Self.margin) - height
        return CGRect(x: x, y: Self.clamp(y, screen.minY, screen.maxY - height), width: width, height: height)
    }

    /// Fila visible bajo un punto de la isla desplegada.
    public func row(at point: CGPoint) -> Int? {
        let box = expanded
        guard point.x >= box.minX, point.x <= box.maxX else { return nil }
        let y = box.maxY - point.y - headerHeight - Self.padding
        guard y >= 0 else { return nil }
        let index = Int(y / Self.rowHeight)
        return index < rows ? index : nil
    }

    public static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}
