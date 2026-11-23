// Dibuja el icono de Notchling a 1024 px con la rejilla de iconos de macOS.
// Uso: scripts/make-icon.sh (genera assets/AppIcon.icns).
import AppKit

let size: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)   // cuadrado redondeado de macOS
let radius: CGFloat = 185

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name + ".png"))
}

func squircle() -> CGPath { CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil) }

func background(_ ctx: CGContext, _ colors: [CGColor]) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(squircle()); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle()); ctx.clip()
    let g = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()
}

/// La isla negra pegada al borde de arriba, con las esquinas de abajo redondeadas.
func island(_ ctx: CGContext, width: CGFloat, height: CGFloat) -> CGRect {
    let rect = CGRect(x: tile.midX - width / 2, y: tile.maxY - height, width: width, height: height)
    ctx.saveGState()
    ctx.addPath(squircle()); ctx.clip()
    let r = height * 0.5
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX - 30, y: rect.maxY + 10))
    p.addLine(to: CGPoint(x: rect.maxX + 30, y: rect.maxY + 10))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY), radius: r)
    p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY + r), radius: r)
    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.45))
    ctx.addPath(p); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    return rect
}

func dots(_ ctx: CGContext, right: CGFloat, y: CGFloat, d: CGFloat, colors: [UInt32]) {
    for (i, c) in colors.reversed().enumerated() {
        ctx.setFillColor(rgb(c))
        ctx.fillEllipse(in: CGRect(x: right - d - CGFloat(i) * d * 1.6, y: y - d / 2, width: d, height: d))
    }
}

let orange: UInt32 = 0xF28F66, teal: UInt32 = 0x61D1D1, gray: UInt32 = 0x8F8F8F

// La isla de la app, con el anillo de "trabajando" y los puntos de estado.
render("icon_1024") { ctx in
    background(ctx, [rgb(0xF58C6A), rgb(0x8A4FC7), rgb(0x1F2A6B)])
    let r = island(ctx, width: 700, height: 280)
    let c = CGPoint(x: r.minX + 150, y: r.midY - 10)
    ctx.setLineWidth(38); ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(orange, 0.25)); ctx.addArc(center: c, radius: 72, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
    ctx.setStrokeColor(rgb(orange)); ctx.addArc(center: c, radius: 72, startAngle: .pi * 0.5, endAngle: .pi * 1.6, clockwise: false); ctx.strokePath()
    dots(ctx, right: r.maxX - 100, y: r.midY - 10, d: 66, colors: [orange, teal, gray])
}
