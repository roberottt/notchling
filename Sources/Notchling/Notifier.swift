import AppKit
import NotchCore
import UserNotifications

/// Notificaciones de macOS. Pasan por el sistema, así que respetan los modos de Concentración.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let permissionCategory = "permission"
    private static let allowAction = "allow"
    private static let denyAction = "deny"

    /// Pulsar la notificación: la sesión por su `id`.
    var onOpen: (String) -> Void = { _ in }
    /// Botones Permitir / Denegar: el identificador de la petición pendiente.
    var onDecision: (UUID, PermissionHook.Decision) -> Void = { _, _ in }

    /// Sin paquete .app (swift run) el centro de notificaciones aborta la app.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()

    func start() {
        guard let center else { return }
        center.delegate = self
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Los textos de los botones van con el idioma: se registran de nuevo al cambiarlo.
    func registerCategories() {
        // Con el Mac bloqueado, contestar pide desbloquearlo antes.
        let allow = UNNotificationAction(
            identifier: Self.allowAction, title: tr("Permitir", "Allow"), options: [.authenticationRequired])
        let deny = UNNotificationAction(
            identifier: Self.denyAction, title: tr("Denegar", "Deny"), options: [.destructive, .authenticationRequired])
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: Self.permissionCategory, actions: [allow, deny], intentIdentifiers: []),
        ])
    }

    func needsYou(_ session: Session, request: UUID?, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.project) — \(session.state.label)"
        content.body = session.requestText ?? session.detail
        // Los botones solo si el texto entero cabe en el aviso; si no, se contesta donde se lee entero.
        if let request, let text = session.requestText, text.unicodeScalars.count <= PermissionHook.maxNotified {
            content.categoryIdentifier = Self.permissionCategory
            content.userInfo["request"] = request.uuidString
        }
        post(content, session: session, sound: sound)
    }

    func finished(_ session: Session, sound: Bool) {
        let content = UNMutableNotificationContent()
        let failed = session.outcome == .failed
        content.title = "\(session.project) — \(failed ? SessionState.error.label : SessionState.done.label)"
        content.body = session.lastMessage ?? tr("Ha terminado", "Finished")
        post(content, session: session, sound: sound)
    }

    private func post(_ content: UNMutableNotificationContent, session: Session, sound: Bool) {
        guard let center else { return }
        if let title = session.title { content.subtitle = title }
        content.userInfo["session"] = session.id
        if sound { content.sound = .default }
        // Una por sesión: la nueva sustituye a la anterior.
        center.add(UNNotificationRequest(identifier: session.id, content: content, trigger: nil))
    }

    func clear(_ session: Session) {
        center?.removeDeliveredNotifications(withIdentifiers: [session.id])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let session = info["session"] as? String
        let request = (info["request"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.allowAction: if let request { onDecision(request, .allow) }
            case Self.denyAction: if let request { onDecision(request, .deny) }
            case UNNotificationDefaultActionIdentifier: if let session { onOpen(session) }
            default: break
            }
        }
    }
}
