import Foundation
import os

/// Idioma de la interfaz. Se lee también desde el hilo del escáner, por eso va tras un cerrojo.
public enum Language: String, CaseIterable, Sendable {
    case spanish = "es"
    case english = "en"

    private static let state = OSAllocatedUnfairLock(initialState: Language.standard)

    public static var current: Language {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// Mientras no se elija otro en el menú.
    public static let standard = Language.english

    /// Cada idioma se nombra en su propia lengua para que se reconozca aunque no se entienda el otro.
    public var name: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }
}

/// El texto en el idioma elegido.
public func tr(_ spanish: String, _ english: String) -> String {
    Language.current == .english ? english : spanish
}
