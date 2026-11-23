import Foundation
import NotchCore

@MainActor
final class Preferences {
    private let store: UserDefaults
    var onChange: (() -> Void)?

    init(store: UserDefaults) {
        self.store = store
        store.register(defaults: ["autoExpand": true, "yieldToMenus": true])
        Language.current = language
    }

    /// Sin elegir, inglés.
    var language: Language {
        get { store.string(forKey: "language").flatMap(Language.init(rawValue:)) ?? .standard }
        set {
            Language.current = newValue
            store.set(newValue.rawValue, forKey: "language")
            onChange?()
        }
    }

    var autoExpand: Bool {
        get { store.bool(forKey: "autoExpand") }
        set { save(newValue, "autoExpand") }
    }
    var yieldToMenus: Bool {
        get { store.bool(forKey: "yieldToMenus") }
        set { save(newValue, "yieldToMenus") }
    }
    var compact: Bool {
        get { store.bool(forKey: "compact") }
        set { save(newValue, "compact") }
    }
    var showWhenEmpty: Bool {
        get { store.bool(forKey: "showWhenEmpty") }
        set { save(newValue, "showWhenEmpty") }
    }
    var hidden: Bool {
        get { store.bool(forKey: "hidden") }
        set { save(newValue, "hidden") }
    }

    /// Cada combinación de monitores recuerda su posición.
    func placement(for displays: [Display]) -> Placement {
        guard let data = store.data(forKey: key(displays)),
              let placement = try? JSONDecoder().decode(Placement.self, from: data)
        else { return .automatic }
        return placement
    }

    func setPlacement(_ placement: Placement, for displays: [Display]) {
        if placement == .automatic {
            store.removeObject(forKey: key(displays))
        } else if let data = try? JSONEncoder().encode(placement) {
            store.set(data, forKey: key(displays))
        }
        onChange?()
    }

    private func key(_ displays: [Display]) -> String {
        "placement." + displays.map(\.id).sorted().joined(separator: "+")
    }

    private func save(_ value: Bool, _ key: String) {
        store.set(value, forKey: key)
        onChange?()
    }
}
