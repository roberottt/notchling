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

@MainActor
enum AppMenu {
    static func fill(
        _ menu: NSMenu, sessions: [Session], displays: [Display], preferences: Preferences,
        select: @escaping @MainActor (Session) -> Void
    ) {
        menu.removeAllItems()
        if sessions.isEmpty {
            let item = NSMenuItem(title: tr("No hay sesiones abiertas", "No open sessions"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for session in sessions {
            let item = ActionItem("\(session.project) — \(session.state.label)") { select(session) }
            item.image = dot(session.state.color)
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

        if Bundle.main.bundleIdentifier != nil {
            menu.addItem(ActionItem(tr("Abrir al iniciar sesión", "Open at login"), checked: SMAppService.mainApp.status == .enabled) {
                toggleLoginItem()
            })
        }
        menu.addItem(ActionItem(tr("Salir de Notchling", "Quit Notchling")) { NSApp.terminate(nil) })
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
