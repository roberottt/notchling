import AppKit
import NotchCore
import QuartzCore

@MainActor
protocol IslandViewDelegate: AnyObject {
    func pointerMoved()
    func pointerDown()
    func pointerDragged()
    func pointerUp()
    func scrolled(rows: Int)
    func showMenu(at point: NSPoint, in view: NSView)
    func menuVisibilityChanged(open: Bool)
}

@MainActor
final class IslandView: NSView {
    weak var delegate: IslandViewDelegate?

    private let canvas = CALayer()
    private let background = CAShapeLayer()
    private let border = CAShapeLayer()
    private let content = CALayer()
    private let clip = CAShapeLayer()

    private let glyph = StatusGlyph()
    private let status = Label(size: 12, weight: .semibold)
    private let shimmer = CAGradientLayer()
    private let summary = Label(size: 11.5, weight: .medium, color: NSColor(white: 0.78, alpha: 1), align: .right)
    private let badges = CALayer()
    private let dots = (0..<3).map { _ in CALayer() }
    private let overflow = Label(size: 10, weight: .semibold, color: NSColor(white: 0.7, alpha: 1), align: .right)

    private let list = CALayer()
    private let rows = (0..<IslandLayout.maxRows).map { _ in SessionRow() }
    private let empty = Label(size: 12, weight: .regular, color: NSColor(white: 0.6, alpha: 1))

    private var scrollTotal: CGFloat = 0
    private var lastPanel: CGRect?
    private var pulsing: SessionState?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        layer = root // Asignar la capa antes de wantsLayer la hace nuestra, no de AppKit.
        wantsLayer = true

        canvas.isGeometryFlipped = true
        canvas.anchorPoint = .zero
        root.addSublayer(canvas)

        background.fillColor = NSColor.black.cgColor
        background.shadowColor = NSColor.black.cgColor
        background.shadowRadius = 10
        background.shadowOffset = CGSize(width: 0, height: 4)
        canvas.addSublayer(background)

        content.mask = clip
        canvas.addSublayer(content)
        content.addSublayer(glyph.layer)
        content.addSublayer(status.layer)
        content.addSublayer(summary.layer)

        badges.anchorPoint = CGPoint(x: 1, y: 0.5)
        content.addSublayer(badges)
        for dot in dots {
            dot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
            dot.cornerRadius = 3
            badges.addSublayer(dot)
        }
        badges.addSublayer(overflow.layer)

        list.opacity = 0
        content.addSublayer(list)
        for row in rows { list.addSublayer(row.layer) }
        list.addSublayer(empty.layer)

        border.fillColor = nil
        border.lineWidth = 1
        canvas.addSublayer(border)

        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        let dim = NSColor(white: 1, alpha: 0.7).cgColor
        shimmer.colors = [dim, NSColor.white.cgColor, dim]
        shimmer.locations = [-0.6, -0.3, 0]

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func render(_ data: IslandContent, animated requested: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let panel = data.panel
        // Si la ventana se mueve cambian las coordenadas locales: animar daría un salto.
        let animated = requested && lastPanel == panel
        lastPanel = panel

        canvas.frame = CGRect(origin: .zero, size: panel.size)
        for layer in [background, content, clip, border] as [CALayer] { layer.frame = canvas.bounds }
        setScale(window?.backingScaleFactor ?? 2)

        let layout = data.layout
        let box = local(data.expanded ? layout.expanded : layout.collapsed, in: panel)
        let path = IslandShape.path(box, notch: layout.isNotch, expanded: data.expanded)
        let bounce: CGFloat = data.expanded ? 0.22 : 0.1
        Motion.set(background, "path", to: path, animated: animated, bounce: bounce)
        Motion.set(background, "shadowPath", to: path, animated: animated, bounce: bounce)
        Motion.set(clip, "path", to: path, animated: animated, bounce: bounce)
        Motion.set(border, "path", to: path, animated: animated, bounce: bounce)
        let shadow: Float = layout.isNotch && !data.expanded ? 0 : 0.4
        Motion.set(background, "shadowOpacity", to: NSNumber(value: shadow), animated: animated)

        let top = data.sessions.first?.state ?? .idle
        updateBorder(data, state: top)
        renderHeader(data, box: box, state: top, animated: animated)
        renderList(data, panel: panel, animated: animated)

        let spoken = data.sessions.map { "\($0.project): \($0.state.label). \($0.detail)" }.joined(separator: "; ")
        setAccessibilityLabel(spoken.isEmpty ? tr("Sin sesiones de Claude Code", "No Claude Code sessions") : spoken)
    }

