import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var revealAttempts = 0

    /// Поднимает окно поверх всех приложений.
    ///
    /// macOS 14+ не отдаёт фоновому приложению активацию одним вызовом, а
    /// `makeKeyAndOrderFront` уважает это решение. Поэтому: снимаем hide, просим
    /// активацию, поднимаем окно главной сцены `orderFrontRegardless()` и повторяем
    /// до ~1.2 с — окно создаётся через несколько циклов run loop после клика.
    /// Если активацию так и не дали, посылаем reopen — то же событие, что при
    /// клике по иконке в Dock, и оно гарантированно выводит окно вперёд.
    @objc func activateMainWindow() {
        revealAttempts = 0
        revealStep()
    }

    private func revealStep() {
        revealAttempts += 1

        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])

        if let window = MainWindowRegistry.shared.window ?? fallbackWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            if !window.isKeyWindow { window.makeKey() }
        }

        let isReady = NSApp.isActive && (MainWindowRegistry.shared.window?.isKeyWindow ?? false)
        if isReady {
            revealAttempts = 0
            return
        }

        guard revealAttempts < 15 else {
            revealAttempts = 0
            requestReopen()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.revealStep()
        }
    }

    /// Reopen-событие через LaunchServices: ровно то, что делает клик по иконке в
    /// Dock. Нужен как последний рубеж, когда система не отдала активацию.
    private func requestReopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                AppLogger.shared.warn("App", "Не удалось вывести окно вперёд", details: error.localizedDescription)
            }
        }
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
            let delegate = NSApp.delegate as? AppDelegate
            // Активация должна запрашиваться синхронно в обработчике клика:
            // позже macOS уже не считает её инициированной пользователем.
            delegate?.activateMainWindow()
            openWindow(id: "main")
            // Окно создаётся следующим циклом run loop — поднимаем его, когда появится
            // (плюс страховка на случай, если onAppear отработает раньше window server).
            DispatchQueue.main.async {
                delegate?.activateMainWindow()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                delegate?.activateMainWindow()
            }
        }

        Divider()

        Button(L10n.tr("Завершить")) { NSApplication.shared.terminate(nil) }
    }
}
