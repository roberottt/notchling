import AppKit
import NotchCore

@MainActor
final class IslandController: IslandViewDelegate {
    private struct Drag {
        var grab: CGSize
        var pointer: CGPoint
        var snapped: Display?
    }

    let panel = IslandPanel()
    var makeMenu: () -> NSMenu = { NSMenu() }
    var onSelect: (Session) -> Void = { _ in }
    var onDecision: (Session, PermissionHook.Decision) -> Void = { _, _ in }
    var makeSessionMenu: (Session) -> NSMenu = { _ in NSMenu() }

    private let view = IslandView(frame: .zero)
    private let preferences: Preferences
    private let hosts: HostApps

    private(set) var displays = Display.current()
    private var sessions: [Session] = []
    private var frozenOrder: [String]?
    private var scrollOffset = 0

    private var current: (layout: IslandLayout, panel: CGRect)?
    private var expanded = false
    private var hovering = false
    private var hoveredRow: Int?
    private var waitsForExit = false
    private var menuOpen = false
    /// Cambios recibidos con un menú abierto: se pintan al cerrarlo.
    private var pendingRender = false
    private var peekUntil: Date?
    /// Abierta con el atajo: no se recoge porque nadie te necesite.
    private var manualPeek = false
    private let preview = PreviewPanel()
    private var previewWork: DispatchWorkItem?
    private var previewFor: String?
    private var pressedAt: CGPoint?
    private var drag: Drag?
    /// Alas recogidas dentro del notch para no tapar los menús de las apps.
    private var yielding = false
    private var yieldEnds: Date?
    private var foreignMenuOpen = false
    private var previousApp: NSRunningApplication?

    private var hoverWork: DispatchWorkItem?
    private var clock: Timer?
    private var monitor: Any?
    /// Menú esperando a que la app sea la activa para abrirse.
    private var pendingMenu: (() -> Void)?
    private var menuRequest = 0

