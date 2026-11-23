import Foundation

/// Añade lo que depende del historial: «Listo», los errores y qué avisos son nuevos.
public struct AttentionTracker {
    public static let doneDuration: TimeInterval = 300
    public static let errorDuration: TimeInterval = 600

    private var previous: [String: SessionState] = [:]
    private var finished: [String: Date] = [:]
    private var acknowledged: [String: Date] = [:]

    public init() {}

    /// `alerts`: acaban de pedirte algo. `finished`: acaban de terminar un turno.
    public mutating func update(_ raw: [Session], now: Date = Date()) -> (sessions: [Session], alerts: [Session], finished: [Session]) {
        var sessions: [Session] = []
        var alerts: [Session] = []
        var finished: [Session] = []

        for var session in raw {
            let id = session.id
            let before = previous[id]
            previous[id] = session.state

            if session.state.needsUser, before != session.state { alerts.append(session) }

            if session.state == .idle {
                if let before, before == .working || before.needsUser {
                    self.finished[id] = now
                    if session.outcome != .interrupted { finished.append(session) }
                }

                let seen = acknowledged[id].map { $0 >= session.since } ?? false
                if !seen {
                    if session.outcome == .failed, now.timeIntervalSince(session.since) < Self.errorDuration {
                        session.state = .error
                    } else if let end = self.finished[id], now.timeIntervalSince(end) < Self.doneDuration,
                              session.outcome != .interrupted {
                        // El transcript puede ir unas décimas por detrás; «running» justo al acabar es normal.
                        session.state = .done
                    }
                }
            } else if session.state != .dialog {
                self.finished[id] = nil
            }
            sessions.append(session)
        }

        let live = Set(raw.map(\.id))
        previous = previous.filter { live.contains($0.key) }
        self.finished = self.finished.filter { live.contains($0.key) }
        acknowledged = acknowledged.filter { live.contains($0.key) }

        sessions.sort { ($0.state, $0.startedAt, $0.pid) < ($1.state, $1.startedAt, $1.pid) }
        return (sessions, alerts, finished)
    }

    public mutating func acknowledge(_ id: String, now: Date = Date()) {
        acknowledged[id] = now
        finished[id] = nil
    }
}
