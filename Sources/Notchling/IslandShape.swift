import CoreGraphics

/// Todas las variantes tienen los mismos segmentos, así Core Animation interpola entre ellas.
enum IslandShape {
    private static let curve: CGFloat = 0.5523

    static func path(_ box: CGRect, notch: Bool, expanded: Bool) -> CGPath {
        let bottom: CGFloat = expanded ? 22 : (notch ? 12 : box.height / 2)
        let top: CGFloat = notch ? (expanded ? 12 : 6) : bottom
        // En el notch las esquinas de arriba se abren hacia fuera, como las del hardware.
        let out: CGFloat = notch ? -1 : 1
        let k = curve
        let (left, right, minY, maxY) = (box.minX, box.maxX, box.minY, box.maxY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + out * top, y: minY))
        path.addCurve(
            to: CGPoint(x: left, y: minY + top),
            control1: CGPoint(x: left + out * top * (1 - k), y: minY),
            control2: CGPoint(x: left, y: minY + top * (1 - k)))
        path.addLine(to: CGPoint(x: left, y: maxY - bottom))
        path.addCurve(
            to: CGPoint(x: left + bottom, y: maxY),
            control1: CGPoint(x: left, y: maxY - bottom * (1 - k)),
            control2: CGPoint(x: left + bottom * (1 - k), y: maxY))
        path.addLine(to: CGPoint(x: right - bottom, y: maxY))
        path.addCurve(
            to: CGPoint(x: right, y: maxY - bottom),
            control1: CGPoint(x: right - bottom * (1 - k), y: maxY),
            control2: CGPoint(x: right, y: maxY - bottom * (1 - k)))
        path.addLine(to: CGPoint(x: right, y: minY + top))
        path.addCurve(
            to: CGPoint(x: right - out * top, y: minY),
            control1: CGPoint(x: right, y: minY + top * (1 - k)),
            control2: CGPoint(x: right - out * top * (1 - k), y: minY))
        path.addLine(to: CGPoint(x: left + out * top, y: minY))
        path.closeSubpath()
        return path
    }
}
