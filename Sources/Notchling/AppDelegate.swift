import AppKit
import NotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let demo: Bool
    private let preferences: Preferences
    private let hosts = HostApps()
    private let feed = SessionFeed()
    private let notifier = Notifier()
    private let broker = PermissionBroker()

    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private var statusSymbol: String?
    private let statusMenu = NSMenu()
    private var hotKey: HotKey?
    private var tracker = AttentionTracker()
    private var latest: [Session] = []
    /// Todas, incluidas las ocultas: las usa el menú.
    private var all: [Session] = []
    /// Las que se ven en la isla.
    private var sessions: [Session] = []
    /// Silenciadas hasta una hora; solo en memoria.
    private var mutedUntil: [String: Date] = [:]
    private var language = Language.current
    private var activity: NSObjectProtocol?

    init(demo: Bool) {
        self.demo = demo
        // La demo no debe pisar la configuración real.
        let store = demo ? UserDefaults(suiteName: "local.notchling.demo") ?? .standard : .standard
        if !demo { Self.importOldPreferences() }
        preferences = Preferences(store: store)
        super.init()
    }

    /// La app se llamaba NotchVisualizer: la primera vez se traen sus preferencias.
    private static func importOldPreferences() {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier,
              defaults.persistentDomain(forName: id)?.isEmpty ?? true,
              let old = defaults.persistentDomain(forName: "local.notchvisualizer"), !old.isEmpty
        else { return }
        defaults.setPersistentDomain(old, forName: id)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !demo, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .contains(where: { $0 != .current && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }

        // Sin esto App Nap espacia los timers y los avisos llegan tarde. No impide el reposo del Mac.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Vigilar el estado de las sesiones")

        let island = IslandController(preferences: preferences, hosts: hosts)
        island.makeMenu = { [weak self] in
            let menu = NSMenu()
            self?.fill(menu)
            return menu
        }
        island.makeSessionMenu = { [weak self] session in
            guard let self else { return NSMenu() }
            return AppMenu.sessionMenu(session, actions: self.actions)
        }
        island.onSelect = { [weak self] in self?.select($0) }
        island.onDecision = { [weak self] in self?.decide($0, $1) }
        self.island = island
        preferences.onChange = { [weak self] in self?.preferencesChanged() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        statusMenu.delegate = self
        // Sin menú fijo: el clic activa la app primero y abre el menú después (ver whenFocused).
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        statusItem = item
        updateStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil)

        notifier.onOpen = { [weak self] id in
            guard let self, let session = self.all.first(where: { $0.id == id }) else { return }
            self.select(session)
        }
        notifier.onDecision = { [weak self] request, decision in
            self?.broker.decide(request, decision)
        }
        if preferences.notifications { notifier.start() }

        // La demo no debe quedarse con el socket de la app de verdad.
        if !demo {
            broker.onChange = { [weak self] in self.map { $0.receive($0.latest) } }
            broker.start()
            HookInstaller.refresh()
        }
        updateHotKey()

        island.reload()
        feed.start(demo: demo) { [weak self] in self?.receive($0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !demo { broker.stop() }
    }

    /// Abrir la app de nuevo la vuelve a mostrar si estaba oculta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferences.hidden = false
        return true
    }

    // MARK: - Sesiones

    private func receive(_ raw: [Session]) {
        latest = raw
        let now = Date()
        mutedUntil = mutedUntil.filter { $0.value > now }

        // Un permiso pendiente en la isla manda sobre lo que diga el registro.
        var incoming = raw
        for index in incoming.indices {
            guard let request = broker.request(for: incoming[index].sessionID) else { continue }
            incoming[index].state = .permission
            incoming[index].detail = request.text
            incoming[index].since = request.arrived
            incoming[index].awaitingDecision = true
        }
        // Peticiones de sesiones que no se ven (otra carpeta de configuración...): a la terminal.
        let known = Set(raw.compactMap(\.sessionID))
        for request in broker.pending where !known.contains(request.sessionID) && now.timeIntervalSince(request.arrived) > 3 {
            broker.decide(request.id, .ask)
        }

        let update = tracker.update(incoming)
        let names = preferences.names
        let pinned = preferences.pinned
        let decorated = update.sessions.map { session in
            var session = session
            if let name = names[session.key] { session.title = name }
            session.pinned = pinned.contains(session.key)
            session.muted = mutedUntil[session.key] != nil
            return session
        }
        // Primero quien te necesita, luego las fijadas, luego el resto, cada grupo por urgencia.
        let urgent = decorated.filter { $0.state.needsUser && !$0.muted }
        let fixed = decorated.filter { !($0.state.needsUser && !$0.muted) && $0.pinned }
        let rest = decorated.filter { !($0.state.needsUser && !$0.muted) && !$0.pinned }
        all = urgent + fixed + rest

        let hidden = preferences.hiddenSessions
        let shown = all.filter { !hidden.contains($0.key) }
        let audible = Set(shown.filter { !$0.muted }.map(\.id))
        let alerts = update.alerts.filter { audible.contains($0.id) }
        let finished = update.finished.filter { audible.contains($0.id) }

        hosts.update(all)
        let changed = shown != sessions
        sessions = shown
        island?.update(sessions: shown, alerts: alerts)
        if changed { updateStatusItem() }
        notify(alerts: alerts, finished: finished)
    }

    /// No avisa si ya estás mirando la app de esa sesión.
    private func notify(alerts: [Session], finished: [Session]) {
        guard preferences.notifications, !demo else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let sound = preferences.notificationSound
        for session in alerts where hosts.app(for: session) != front {
            let request = session.awaitingDecision ? broker.request(for: session.sessionID)?.id : nil
            notifier.needsYou(session, request: request, sound: sound)
        }
        for session in finished where hosts.app(for: session) != front {
            notifier.finished(session, sound: sound)
        }
    }

    private func select(_ session: Session) {
        tracker.acknowledge(session.id)
        notifier.clear(session)
        // Ir a la sesión con un permiso pendiente: que pregunte allí.
        if session.awaitingDecision, let request = broker.request(for: session.sessionID) {
            broker.decide(request.id, .ask)
        }
        hosts.activate(session)
        receive(latest)
    }

    private func decide(_ session: Session, _ decision: PermissionHook.Decision) {
        guard let request = broker.request(for: session.sessionID) else { return }
        notifier.clear(session)
        broker.decide(request.id, decision)
        if decision == .ask { hosts.activate(session) }
    }

    private var actions: SessionActions {
        SessionActions(
            select: { [weak self] in self?.select($0) },
            decide: { [weak self] in self?.decide($0, $1) },
            togglePin: { [weak self] session in
                guard let self else { return }
                if self.preferences.pinned.contains(session.key) {
                    self.preferences.pinned.remove(session.key)
                } else {
                    self.preferences.pinned.insert(session.key)
                }
            },
            toggleMute: { [weak self] session in
                guard let self else { return }
                if self.mutedUntil[session.key] != nil {
                    self.mutedUntil[session.key] = nil
                } else {
                    self.mutedUntil[session.key] = Date().addingTimeInterval(3600)
                    self.notifier.clear(session)
                }
                self.receive(self.latest)
            },
            rename: { [weak self] in self?.rename($0) },
            toggleHidden: { [weak self] session in
                guard let self else { return }
                if self.preferences.hiddenSessions.contains(session.key) {
                    self.preferences.hiddenSessions.remove(session.key)
                } else {
                    self.preferences.hiddenSessions.insert(session.key)
                }
            },
            isHidden: { [weak self] in self?.preferences.hiddenSessions.contains($0.key) ?? false })
    }

    private func rename(_ session: Session) {
        let alert = NSAlert()
        alert.messageText = tr("Renombrar «\(session.project)»", "Rename “\(session.project)”")
        alert.informativeText = tr("Déjalo vacío para volver al título de Claude.", "Leave it empty to use Claude's title.")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = preferences.names[session.key] ?? session.title ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: tr("Guardar", "Save"))
        alert.addButton(withTitle: tr("Cancelar", "Cancel"))
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.names[session.key] = name.isEmpty ? nil : name
    }

    /// ⌃⌥N: a la sesión que te espera; si no hay ninguna, abre o cierra la lista.
    private func hotKeyPressed() {
        if let session = sessions.first(where: { $0.state.needsUser && !$0.muted }) {
            select(session)
        } else {
            island?.toggleList()
        }
    }

    // MARK: - Ajustes

    private func preferencesChanged() {
        updateHotKey()
        if preferences.notifications { notifier.start() }
        if language != Language.current {
            language = Language.current
            notifier.registerCategories()
        }
        receive(latest)
        island?.reload()
    }

    private func updateHotKey() {
        if preferences.hotKey, hotKey == nil {
            hotKey = HotKey { [weak self] in self?.hotKeyPressed() }
        } else if !preferences.hotKey, let current = hotKey {
            current.invalidate()
            hotKey = nil
        }
    }

    private func toggleApprovals() {
        do {
            if HookInstaller.isInstalled {
                try HookInstaller.uninstall()
            } else if HookInstaller.confirmInstall() {
                try HookInstaller.install()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let waiting = sessions.filter { $0.state.needsUser && !$0.muted }.count
        let symbol = waiting > 0 ? "exclamationmark.bubble.fill" : "capsule.tophalf.filled"
        let title = waiting > 0 ? " \(waiting)" : ""
        // Reasignar el botón re-maqueta el ítem de la barra, y con el menú abierto lo hace tropezar.
        if symbol != statusSymbol {
            statusSymbol = symbol
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Notchling")
        }
        if button.title != title { button.title = title }
    }

    private func fill(_ menu: NSMenu) {
        AppMenu.fill(
            menu, sessions: all, displays: Display.current(), preferences: preferences, actions: actions,
            settings: AppSettings(
                approvalsInstalled: !demo && HookInstaller.isInstalled,
                toggleApprovals: { [weak self] in self?.toggleApprovals() }))
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }

    func menuWillOpen(_ menu: NSMenu) { island?.menuVisibilityChanged(open: true) }

    func menuDidClose(_ menu: NSMenu) { island?.menuVisibilityChanged(open: false) }

    @objc private func statusClicked() {
        statusItem?.button?.highlight(true)
        island?.whenFocused { [weak self] in
            guard let self, let item = self.statusItem else { return }
            item.menu = self.statusMenu
            item.button?.performClick(nil)
            item.menu = nil
        }
    }

    @objc private func screensChanged() { island?.screensChanged() }
}
