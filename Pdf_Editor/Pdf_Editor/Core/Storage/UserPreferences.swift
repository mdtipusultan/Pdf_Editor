import SwiftUI

@Observable
final class UserPreferences {
    static let shared = UserPreferences()

    private enum Keys {
        static let onboardingCompleted = "onboardingCompleted"
        static let hapticsEnabled = "hapticsEnabled"
        static let autoSave = "autoSave"
        static let defaultAnnotationColor = "defaultAnnotationColor"
        static let defaultPenSize = "defaultPenSize"
        static let appearance = "appearance"
    }

    var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    var autoSave: Bool {
        didSet { UserDefaults.standard.set(autoSave, forKey: Keys.autoSave) }
    }

    var defaultAnnotationColorHex: String {
        didSet { UserDefaults.standard.set(defaultAnnotationColorHex, forKey: Keys.defaultAnnotationColor) }
    }

    var defaultPenSize: Double {
        didSet { UserDefaults.standard.set(defaultPenSize, forKey: Keys.defaultPenSize) }
    }

    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    private init() {
        let defaults = UserDefaults.standard
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        autoSave = defaults.object(forKey: Keys.autoSave) as? Bool ?? true
        defaultAnnotationColorHex = defaults.string(forKey: Keys.defaultAnnotationColor) ?? "FFD700"
        defaultPenSize = defaults.object(forKey: Keys.defaultPenSize) as? Double ?? 3.0
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