    private func local(_ rect: CGRect, in panel: CGRect) -> CGRect {
        CGRect(x: rect.minX - panel.minX, y: panel.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func setScale(_ scale: CGFloat) {
        guard status.layer.contentsScale != scale else { return }
        for label in [status, summary, overflow, empty] + rows.flatMap(\.labels) { label.layer.contentsScale = scale }
    }

    private func updateBorder(_ data: IslandContent, state: SessionState) {
        let pulse = state.needsUser && !data.snapping ? state : nil
        if data.snapping {
            border.strokeColor = NSColor.controlAccentColor.cgColor
        } else if let pulse {
            border.strokeColor = pulse.color.withAlphaComponent(0.85).cgColor
        } else if data.layout.isNotch {
            border.strokeColor = NSColor.clear.cgColor
        } else {
            border.strokeColor = NSColor(white: 1, alpha: 0.16).cgColor
        }
        guard pulse != pulsing else { return }
        pulsing = pulse
        border.removeAnimation(forKey: "loop.opacity")
        if pulse != nil { Motion.loop(border, "opacity", values: [0.25, 1, 0.25], duration: 1.6) }
    }

    private func renderHeader(_ data: IslandContent, box: CGRect, state: SessionState, animated: Bool) {
        let layout = data.layout
        let height = layout.headerHeight
        let midY = box.minY + height / 2
        let minimal = !data.expanded && IslandContent.isMinimal(data.sessions, compact: data.compact)
        let visible = NSNumber(value: Float(minimal || data.yielding ? 0 : 1))
        let shown = NSNumber(value: Float(data.yielding ? 0 : 1))
        Motion.set(glyph.layer, "opacity", to: shown, animated: animated)
        Motion.set(badges, "opacity", to: shown, animated: animated)
        let count = data.sessions.count

        let inset: CGFloat = data.expanded ? 30 : (minimal ? 21 : 20)
        glyph.show(state, animated: animated)
        Motion.set(glyph.layer, "position", to: NSValue(point: CGPoint(x: box.minX + inset, y: midY)), animated: animated)

        let leftEdge = box.midX - layout.gap / 2 - 4
        let labelX = box.minX + inset + 16
        status.set(data.sessions.isEmpty ? tr("Sin sesiones", "No sessions") : state.label, color: state.color, animated: animated)
        status.place(x: labelX, midY: midY, width: leftEdge - labelX, animated: animated)
        Motion.set(status.layer, "opacity", to: visible, animated: animated)
        updateShimmer(active: state == .working)

        // Un punto por sesión: con una sola y texto al lado sobra.
        let dotCount = count > 1 || minimal ? min(count, dots.count) : 0
        let extra = count > dots.count ? "+\(count - dots.count)" : ""
        let extraWidth = extra.isEmpty ? 0 : overflow.width(of: extra) + 2
        let badgeWidth = dotCount == 0 ? 0 : CGFloat(dotCount) * 9 - 3 + extraWidth
        badges.bounds = CGRect(x: 0, y: 0, width: badgeWidth, height: 14)
        let right = box.maxX - (data.expanded ? 22 : (minimal ? 14 : 16))
        Motion.set(badges, "position", to: NSValue(point: CGPoint(x: right, y: midY)), animated: animated)
        for (index, dot) in dots.enumerated() {
            dot.isHidden = index >= dotCount
            guard index < dotCount else { continue }
            dot.position = CGPoint(x: CGFloat(index) * 9 + 3, y: 7)
            dot.backgroundColor = data.sessions[index].state.color.cgColor
        }
        overflow.set(extra, animated: false)
        overflow.place(x: badgeWidth, midY: 7, width: extraWidth, animated: false)

        let text: String
        if data.expanded {
            text = count == 1 ? tr("1 sesión", "1 session") : tr("\(count) sesiones", "\(count) sessions")
        } else if let first = data.sessions.first {
            // Trabajando importa el qué; cuando te espera importa quién.
            text = first.state == .working ? first.detail : first.project
        } else {
            text = ""
        }
        let textRight = right - (dotCount == 0 ? 0 : badgeWidth + 7)
        summary.set(text, animated: animated)
        summary.place(x: textRight, midY: midY, width: textRight - (box.midX + layout.gap / 2 + 6), animated: animated)
        Motion.set(summary.layer, "opacity", to: visible, animated: animated)
    }

    private func updateShimmer(active: Bool) {
        guard active, !Motion.reduced else {
            status.layer.mask = nil
            return
        }
        shimmer.frame = CGRect(x: 0, y: 0, width: min(status.layer.bounds.width, 90), height: status.height)
        guard status.layer.mask == nil else { return }
        status.layer.mask = shimmer
        Motion.loop(
            shimmer, "locations", values: [[-0.6, -0.3, 0], [1, 1.3, 1.6]] as [[NSNumber]], duration: 1.8, timing: .linear)
    }

    private func renderList(_ data: IslandContent, panel: CGRect, animated: Bool) {
        let box = local(data.layout.expanded, in: panel)
        let origin = box.minY + data.layout.headerHeight + IslandLayout.padding
        let height = IslandLayout.rowHeight
        list.frame = CGRect(x: box.minX, y: origin, width: box.width, height: height * CGFloat(IslandLayout.maxRows))
        Motion.set(list, "opacity", to: NSNumber(value: Float(data.expanded ? 1 : 0)), animated: animated)

        let now = Date()
        for (index, row) in rows.enumerated() {
            row.layer.isHidden = index >= data.visible.count
            guard index < data.visible.count else { continue }
            let session = data.visible[index]
            row.update(
                session: session, hostName: data.hosts[session.id] ?? "",
                hovered: data.expanded && data.hoveredRow == index,
                frame: CGRect(x: 0, y: CGFloat(index) * height, width: box.width, height: height),
                now: now, animated: animated)
        }
        empty.layer.isHidden = !data.visible.isEmpty
        empty.set(tr("No hay sesiones de Claude Code abiertas", "No open Claude Code sessions"), animated: false)
        empty.place(x: 22, midY: height / 2, width: box.width - 44, animated: false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { delegate?.pointerMoved() }
    override func mouseEntered(with event: NSEvent) { delegate?.pointerMoved() }
    override func mouseExited(with event: NSEvent) { delegate?.pointerMoved() }
    override func mouseDragged(with event: NSEvent) { delegate?.pointerDragged() }
    override func mouseUp(with event: NSEvent) { delegate?.pointerUp() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(event)
        } else {
            delegate?.pointerDown()
        }
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    private func showMenu(_ event: NSEvent) {
        delegate?.showMenu(at: convert(event.locationInWindow, from: nil), in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollTotal -= event.scrollingDeltaY
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 1
        let count = Int(scrollTotal / step)
        guard count != 0 else { return }
        scrollTotal -= CGFloat(count) * step
        delegate?.scrolled(rows: count)
    }
}
