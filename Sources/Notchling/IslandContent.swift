import Foundation
import NotchCore

struct IslandContent {
    /// Ordenadas por urgencia.
    var sessions: [Session]
    /// Las filas que caben, en el orden en que se muestran.
    var visible: [Session]
    var hosts: [String: String]
    var layout: IslandLayout
    var panel: CGRect
    var expanded: Bool
    var hoveredRow: Int?
    var snapping: Bool
    var compact: Bool
    var yielding: Bool

    static func isMinimal(_ sessions: [Session], compact: Bool) -> Bool {
        compact || (sessions.first?.state ?? .idle) >= .idle
    }

    static func wingWidth(_ sessions: [Session], compact: Bool) -> CGFloat {
        if isMinimal(sessions, compact: compact) { return sessions.count > 1 ? 56 : 42 }
        return sessions.count > 1 ? 160 : 138
    }
}
