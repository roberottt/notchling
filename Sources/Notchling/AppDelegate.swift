import AppKit
import NotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let demo: Bool
    private let preferences: Preferences
    private let hosts = HostApps()
    private let feed = SessionFeed()

    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private var statusSymbol: String?
    private let statusMenu = NSMenu()
    private var tracker = AttentionTracker()
    private var latest: [Session] = []
    private var sessions: [Session] = []
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
        island.onSelect = { [weak self] in self?.select($0) }
        self.island = island
        preferences.onChange = { [weak island] in island?.reload() }

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

        island.reload()
        feed.start(demo: demo) { [weak self] in self?.receive($0) }
    }

    /// Abrir la app de nuevo la vuelve a mostrar si estaba oculta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferences.hidden = false
        return true
    }

    private func receive(_ raw: [Session]) {
        latest = raw
        let update = tracker.update(raw)
        hosts.update(update.sessions)
        let changed = update.sessions != sessions
        sessions = update.sessions
        island?.update(sessions: update.sessions, alerts: update.alerts)
        if changed { updateStatusItem() }
    }

    private func select(_ session: Session) {
        tracker.acknowledge(session.id)
        hosts.activate(session)
        receive(latest)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let waiting = sessions.filter { $0.state.needsUser }.count
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
            menu, sessions: sessions, displays: Display.current(), preferences: preferences,
            select: { [weak self] in self?.select($0) })
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
