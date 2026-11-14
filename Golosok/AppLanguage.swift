import SwiftUI
import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case ru = "ru"
    case en = "en"
    var id: String { rawValue }
}

enum LocalizedMessage: Equatable {
    case key(String)
    case formatted(key: String, arg: String)
    case raw(String)

    var localized: String {
        switch self {
        case .key(let key):
            return L10n.tr(key)
        case .formatted(let key, let arg):
            return L10n.format(key, arg)
        case .raw(let text):
            return text
        }
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        LanguageSettings.shared.localizedString(forKey: key)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        let template = LanguageSettings.shared.localizedString(forKey: key)
        return String(format: template, locale: LanguageSettings.shared.currentLocale, arguments: args)
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("AppLanguageDidChange")
}

final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    @AppStorage("appLanguage") var rawLanguage: String = AppLanguage.system.rawValue

    @Published private(set) var effectiveCode: String = "ru"
    @Published private(set) var locale: Locale = Locale(identifier: "ru_RU")
    @Published private(set) var revision: Int = 0

    private let lock = NSLock()
    private var cachedCode: String = "ru"
    private var cachedLocale: Locale = Locale(identifier: "ru_RU")
    private var cachedBundle: Bundle = .main
    private var localeObserver: NSObjectProtocol?

    var current: AppLanguage {
        AppLanguage(rawValue: rawLanguage) ?? .system
    }

    var currentCode: String {
        lock.lock()
        defer { lock.unlock() }
        return cachedCode
    }

    var currentLocale: Locale {
        lock.lock()
        defer { lock.unlock() }
        return cachedLocale
    }

    var currentBundle: Bundle {
        lock.lock()
        defer { lock.unlock() }
        return cachedBundle
    }

    private init() {
        apply(notify: false)
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.current == .system else { return }
            self.apply(notify: true)
        }
    }

    deinit {
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }

    func localizedString(forKey key: String) -> String {
        let bundle = currentBundle
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func apply(notify: Bool = true) {
        let mode = current
        switch mode {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .ru:
            UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }

        let code = resolveEffectiveCode(for: mode)
        let newLocale = Locale(identifier: code == "ru" ? "ru_RU" : "en_US")
        let newBundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main

        lock.lock()
        let changed = (cachedCode != code || cachedLocale != newLocale)
        cachedCode = code
        cachedLocale = newLocale
        cachedBundle = newBundle
        lock.unlock()

        let publishUpdate = {
            if self.effectiveCode != code {
                self.effectiveCode = code
            }
            if self.locale != newLocale {
                self.locale = newLocale
            }
            if notify && changed {
                self.revision &+= 1
                NotificationCenter.default.post(name: .appLanguageDidChange, object: code)
            }
        }

        if Thread.isMainThread {
            publishUpdate()
        } else {
            DispatchQueue.main.async(execute: publishUpdate)
        }
    }

    func select(_ language: AppLanguage) {
        let performSelect = {
            guard self.current != language else { return }
            self.rawLanguage = language.rawValue
            self.apply(notify: true)
        }
        if Thread.isMainThread {
            performSelect()
        } else {
            DispatchQueue.main.async(execute: performSelect)
        }
    }

    private func resolveEffectiveCode(for mode: AppLanguage) -> String {
        switch mode {
        case .ru:
            return "ru"
        case .en:
            return "en"
        case .system:
            let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
            let preferred = (globalDomain?["AppleLanguages"] as? [String]) ?? Locale.preferredLanguages
            return Bundle.preferredLocalizations(from: ["en", "ru"], forPreferences: preferred).first ?? "en"
        }
    }
}

struct AppLocalizationModifier: ViewModifier {
    @ObservedObject private var language = LanguageSettings.shared

    func body(content: Content) -> some View {
        content
            .environment(\.locale, language.locale)
    }
}

extension View {
    func withAppLocale() -> some View {
        modifier(AppLocalizationModifier())
    }
}
