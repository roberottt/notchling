import AppKit
import NotchCore
import ServiceManagement

private final class ActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @MainActor @objc private func run() { handler() }
}

/// Lo que se puede hacer con una sesión desde los menús.
@MainActor
struct SessionActions {
    var select: (Session) -> Void
    var decide: (Session, PermissionHook.Decision) -> Void
    var togglePin: (Session) -> Void
    var toggleMute: (Session) -> Void
    var rename: (Session) -> Void
    var toggleHidden: (Session) -> Void
    var isHidden: (Session) -> Bool
}

/// Lo que cambia algo fuera de las preferencias.
@MainActor
struct AppSettings {
    var approvalsInstalled: Bool
    var toggleApprovals: () -> Void
}

@MainActor
enum AppMenu {
    static func fill(
        _ menu: NSMenu, sessions: [Session], displays: [Display], preferences: Preferences,
        actions: SessionActions, settings: AppSettings
    ) {
        menu.removeAllItems()
        if sessions.isEmpty {
            let item = NSMenuItem(title: tr("No hay sesiones abiertas", "No open sessions"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for session in sessions {
            var title = "\(session.title.map { "\(session.project) · \($0)" } ?? session.project) — \(session.state.label)"
            if actions.isHidden(session) { title += " (" + tr("oculta", "hidden") + ")" }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.image = dot(session.state.color)
            item.submenu = sessionMenu(session, actions: actions)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let position = NSMenuItem(title: tr("Posición", "Position"), action: nil, keyEquivalent: "")
        position.submenu = positionMenu(displays: displays, preferences: preferences)
        menu.addItem(position)

        let language = NSMenuItem(title: tr("Idioma", "Language"), action: nil, keyEquivalent: "")
        language.submenu = languageMenu(preferences: preferences)
        menu.addItem(language)

        menu.addItem(ActionItem(tr("Desplegar cuando te necesite", "Expand when you're needed"), checked: preferences.autoExpand) {
            preferences.autoExpand.toggle()
        })
        menu.addItem(ActionItem(tr("Apartarse de los menús de las apps", "Make way for app menus"), checked: preferences.yieldToMenus) {
            preferences.yieldToMenus.toggle()
        })
        menu.addItem(ActionItem(tr("Modo compacto", "Compact mode"), checked: preferences.compact) { preferences.compact.toggle() })
        menu.addItem(ActionItem(tr("Mostrar aunque no haya sesiones", "Show even with no sessions"), checked: preferences.showWhenEmpty) {
            preferences.showWhenEmpty.toggle()
        })
        menu.addItem(ActionItem(tr("Ocultar", "Hide"), checked: preferences.hidden) { preferences.hidden.toggle() })
        menu.addItem(.separator())

        menu.addItem(ActionItem(tr("Notificaciones", "Notifications"), checked: preferences.notifications) {
            preferences.notifications.toggle()
        })
        let sound = ActionItem(tr("Sonido en las notificaciones", "Notification sound"), checked: preferences.notificationSound) {
            preferences.notificationSound.toggle()
        }
        sound.isEnabled = preferences.notifications
        menu.addItem(sound)
        menu.addItem(ActionItem(
            tr("Atajo \(HotKey.label): ir a quien te necesita", "\(HotKey.label) shortcut: jump to who needs you"),
            checked: preferences.hotKey
        ) { preferences.hotKey.toggle() })
        if Bundle.main.bundleIdentifier != nil {
            menu.addItem(ActionItem(
                tr("Aprobar permisos desde la isla", "Approve permissions from the island"),
                checked: settings.approvalsInstalled, handler: settings.toggleApprovals))
        }
        menu.addItem(.separator())

        if Bundle.main.bundleIdentifier != nil {
            menu.addItem(ActionItem(tr("Abrir al iniciar sesión", "Open at login"), checked: SMAppService.mainApp.status == .enabled) {
                toggleLoginItem()
            })
        }
        menu.addItem(ActionItem(tr("Salir de Notchling", "Quit Notchling")) { NSApp.terminate(nil) })
    }

    /// Menú de una sesión: submenú en la barra y clic derecho sobre su fila.
    static func sessionMenu(_ session: Session, actions: SessionActions) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionItem(tr("Ir a la sesión", "Go to session")) { actions.select(session) })
        if session.awaitingDecision {
            menu.addItem(.separator())
            let heading = NSMenuItem(title: session.requestText ?? session.detail, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            menu.addItem(ActionItem(tr("Permitir", "Allow")) { actions.decide(session, .allow) })
            menu.addItem(ActionItem(tr("Denegar", "Deny")) { actions.decide(session, .deny) })
            menu.addItem(ActionItem(tr("Contestar en la terminal", "Answer in the terminal")) { actions.decide(session, .ask) })
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem(tr("Fijar arriba", "Pin to top"), checked: session.pinned) { actions.togglePin(session) })
        menu.addItem(ActionItem(
            session.muted ? tr("Volver a avisar", "Unmute") : tr("Silenciar 1 hora", "Mute for 1 hour")
        ) { actions.toggleMute(session) })
        menu.addItem(ActionItem(tr("Renombrar…", "Rename…")) { actions.rename(session) })
        menu.addItem(ActionItem(
            actions.isHidden(session) ? tr("Mostrar en la isla", "Show in the island") : tr("Ocultar de la isla", "Hide from the island")
        ) { actions.toggleHidden(session) })
        return menu
    }

    private static func positionMenu(displays: [Display], preferences: Preferences) -> NSMenu {
        let menu = NSMenu()
        let selected = preferences.placement(for: displays)
        menu.addItem(ActionItem(tr("Automática", "Automatic"), checked: selected == .automatic) {
            preferences.setPlacement(.automatic, for: displays)
        })
        menu.addItem(.separator())
        for display in displays {
            if display.notch != nil {
                let placement = Placement.notch(display: display.id)
                menu.addItem(ActionItem(tr("En el notch — \(display.name)", "In the notch — \(display.name)"), checked: selected == placement) {
                    preferences.setPlacement(placement, for: displays)
                })
            }
            let placement = Placement.topCenter(display: display.id)
            menu.addItem(ActionItem(tr("Arriba en el centro — \(display.name)", "Top center — \(display.name)"), checked: selected == placement) {
                preferences.setPlacement(placement, for: displays)
            })
        }
        return menu
    }

    private static func languageMenu(preferences: Preferences) -> NSMenu {
        let menu = NSMenu()
        for language in Language.allCases {
            menu.addItem(ActionItem(language.name, checked: preferences.language == language) {
                preferences.language = language
            })
        }
        return menu
    }

    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private static func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = tr(
                "Instala la app con scripts/build.sh --install e inténtalo otra vez.",
                "Install the app with scripts/build.sh --install and try again.")
            NSApp.activate()
            alert.runModal()
        }
    }
}
