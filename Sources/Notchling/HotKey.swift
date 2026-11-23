import Carbon
import Foundation

/// Atajo de teclado global. Carbon sigue siendo la única API que no pide permiso de accesibilidad.
@MainActor
final class HotKey {
    /// ⌃⌥N
    static let keyCode = UInt32(kVK_ANSI_N)
    static let modifiers = UInt32(controlKey | optionKey)
    static let label = "⌃⌥N"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(
            Self.keyCode, Self.modifiers, EventHotKeyID(signature: OSType(0x4E_4F_54_43), id: 1),
            GetApplicationEventTarget(), 0, &hotKey)
    }

    func invalidate() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
