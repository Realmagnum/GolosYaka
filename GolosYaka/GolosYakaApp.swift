import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
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
        WindowGroup {
            ContentView()
                .withAppLocale()
                .frame(minWidth: 990, minHeight: 710)
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
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Divider()
            
            Button(L10n.tr("Завершить")) { NSApplication.shared.terminate(nil) }
        }
    }
}
