import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Поднимает уже существующее окно. macOS 14+ игнорирует
    /// `activate(ignoringOtherApps:)` для фонового приложения, поэтому порядок
    /// важен: политика → окно → активация.
    func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) else { return }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
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
        // Явный id нужен, чтобы «Развернуть ГолосЯку» мог создать окно заново,
        // если пользователь закрыл его крестиком и остался только пункт в статус-баре.
        WindowGroup(id: "main") {
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
            openWindow(id: "main")
            // Окно создаётся асинхронно: активируем и сразу, и когда оно появится
            // (см. onAppear у WindowGroup).
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.activateMainWindow()
            }
        }

        Divider()

        Button(L10n.tr("Завершить")) { NSApplication.shared.terminate(nil) }
    }
}
