import SwiftUI
import AVFoundation
import AppKit

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var isMicGranted: Bool = false
    @Published var isAccessibilityGranted: Bool = false
    @Published var didRequestAccessibility: Bool = UserDefaults.standard.bool(forKey: "didRequestAccessibility") {
        didSet {
            UserDefaults.standard.set(didRequestAccessibility, forKey: "didRequestAccessibility")
        }
    }
    
    // Показывает, что доступ запрашивался (или онбординг был пройден), но система не доверяет процессу
    // (типично при смене подписи/обновлении: тумблер в macOS включен, но привязан к старой версии)
    var isAccessibilityMismatch: Bool {
        return (didRequestAccessibility || onboardingCompleted) && !isAccessibilityGranted
    }
    
    @Published var onboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "onboardingCompleted") {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: "onboardingCompleted")
        }
    }
    
    var canContinue: Bool {
        return isMicGranted
    }
    
    init() {
        checkPermissions()
        if !isMicGranted {
            onboardingCompleted = false
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissions()
        }
    }
    
    func checkPermissions() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.isMicGranted = (micStatus == .authorized)
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }

    // Асинхронная проверка — не блокирует главный поток системным IPC
    // (AXIsProcessTrusted может дёргать TCC-демон). Для didBecomeActive и таймера.
    func refreshPermissions() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let ax = AXIsProcessTrusted()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMicGranted = mic
                self.isAccessibilityGranted = ax
            }
        }
    }
    
    func requestMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.isMicGranted = granted
                    self.checkPermissions()
                }
            }
        case .denied, .restricted:
            // macOS не показывает повторный запрос после отказа — ведём пользователя
            // напрямую в системный раздел «Микрофон».
            AppLogger.shared.warn("Permissions", "Доступ к микрофону запрещён", details: "Открываю системные настройки")
            openMicrophoneSettings()
        @unknown default:
            break
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func requestAccessibilityPermission() {
        didRequestAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func completeOnboarding() {
        DispatchQueue.main.async {
            self.onboardingCompleted = true
        }
    }
}

// MARK: - Безопасное приведение типов Accessibility API

enum AXValueCast {
    /// Accessibility API отдаёт `CFTypeRef`. Условное приведение к CF-типу (`as?`) в Swift
    /// считается всегда успешным и не компилируется, поэтому сначала проверяем `CFTypeID`,
    /// а затем переинтерпретируем значение — это единственный корректный способ без `as!`.
    static func element(_ ref: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }
}
