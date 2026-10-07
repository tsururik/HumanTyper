import AppKit
import TypingEngine

/// Ключи UserDefaults. Те же ключи используются в `@AppStorage` во вьюхах.
enum SettingsKey {
    static let wordsPerMinute = "wordsPerMinute"
    static let typoPercent = "typoPercent"
    static let naturalRhythm = "naturalRhythm"
    static let breaksEnabled = "breaksEnabled"
    static let breakEveryMin = "breakEveryMin"
    static let breakEveryMax = "breakEveryMax"
    static let breakForMin = "breakForMin"
    static let breakForMax = "breakForMax"
    static let theme = "theme"
    static let hideWindowOnStart = "hideWindowOnStart"
    static let autoResume = "autoResume"
    static let startHotkey = "startHotkey"
    static let pauseHotkey = "pauseHotkey"
    static let sourceText = "sourceText"
}

/// Значения по умолчанию — единый источник и для `@AppStorage`, и для `register(defaults:)`.
enum AppDefaults {
    static let wordsPerMinute = 60.0
    static let typoPercent = 3.0
    static let naturalRhythm = true
    static let breaksEnabled = true
    static let breakEveryMin = 30
    static let breakEveryMax = 120
    static let breakForMin = 3
    static let breakForMax = 15
    static let hideWindowOnStart = true
    static let autoResume = true

    static let wordsPerMinuteRange = TypingSettings.wordsPerMinuteRange
    static let typoPercentRange = 0.0...20.0
    static let breakEveryRange = 5...1800
    static let breakForRange = 1...300

    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            SettingsKey.wordsPerMinute: wordsPerMinute,
            SettingsKey.typoPercent: typoPercent,
            SettingsKey.naturalRhythm: naturalRhythm,
            SettingsKey.breaksEnabled: breaksEnabled,
            SettingsKey.breakEveryMin: breakEveryMin,
            SettingsKey.breakEveryMax: breakEveryMax,
            SettingsKey.breakForMin: breakForMin,
            SettingsKey.breakForMax: breakForMax,
            SettingsKey.theme: AppTheme.system.rawValue,
            SettingsKey.hideWindowOnStart: hideWindowOnStart,
            SettingsKey.autoResume: autoResume,
            SettingsKey.startHotkey: Hotkey.defaultStart.rawValue,
            SettingsKey.pauseHotkey: Hotkey.defaultPause.rawValue,
        ])
    }

    /// Текущие настройки набора из UserDefaults (значения приводятся к допустимым диапазонам).
    static func typingSettings(from defaults: UserDefaults = .standard) -> TypingSettings {
        let wpm = defaults.double(forKey: SettingsKey.wordsPerMinute)
        let typo = defaults.double(forKey: SettingsKey.typoPercent)
        return TypingSettings(
            wordsPerMinute: min(max(wpm, wordsPerMinuteRange.lowerBound), wordsPerMinuteRange.upperBound),
            typoRate: min(max(typo, typoPercentRange.lowerBound), typoPercentRange.upperBound) / 100,
            naturalRhythm: defaults.bool(forKey: SettingsKey.naturalRhythm),
            breaksEnabled: defaults.bool(forKey: SettingsKey.breaksEnabled),
            breakInterval: .ordered(
                TimeInterval(defaults.integer(forKey: SettingsKey.breakEveryMin)),
                TimeInterval(defaults.integer(forKey: SettingsKey.breakEveryMax))
            ),
            breakDuration: .ordered(
                TimeInterval(defaults.integer(forKey: SettingsKey.breakForMin)),
                TimeInterval(defaults.integer(forKey: SettingsKey.breakForMax))
            )
        )
    }

    static func hotkey(_ key: String, fallback: Hotkey, in defaults: UserDefaults = .standard) -> Hotkey {
        defaults.string(forKey: key).flatMap(Hotkey.init(rawValue:)) ?? fallback
    }
}

/// Тема оформления.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: SettingsKey.theme) ?? "") ?? .system
    }

    /// Применяется ко всему приложению, включая меню в строке меню.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
