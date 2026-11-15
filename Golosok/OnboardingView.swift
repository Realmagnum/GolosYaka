import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions = PermissionManager.shared
    @Binding var isPresented: Bool
    
    var canContinue: Bool {
        return permissions.isMicGranted
    }
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // ШАПКА
                VStack(spacing: 8) {
                    Text("Давайте начнём")
                        .font(UIStyleFont.display(size: 22, weight: .semibold))
                        .foregroundColor(.uiInk)
                    
                    Text(LocalizedStringKey("Разрешите доступ к микрофону для записи речи.\nОстальные опции можно настроить позже."))
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                
                // КАРТОЧКА НАСТРОЕК
                UICard {
                    VStack(spacing: 18) {
                        // ШАГ 1: Микрофон (Обязательно)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isMicGranted ? Color(hex: "#10B981") : Color.uiWarn)
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Доступ к микрофону")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("Требуется")
                                        .font(UIStyleFont.body(size: 10, weight: .bold))
                                        .foregroundColor(.uiWarn)
                                }
                                Text("Запись голоса для распознавания моделью")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isMicGranted {
                                UIBadge(text: "Готово")
                            } else {
                                UIPrimaryButton(title: "Разрешить") {
                                    permissions.requestMicPermission()
                                }
                            }
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        // ШАГ 2: Авто-вставка (По желанию)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isAccessibilityGranted ? Color(hex: "#10B981") : (permissions.isAccessibilityMismatch ? Color.uiWarn : Color.uiMidGray.opacity(0.4)))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Вставка под курсор")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("Опционально")
                                        .font(UIStyleFont.body(size: 10, weight: .regular))
                                        .foregroundColor(.uiMidGray)
                                    if permissions.isAccessibilityMismatch {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.uiWarn)
                                            .font(.system(size: 12))
                                    }
                                }
                                Text(permissions.isAccessibilityMismatch ?
                                     LocalizedStringKey("macOS привязала доступ к старой подписи. Удалите Голосок кнопкой «–» в Настройках и добавьте снова.") :
                                     LocalizedStringKey("Мгновенная вставка распознанного текста в активное окно"))
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(permissions.isAccessibilityMismatch ? .uiWarn : .uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isAccessibilityGranted {
                                UIBadge(text: String(localized: "Готово"))
                            } else if permissions.isAccessibilityMismatch {
                                UIOutlineButton(title: "Передобавить") {
                                    permissions.requestAccessibilityPermission()
                                }
                            } else {
                                UIOutlineButton(title: "Включить") {
                                    permissions.requestAccessibilityPermission()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 480)
                
                UIPrimaryButton(title: canContinue ? LocalizedStringKey("Начать использование") : LocalizedStringKey("Требуется доступ к микрофону")) {
                    if canContinue {
                        permissions.completeOnboarding()
                        isPresented = false
                    }
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1.0 : 0.4)
            }
            .padding(40)
        }
        .onReceive(timer) { _ in
            permissions.refreshPermissions()
        }
    }
}