    init(preferences: Preferences, hosts: HostApps) {
        self.preferences = preferences
        self.hosts = hosts
        panel.contentView = view
        view.delegate = self
        // Mientras la ventana deja pasar los clics, el ratón solo se ve con un monitor global.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.openPendingMenu() }
        }
    }

    func update(sessions new: [Session], alerts: [Session]) {
        let changed = new != sessions
        sessions = new
        let now = Date()

        if preferences.autoExpand, !alerts.isEmpty, drag == nil {
            peekUntil = now.addingTimeInterval(6)
            waitsForExit = false
            // Con un menú abierto se aplaza: desplegarse debajo lo estorbaría.
            if !menuOpen { setExpanded(true) }
        } else if let until = peekUntil, now >= until || (new.first?.state.needsUser != true && !manualPeek) {
            peekUntil = nil
            manualPeek = false
            if !hovering, !menuOpen { setExpanded(false) }
        }

        // Con nuestro menú abierto no se toca el WindowServer ni la ventana: cada consulta o
        // cambio de marco compite con el seguimiento del menú y el resaltado avanza a saltos.
        guard !menuOpen else {
            if changed { pendingRender = true }
            return
        }
        foreignMenuOpen = yielding && otherAppHasMenuOpen()
        if changed { render(animated: true) }
        pointerMoved()
    }

    func screensChanged() {
        displays = Display.current()
        drag = nil
        pressedAt = nil
        hosts.update(sessions)
        render(animated: false)
    }

    func reload() {
        render(animated: true)
    }

    // MARK: - Pintado

    private func makeLayout() -> (layout: IslandLayout, panel: CGRect)? {
        let wing = yielding && drag == nil ? 0 : IslandContent.wingWidth(sessions, compact: preferences.compact)
        let rows = sessions.count

        if let drag {
            if let display = drag.snapped, let notch = display.notch {
                let layout = IslandLayout(screen: display.frame, anchor: .notch(notch), wing: wing, rows: rows)
                return (layout, layout.panel)
            }
            let desktop = displays.reduce(CGRect.null) { $0.union($1.frame) }
            let top = CGPoint(x: drag.pointer.x - drag.grab.width, y: drag.pointer.y + drag.grab.height)
            let layout = IslandLayout(screen: desktop, anchor: .floating(top), wing: wing, rows: rows)
            // Ventana mínima al arrastrar: macOS la muestra en la pantalla que contiene su mayor parte.
            return (layout, layout.collapsed.insetBy(dx: -IslandLayout.margin, dy: -IslandLayout.margin))
        }

        guard let (display, anchor) = preferences.placement(for: displays).resolve(in: displays) else { return nil }
        let layout = IslandLayout(screen: display.frame, anchor: anchor, wing: wing, rows: rows)
        return (layout, layout.panel)
    }

    private func render(animated: Bool) {
        pendingRender = false
        let wanted = !preferences.hidden && (!sessions.isEmpty || preferences.showWhenEmpty || drag != nil)
        guard wanted, let next = makeLayout() else {
            panel.orderOut(nil)
            current = nil
            expanded = false
            hovering = false
            frozenOrder = nil
            updateClock()
            return
        }

        let appearing = !panel.isVisible
        current = next
        if panel.frame != next.panel { panel.setFrame(next.panel, display: false) }

        let content = IslandContent(
            sessions: sessions, visible: visibleSessions(), hosts: hosts.names,
            layout: next.layout, panel: next.panel,
            expanded: expanded && drag == nil, hoveredRow: hoveredRow,
            snapping: drag?.snapped != nil, compact: preferences.compact, yielding: yielding && drag == nil)
        view.render(content, animated: animated && !appearing)

        updatePreview()

        if appearing {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
        }
    }

    /// La vista previa sale tras un momento sobre la misma fila y sigue a la isla mientras se repinta.
    private func updatePreview() {
        let visible = visibleSessions()
        // Un permiso pendiente se enseña entero sin tener que pasar por encima: es lo que se aprueba.
        let hovered = hoveredRow.flatMap { $0 < visible.count ? visible[$0] : nil }
        let target = hovered ?? visible.first(where: \.awaitingDecision)
        let text = target.flatMap { $0.awaitingDecision ? $0.requestText : $0.lastMessage }
        guard expanded, !menuOpen, drag == nil, let target, let layout = current?.layout, let text, !text.isEmpty
        else {
            previewWork?.cancel()
            previewWork = nil
            previewFor = nil
            preview.hide()
            return
        }
        let session = target
        var heading = session.title.map { "\(session.project) · \($0)" } ?? session.project
        if session.awaitingDecision { heading += " — " + SessionState.permission.label }
        let show = { [weak self] in
            self?.preview.show(
                heading: heading, text: text, anchor: layout.expanded, upward: layout.opensUpward, screen: layout.screen)
        }
        let key = session.id + (session.awaitingDecision ? "#decision" : "")
        if previewFor == key {
            if previewWork == nil { show() }
            return
        }
        if session.awaitingDecision {
            previewWork?.cancel()
            previewWork = nil
            previewFor = key
            show()
            return
        }
        previewFor = key
        previewWork?.cancel()
        preview.hide()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.previewWork = nil
                show()
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    /// Atajo de teclado: abre la lista unos segundos, o la cierra si ya estaba abierta.
    func toggleList() {
        guard current != nil, panel.isVisible, !menuOpen, drag == nil else { return }
        if expanded {
            peekUntil = nil
            manualPeek = false
            setExpanded(false)
        } else {
            waitsForExit = false
            peekUntil = Date().addingTimeInterval(8)
            manualPeek = true
            setExpanded(true)
        }
    }

    private func visibleSessions() -> [Session] {
        var ordered = sessions
        if let frozenOrder {
            // Bajo el cursor las filas no se reordenan: un clic no debe caer en otra sesión.
            let position = Dictionary(uniqueKeysWithValues: frozenOrder.enumerated().map { ($1, $0) })
            ordered = sessions.enumerated().sorted {
                (position[$0.element.id] ?? .max, $0.offset) < (position[$1.element.id] ?? .max, $1.offset)
            }.map(\.element)
        }
        scrollOffset = max(0, min(scrollOffset, ordered.count - IslandLayout.maxRows))
        return Array(ordered.dropFirst(scrollOffset).prefix(IslandLayout.maxRows))
    }

    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        expanded = value
        if value {
            yielding = false
            yieldEnds = nil
        }
        if !value {
            scrollOffset = 0
            hoveredRow = nil
        }
        updateClock()
        render(animated: true)
    }

    private func updateClock() {
        clock?.invalidate()
        clock = nil
        guard expanded else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(animated: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    // MARK: - Ratón

    func pointerMoved() {
        guard pressedAt == nil, drag == nil, !menuOpen, current != nil, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        // Recoger o sacar las alas cambia la zona sensible: se repinta antes de medirla.
        if updateYield(mouse: mouse) { render(animated: true) }
        guard let layout = current?.layout else { return }
        let area = (expanded ? layout.expanded : layout.collapsed).insetBy(dx: -2, dy: -2)
        // Cruzar el notch con un menú de otra app abierto no debe desplegar la isla.
        let inside = area.contains(mouse) && !isCovered(at: mouse) && !foreignMenuOpen
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if inside != hovering {
            hovering = inside
            frozenOrder = inside ? sessions.map(\.id) : nil
            if !inside { waitsForExit = false }

            hoverWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.settleHover() }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.14 : 0.3), execute: work)
        }

        let row = inside && expanded ? layout.row(at: mouse).flatMap { $0 < sessions.count ? $0 : nil } : nil
        if row != hoveredRow {
            hoveredRow = row
            render(animated: true)
        }
    }

    /// Recoge las alas mientras el ratón está en la barra de menús fuera del notch,
    /// o mientras otra app tiene un menú abierto. Devuelve si ha cambiado.
    private func updateYield(mouse: CGPoint) -> Bool {
        let before = yielding
        guard preferences.yieldToMenus, !expanded, let layout = current?.layout,
              case .notch(let notch) = layout.anchor
        else {
            yielding = false
            yieldEnds = nil
            return before != yielding
        }

        let menuBar = CGRect(x: layout.screen.minX, y: notch.minY, width: layout.screen.width, height: notch.height + 1)
        let inMenuBar = menuBar.contains(mouse) && !notch.insetBy(dx: -2, dy: -2).contains(mouse)
        if inMenuBar || (yielding && foreignMenuOpen) {
            yielding = true
            yieldEnds = nil
        } else if yielding {
            // Margen para alcanzar el menú desplegado sin que las alas vuelvan entretanto.
            let ends = yieldEnds ?? Date().addingTimeInterval(0.8)
            yieldEnds = ends
            if Date() >= ends {
                yielding = false
                yieldEnds = nil
            }
        }
        return before != yielding
    }

    /// Algún menú de otra app abierto en la pantalla de la isla (barra de menús, iconos, contextuales).
    private func otherAppHasMenuOpen() -> Bool {
        guard let screen = current?.layout.screen,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return windows.contains { window in
            guard window[kCGWindowLayer as String] as? Int == level, window[kCGWindowOwnerPID as String] as? Int != me,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            // Las coordenadas de CoreGraphics tienen el origen arriba a la izquierda.
            let frame = CGRect(
                x: bounds["X"] ?? 0, y: top - (bounds["Y"] ?? 0) - (bounds["Height"] ?? 0),
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            return frame.intersects(screen)
        }
    }

    /// Hay otra ventana (un menú, un submenú, otra app) por encima de la isla en ese punto.
    /// Las que dejan pasar los clics no cuentan, porque el sistema ya se las salta.
    private func isCovered(at point: CGPoint) -> Bool {
        let top = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard top != panel.windowNumber else { return false }
        return top != NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: panel.windowNumber)
    }

    private func settleHover() {
        guard drag == nil, pressedAt == nil, !menuOpen else { return }
        if hovering {
            if !waitsForExit { setExpanded(true) }
        } else if peekUntil == nil {
            setExpanded(false)
        }
    }

    func pointerDown() {
        pressedAt = NSEvent.mouseLocation
        hoverWork?.cancel()
    }

    func pointerDragged() {
        guard let start = pressedAt, let current else { return }
        let mouse = NSEvent.mouseLocation

        if drag == nil {
            guard hypot(mouse.x - start.x, mouse.y - start.y) > 4 else { return }
            let pill = current.layout.collapsed
            let half = max(pill.width / 2 - 12, 0)
            // Al despegar del notch la ventanita es más estrecha: se centra bajo el cursor.
            let x = current.layout.isNotch ? 0 : max(-half, min(start.x - pill.midX, half))
            let y = max(6, min(pill.maxY - start.y, IslandLayout.floatingHeight - 6))
            drag = Drag(grab: CGSize(width: x, height: y), pointer: mouse)
            expanded = false
            hoveredRow = nil
            peekUntil = nil
            updateClock()
        }

        drag?.pointer = mouse
        drag?.snapped = displays.first { display in
            guard let notch = display.notch else { return false }
            let zone = CGRect(x: notch.minX - 70, y: notch.minY - 30, width: notch.width + 140, height: notch.height + 31)
            return zone.contains(mouse)
        }
        render(animated: false)
    }

    func pointerUp() {
        defer { pressedAt = nil }
        guard let drag else {
            clicked()
            return
        }

        var placement: Placement?
        if let display = drag.snapped {
            placement = .notch(display: display.id)
        } else if let display = displays.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(drag.pointer) }),
                  let pill = current?.layout.collapsed {
            let frame = display.frame
            let half = pill.width / 2
            var x = IslandLayout.clamp(pill.midX, frame.minX + half, frame.maxX - half)
            if abs(x - frame.midX) < 16 { x = frame.midX }
            let top = IslandLayout.clamp(pill.maxY, frame.minY + pill.height, frame.maxY)
            placement = .custom(display: display.id, x: (x - frame.minX) / frame.width, top: frame.maxY - top)
        }

        self.drag = nil
        hovering = true
        waitsForExit = true
        if let placement { preferences.setPlacement(placement, for: displays) }
        render(animated: false)
    }

    private func clicked() {
        guard let current else { return }
        guard expanded else {
            waitsForExit = false
            setExpanded(true)
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let row = current.layout.row(at: mouse) else { return }
        let visible = visibleSessions()
        guard row < visible.count else { return }
        if visible[row].awaitingDecision, let decision = decision(at: mouse, row: row, layout: current.layout) {
            onDecision(visible[row], decision)
            return
        }
        waitsForExit = true
        peekUntil = nil
        setExpanded(false)
        onSelect(visible[row])
    }

    func scrolled(rows: Int) {
        guard expanded else { return }
        scrollOffset += rows
        render(animated: true)
    }

    private func decision(at mouse: CGPoint, row: Int, layout: IslandLayout) -> PermissionHook.Decision? {
        let box = layout.expanded
        let point = CGPoint(
            x: mouse.x - box.minX,
            y: box.maxY - mouse.y - layout.headerHeight - IslandLayout.padding - CGFloat(row) * IslandLayout.rowHeight)
        return SessionRow.buttonFrames(rowWidth: box.width, rowHeight: IslandLayout.rowHeight)
            .first { $0.1.insetBy(dx: -3, dy: -5).contains(point) }?.0
    }

    func showMenu(at point: NSPoint, in view: NSView) {
        // Sobre una fila, el menú es el de esa sesión. Se decide antes de que la isla se recoja.
        var session: Session?
        if expanded, let row = current?.layout.row(at: NSEvent.mouseLocation) {
            let visible = visibleSessions()
            if row < visible.count { session = visible[row] }
        }
        whenFocused { [weak self] in
            guard let self else { return }
            self.menuVisibilityChanged(open: true)
            let menu = session.map(self.makeSessionMenu) ?? self.makeMenu()
            menu.popUp(positioning: nil, at: point, in: view)
            self.menuVisibilityChanged(open: false)
        }
    }

    /// Abre un menú cuando la app ya es la activa. Si no lo es, macOS sigue mandando el ratón a la app
    /// de delante: el resaltado del menú va a saltos y lo que hay detrás reacciona al cursor.
    /// Activarse con el menú ya abierto llega tarde, por eso se espera a la activación antes de abrirlo.
    func whenFocused(_ open: @escaping () -> Void) {
        if NSApp.isActive {
            open()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? nil : front
        menuRequest += 1
        let request = menuRequest
        pendingMenu = open
        // activate() es cooperativa desde macOS 14 y la app de delante puede negarse; esta no.
        NSApp.activate(ignoringOtherApps: true)
        // Si la activación no llega, el menú se abre igualmente.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard self?.menuRequest == request else { return }
                self?.openPendingMenu()
            }
        }
    }

    private func openPendingMenu() {
        guard let open = pendingMenu else { return }
        pendingMenu = nil
        menuRequest += 1
        open()
    }

    /// Mientras haya un menú abierto, la isla se recoge y deja pasar el ratón.
    func menuVisibilityChanged(open: Bool) {
        menuOpen = open
        hoverWork?.cancel()
        if open {
            pressedAt = nil
            hovering = false
            frozenOrder = nil
            hoveredRow = nil
            panel.ignoresMouseEvents = true
            setExpanded(false)
            return
        }
        returnFocusAfterMenu()
        foreignMenuOpen = false
        if pendingRender { render(animated: true) }
        if let until = peekUntil, until > Date() { setExpanded(true) }
        pointerMoved()
        // Si el ratón ya estaba encima al cerrar, no se despliega hasta que salga y vuelva.
        waitsForExit = hovering
        settleHover()
    }

    private func returnFocusAfterMenu() {
        guard let previous = previousApp else { return }
        previousApp = nil
        // Después de la acción elegida: si abrió otra app o un aviso, el foco ya no es cosa nuestra.
        DispatchQueue.main.async {
            guard NSApp.isActive, NSApp.modalWindow == nil, !previous.isTerminated else { return }
            previous.activate()
        }
    }
}
