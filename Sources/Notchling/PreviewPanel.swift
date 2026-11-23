import AppKit

/// Tarjeta bajo la isla con el último mensaje de la fila sobre la que está el ratón.
@MainActor
final class PreviewPanel {
    private let panel: NSPanel
    private let title = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")
    private var shown: String?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0, alpha: 0.94).cgColor
        view.layer?.cornerRadius = 16
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        panel.contentView = view

        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = NSColor(white: 0.55, alpha: 1)
        title.lineBreakMode = .byTruncatingTail
        body.font = .systemFont(ofSize: 12.5)
        body.textColor = NSColor(white: 0.92, alpha: 1)
        body.maximumNumberOfLines = 12
        // Truncar por el final convierte la etiqueta en una sola línea: se parte por palabras
        // y solo se recorta la última línea visible si no cabe.
        body.lineBreakMode = .byWordWrapping
        body.cell?.truncatesLastVisibleLine = true
        view.addSubview(title)
        view.addSubview(body)
    }

    /// `anchor` es la isla desplegada; la tarjeta va debajo, o encima si la isla abre hacia arriba.
    func show(heading: String, text: String, anchor: CGRect, upward: Bool, screen: CGRect) {
        let key = heading + "\n" + text
        let width = anchor.width
        let inner = width - 32
        title.stringValue = heading
        body.stringValue = text
        body.preferredMaxLayoutWidth = inner
        let bodyHeight = min(body.fittingSize.height, 220)
        let height = 14 + 16 + 6 + bodyHeight + 14

        title.frame = CGRect(x: 16, y: height - 14 - 16, width: inner, height: 16)
        body.frame = CGRect(x: 16, y: 14, width: inner, height: bodyHeight)

        var y = upward ? anchor.maxY + 8 : anchor.minY - 8 - height
        y = min(max(y, screen.minY + 4), screen.maxY - height)
        panel.setFrame(CGRect(x: anchor.minX, y: y, width: width, height: height), display: true)

        guard shown != key || !panel.isVisible else { return }
        let appearing = !panel.isVisible
        shown = key
        if appearing {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        shown = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}
