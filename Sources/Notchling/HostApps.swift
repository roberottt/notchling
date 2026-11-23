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

    func activate(_ session: Session) {
        guard let app = cache[session.id] ?? nil, !app.isTerminated else { return }
        // activate() no siempre funciona desde una app sin foco; LaunchServices sí.
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            app.activate()
        }
    }
}
