import AppKit
import NotchCore

/// Localiza la app (terminal, editor o Claude Desktop) que aloja cada sesión.
@MainActor
final class HostApps {
    private var cache: [String: NSRunningApplication?] = [:]
    private(set) var names: [String: String] = [:]

    func update(_ sessions: [Session]) {
        let live = Set(sessions.map(\.id))
        cache = cache.filter { live.contains($0.key) }
        names = names.filter { live.contains($0.key) }
        for session in sessions where cache.index(forKey: session.id) == nil {
            let app = session.ancestors.lazy
                .compactMap { NSRunningApplication(processIdentifier: $0) }
                .first { $0.activationPolicy == .regular }
            cache.updateValue(app, forKey: session.id)
            names[session.id] = app?.localizedName ?? ""
        }
    }

    func app(for session: Session) -> NSRunningApplication? {
        cache[session.id] ?? nil
    }

    func activate(_ session: Session) {
        guard let app = cache[session.id] ?? nil, !app.isTerminated else { return }
        defer { selectTab(of: session, in: app) }
        // activate() no siempre funciona desde una app sin foco; LaunchServices sí.
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            app.activate()
        }
    }

    /// En Terminal e iTerm2 se puede ir a la pestaña exacta por su tty. La primera vez macOS pide
    /// permiso para controlarlas; sin él, la app se activa igualmente.
    private func selectTab(of session: Session, in app: NSRunningApplication) {
        guard let tty = session.tty, tty.range(of: #"^/dev/tty[a-z0-9]+$"#, options: .regularExpression) != nil else { return }
        let script: String
        switch app.bundleIdentifier {
        case "com.apple.Terminal":
            script = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            script = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                tell t to select
                                tell s to select
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
