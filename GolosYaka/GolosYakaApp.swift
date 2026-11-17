import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Выводит главное окно на передний план.
    ///
    /// Три механизма подряд, потому что macOS 14+ отдаёт активацию фоновому
    /// приложению не всегда:
    /// 1. напрямую активируем приложение и поднимаем окно;
    /// 2. посылаем reopen через LaunchServices — ровно то событие, что приходит
    ///    при клике по иконке в Dock (он в этом приложении работает);
    /// 3. если активацию так и не выдали — на несколько секунд поднимаем окно
    ///    уровнем `.floating`, чтобы оно было видно, и возвращаем `.normal`,
    ///    как только приложение станет активным.
    @objc func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)

        let window = MainWindowRegistry.shared.window ?? fallbackWindow()
        AppLogger.shared.info(
            "App",
            "Reveal",
            details: "window=\(window != nil), visible=\(window?.isVisible ?? false), isActive=\(NSApp.isActive)"
        )

        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            if !window.isKeyWindow { window.makeKey() }
        }

        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) { NSApp.activate() }
        NSRunningApplication.current.activate(options: [.activateAllWindows])

        requestReopen()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.raiseIfStillInactive()
        }
    }

    /// Reopen-событие через LaunchServices: то же, что посылает Dock.
    private func requestReopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                AppLogger.shared.warn("App", "Reveal: reopen не доставлен", details: error.localizedDescription)
            }
        }
    }

    /// Последний рубеж: активацию не дали, но окно должно быть видно.
    private func raiseIfStillInactive() {
        guard !NSApp.isActive,
              let window = MainWindowRegistry.shared.window ?? fallbackWindow() else { return }
        AppLogger.shared.warn("App", "Reveal: активация не выдана, поднимаю окно поверх", details: "")
        window.level = .floating
        window.orderFrontRegardless()

        var observer: NSObjectProtocol?
        let restore = {
            window.level = .normal
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in restore() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { restore() }
    }

    /// Запасной поиск, если accessor ещё не зарегистрировал окно.
    private func fallbackWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { $0.canBecomeMain && !($0 is NSPanel) }
        return candidates.first(where: { $0.isVisible }) ?? candidates.first
    }

    /// Клик по иконке в Dock, повторный `open` и reopen-событие.
    /// Окно после закрытия крестиком создаёт SwiftUI по этому событию, поэтому
    /// здесь достаточно активировать приложение.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyStore.migrateAllIfNeeded()
        let mic = PermissionManager.shared.isMicGranted
        let ax = PermissionManager.shared.isAccessibilityGranted
        AppLogger.shared.info("App", "Запуск GolosYaka",
                              details: "версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"), микрофон: \(mic), доступ AX: \(ax)")
        let hotKey = NativeHotKeyManager.shared
        hotKey.onHotKeyPressed = {
            if hotKey.mode == .pushToTalk {
                if !AudioCapture.shared.isRecording {
                    AudioCapture.shared.startRecording()
                }
            } else {
                AudioCapture.shared.toggleRecording()
            }
        }
        hotKey.onHotKeyReleased = {
            if hotKey.mode == .pushToTalk, AudioCapture.shared.isRecording {
                AudioCapture.shared.stopRecording()
            }
        }
        hotKey.onSelectionHotKeyPressed = {
            AISelectionManager.shared.trigger()
        }
        hotKey.register()
    }
}

/// Явная точка входа вместо `@main` на `App`.
///
/// Свойства `App` инициализируются до его `init()`, а они читают `UserDefaults`
/// (AudioCapture, LanguageSettings). Поэтому миграция из старого домена должна
/// выполниться ещё до создания `GolosYakaApp`.
@main
enum GolosYakaLauncher {
    static func main() {
        LegacyMigration.runIfNeeded()
        GolosYakaApp.main()
    }
}

struct GolosYakaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var language = LanguageSettings.shared

    init() {
        KeyStore.preloadAllIfNeeded()
        LanguageSettings.shared.apply(notify: false)
    }
    
    var body: some Scene {
        // `Window` (а не WindowGroup) — ровно одно главное окно: openWindow не
        // плодит копии, а закрытое крестиком окно создаёт заново.
        Window(L10n.tr("ГолосЯка"), id: "main") {
            ContentView()
                .withAppLocale()
                .frame(minWidth: 990, minHeight: 710)
                .onAppear {
                    (NSApp.delegate as? AppDelegate)?.activateMainWindow()
                }
        }
        
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.tr("О программе")) {
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: NSNotification.Name("OpenAboutModal"), object: nil)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(L10n.tr("Открыть аудиофайл...")) {
                    AudioCapture.shared.importAndTranscribeFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button(L10n.tr("Найти в стенограмме…")) {
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleTranscriptSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(L10n.tr("Найти далее")) {
                    NotificationCenter.default.post(name: NSNotification.Name("FindNextInTranscript"), object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button(L10n.tr("Найти ранее")) {
                    NotificationCenter.default.post(name: NSNotification.Name("FindPreviousInTranscript"), object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        .defaultSize(width: 990, height: 710)
        
        MenuBarExtra(L10n.tr("ГолосЯка"), systemImage: "waveform") {
            MenuBarMenu()
        }
    }
}

/// Содержимое меню в статус-баре. Вынесено отдельной вьюхой, потому что здесь
/// нужен `openWindow`: он создаёт окно главной сцены, когда оно закрыто.
private struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var audioCapture = AudioCapture.shared

    var body: some View {
        Button(L10n.tr("Скопировать последнюю запись")) {
            if let last = audioCapture.history.first?.text {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last, forType: .string)
            }
        }
        .disabled(audioCapture.history.isEmpty)

        Divider()

        Button(L10n.tr("Транскрибировать аудиофайл...")) {
            AudioCapture.shared.importAndTranscribeFile()
        }

        Button(L10n.tr("Развернуть ГолосЯку")) {
            // openWindow создаёт окно, если оно закрыто; reopen внутри
            // activateMainWindow активирует приложение так же, как Dock.
            openWindow(id: "main")
            (NSApp.delegate as? AppDelegate)?.activateMainWindow()
        }

        Divider()

        Button(L10n.tr("Завершить")) { NSApplication.shared.terminate(nil) }
    }
}
