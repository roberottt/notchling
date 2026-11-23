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

    var labels: [Label] { [title, status, detail, time, host] }

    init() {
        highlight.backgroundColor = NSColor(white: 1, alpha: 0.11).cgColor
        highlight.cornerRadius = 14
        highlight.cornerCurve = .continuous
        highlight.opacity = 0
        layer.addSublayer(highlight)
        layer.addSublayer(glyph.layer)
        for label in labels { layer.addSublayer(label.layer) }
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

        let hostWidth = hostName.isEmpty ? 0 : min(host.width(of: hostName), 110)
        host.set(hostName, animated: false)
        host.place(x: right, midY: bottom, width: hostWidth, animated: false)

        let statusWidth = status.width(of: session.state.label)
        status.set(session.state.label, color: session.state.color, animated: false)
        status.place(x: 50, midY: bottom, width: statusWidth, animated: false)

        detail.set(session.detail, animated: false)
        detail.place(x: 56 + statusWidth, midY: bottom, width: right - hostWidth - 64 - statusWidth, animated: false)
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let seconds = Int(max(interval, 0))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        if seconds < 86400 { return "\(seconds / 3600) h \(seconds % 3600 / 60) min" }
        return "\(seconds / 86400) d"
    }
}
