import AppKit
import NotchCore
import QuartzCore

@MainActor
final class SessionRow {
    let layer = CALayer()
    private let highlight = CALayer()
    private let glyph = StatusGlyph()
    private let title = Label(size: 13, weight: .semibold)
    private let status = Label(size: 11, weight: .semibold)
    private let detail = Label(size: 11, weight: .regular, color: NSColor(white: 0.68, alpha: 1))
    private let time = Label(size: 11, weight: .medium, color: NSColor(white: 0.6, alpha: 1), align: .right, digits: true)
    private let host = Label(size: 10, weight: .regular, color: NSColor(white: 0.45, alpha: 1), align: .right)

    private let buttons = Decision.allCases.map { DecisionButton($0) }

    var labels: [Label] { [title, status, detail, time, host] + buttons.map(\.label) }

    typealias Decision = PermissionHook.Decision

    init() {
        highlight.backgroundColor = NSColor(white: 1, alpha: 0.11).cgColor
        highlight.cornerRadius = 14
        highlight.cornerCurve = .continuous
        highlight.opacity = 0
        layer.addSublayer(highlight)
        layer.addSublayer(glyph.layer)
        for label in [title, status, detail, time, host] { layer.addSublayer(label.layer) }
        for button in buttons { layer.addSublayer(button.layer) }
    }

    /// Botones de un permiso pendiente, en coordenadas de la fila (Y hacia abajo).
    static func buttonFrames(rowWidth: CGFloat, rowHeight: CGFloat) -> [(Decision, CGRect)] {
        var right = rowWidth - 18
        let midY = rowHeight / 2 + 10
        return Decision.allCases.reversed().map { decision in
            let width = DecisionButton.width(decision)
            right -= width
            let frame = CGRect(x: right, y: midY - 10, width: width, height: 20)
            right -= 6
            return (decision, frame)
        }.reversed()
    }

    func update(session: Session, hostName: String, hovered: Bool, frame: CGRect, now: Date, animated: Bool) {
        layer.frame = frame
        highlight.frame = layer.bounds.insetBy(dx: 8, dy: 2)
        Motion.set(highlight, "opacity", to: NSNumber(value: Float(hovered ? 1 : 0)), animated: animated)

        glyph.show(session.state, animated: animated)
        glyph.layer.position = CGPoint(x: 30, y: frame.height / 2)

        let right = frame.width - 20
        let top = frame.height / 2 - 9.5
        let bottom = frame.height / 2 + 10

        let elapsed = Self.elapsed(now.timeIntervalSince(session.since))
        let timeWidth = time.width(of: elapsed)
        time.set(elapsed, animated: false)
        time.place(x: right, midY: top, width: timeWidth, animated: false)

        let name = session.title.map { "\(session.project) · \($0)" } ?? session.project
        title.set(name, animated: false)
        title.place(x: 50, midY: top, width: right - timeWidth - 58, animated: false)

        let deciding = session.awaitingDecision
        var notes: [String] = []
        if let tokens = session.contextTokens { notes.append(Self.tokens(tokens)) }
        if session.muted { notes.append(tr("silenciada", "muted")) }
        if !hostName.isEmpty { notes.append(hostName) }
        let note = deciding ? "" : notes.joined(separator: " · ")
        let hostWidth = note.isEmpty ? 0 : min(host.width(of: note), 170)
        host.set(note, animated: false)
        host.place(x: right, midY: bottom, width: hostWidth, animated: false)

        let frames = Self.buttonFrames(rowWidth: frame.width, rowHeight: frame.height)
        for (button, (_, rect)) in zip(buttons, frames) { button.place(rect, visible: deciding) }
        let detailRight = deciding ? (frames.first?.1.minX ?? right) - 8 : right - hostWidth - 8

        let statusWidth = status.width(of: session.state.label)
        status.set(session.state.label, color: session.state.color, animated: false)
        status.place(x: 50, midY: bottom, width: statusWidth, animated: false)

        let progress = session.tasks.map { "\($0.done)/\($0.total) · " } ?? ""
        detail.set(progress + session.detail, animated: false)
        detail.place(x: 56 + statusWidth, midY: bottom, width: detailRight - 56 - statusWidth, animated: false)
    }

    /// 84k ctx, 1.2M ctx
    static func tokens(_ count: Int) -> String {
        let value: String
        if count >= 1_000_000 {
            value = String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            value = "\(count / 1000)k"
        } else {
            value = "\(count)"
        }
        return value + " ctx"
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(max(interval, 0))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        if seconds < 86400 { return "\(seconds / 3600) h \(seconds % 3600 / 60) min" }
        return "\(seconds / 86400) d"
    }
}

/// Píldora de Permitir / Denegar / Terminal.
@MainActor
private final class DecisionButton {
    let layer = CALayer()
    let label: Label
    private let decision: PermissionHook.Decision

    init(_ decision: PermissionHook.Decision) {
        self.decision = decision
        label = Label(size: 11, weight: .semibold, color: Self.color(decision), align: .center)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.backgroundColor = Self.color(decision).withAlphaComponent(0.18).cgColor
        layer.addSublayer(label.layer)
        layer.isHidden = true
    }

    static func title(_ decision: PermissionHook.Decision) -> String {
        switch decision {
        case .allow: tr("Permitir", "Allow")
        case .deny: tr("Denegar", "Deny")
        case .ask: "Terminal"
        }
    }

    static func width(_ decision: PermissionHook.Decision) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        return ceil((title(decision) as NSString).size(withAttributes: [.font: font]).width) + 20
    }

    static func color(_ decision: PermissionHook.Decision) -> NSColor {
        switch decision {
        case .allow: SessionState.done.color
        case .deny: SessionState.error.color
        case .ask: NSColor(white: 0.8, alpha: 1)
        }
    }

    func place(_ frame: CGRect, visible: Bool) {
        layer.isHidden = !visible
        guard visible else { return }
        layer.frame = frame
        label.set(Self.title(decision), animated: false)
        label.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        label.place(x: frame.width / 2, midY: frame.height / 2, width: frame.width, animated: false)
    }
}
