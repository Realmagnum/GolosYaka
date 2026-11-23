import SwiftUI
import AppKit

// MARK: - Секция «ИИ-провайдер»

struct AIProviderSection: View {
    @ObservedObject var store = AIProviderStore.shared
    @ObservedObject var neuralDeepOAuth = NeuralDeepOAuthService.shared

    @State private var showingAddProviderSheet = false
    @State private var renamingPreset: AIProviderPreset? = nil
    @State private var renameText = ""

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 16) {
                Text("ИИ-ПРОВАЙДЕР")
                    .font(UIStyleFont.body(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.uiMidGray)

                Text(LocalizedStringKey("BYO-ключ. Транскрипция уходит напрямую в ваш OpenAI-совместимый сервис — ГолосЯка не выступает оператором данных."))
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Адаптивное размещение плашек в одну или несколько строк
                FlowLayout(spacing: 8) {
                    ForEach(store.allPresets) { preset in
                        PresetChip(
                            preset: preset,
                            isSelected: store.inspectedProviderID == preset.id,
                            isPrimary: store.isPrimary(preset.id),
                            isFailover: store.isFailover(preset.id),
                            onSelect: { store.inspect(preset) },
                            onRename: {
                                renamingPreset = preset
                                renameText = preset.name
                            },
                            onDelete: preset.isCustom ? {
                                store.deleteCustomPreset(id: preset.id)
                            } : nil
                        )
                    }

                    Button(action: { showingAddProviderSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Провайдер")
                                .font(UIStyleFont.body(size: 12, weight: .medium))
                        }
                        .foregroundColor(.uiInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.uiSidebar)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.uiHairline, lineWidth: 1))
                    }
                    .buttonStyle(TactileButtonStyle())
                }

                if let inspected = store.currentPreset {
                    if inspected.id != store.providerID, let primary = store.primaryPreset {
                        HStack(spacing: 8) {
                            Image(systemName: "eye")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.uiMidGray)
                            Text(L10n.format("Вы просматриваете «%@». Основной провайдер — «%@» и не меняется при просмотре.", inspected.name, primary.name))
                                .font(UIStyleFont.body(size: 11, weight: .regular))
                                .foregroundColor(.uiMidGray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(Color.uiSidebar)
                        .cornerRadius(10)
                    }

                    priorityCard(for: inspected)
                    providerDetails(for: inspected)
                }
            }
        }
        .sheet(isPresented: $showingAddProviderSheet) {
            AddCustomAIProviderSheet().withAppLocale()
        }
        .sheet(item: $renamingPreset) { preset in
            RenamePresetSheet(preset: preset).withAppLocale()
        }
    }

    // MARK: - Ручное назначение Primary / Failover

    private func priorityCard(for preset: AIProviderPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПРИОРИТЕТ ПРОВАЙДЕРА")
                .font(UIStyleFont.body(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.uiMidGray)

            Text("Роли назначаются только вручную. Переключение между провайдерами выше лишь открывает их настройки.")
                .font(UIStyleFont.body(size: 11, weight: .regular))
                .foregroundColor(.uiMidGray)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            roleToggle(
                title: "Основной (Primary)",
                subtitle: "Используется для всех ИИ-запросов. Основной провайдер обязателен.",
                icon: "star.fill",
                color: Color(hex: "#F59E0B"),
                isOn: store.isPrimary(preset.id),
                isEnabled: !store.isPrimary(preset.id)
            ) { enabled in
                if enabled { store.makePrimary(preset) }
            }

            roleToggle(
                title: "Резервный (Failover)",
                subtitle: "Автоматически подхватывает запросы при сбое основного провайдера.",
                icon: "shield.lefthalf.filled",
                color: Color(hex: "#3B82F6"),
                isOn: store.isFailover(preset.id),
                isEnabled: !store.isPrimary(preset.id)
            ) { enabled in
                store.setFailover(preset, enabled: enabled)
            }

            if store.isFailoverEnabled, let failover = store.failoverPreset {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#3B82F6"))
                    Text(L10n.format("Текущий резервный провайдер: %@", failover.name))
                        .font(UIStyleFont.body(size: 10, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
            }
        }
        .padding(12)
        .background(Color.uiSidebar.opacity(0.65))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.uiHairline, lineWidth: 1))
    }

    private func roleToggle(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        icon: String,
        color: Color,
        isOn: Bool,
        isEnabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(UIStyleFont.body(size: 12, weight: .semibold))
                    .foregroundColor(.uiInk)
                Text(subtitle)
                    .font(UIStyleFont.body(size: 10, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: color))
                .disabled(!isEnabled)
                .opacity(isOn ? 1 : (isEnabled ? 1 : 0.55))
        }
    }

    // MARK: - Настройки выбранного провайдера

    @ViewBuilder
    private func providerDetails(for preset: AIProviderPreset) -> some View {
        Text(L10n.format("Настройки: %@", preset.name))
            .font(UIStyleFont.body(size: 12, weight: .semibold))
            .foregroundColor(.uiInk)

        AIInputField(title: "Base URL", text: $store.baseURL, placeholder: "https://api.openai.com/v1")

        if store.baseURL.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://") || preset.id == "ollama" {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Разрешить HTTP (без шифрования)")
                        .font(UIStyleFont.body(size: 13, weight: .medium))
                        .foregroundColor(.uiInk)
                    Text("Для локального инференса, домашней сети и Tailscale")
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
                Spacer()
                Toggle("", isOn: $store.allowInsecureHTTP)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
            }
            .padding(.vertical, 2)
        }

        // Блок OAuth2 входа для Neuraldeep
        if preset.id == "neuraldeep" {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Авторизация Neuraldeep")
                        .font(UIStyleFont.body(size: 13, weight: .medium))
                        .foregroundColor(.uiInk)
                    Text(neuralDeepOAuth.authStatusMessage ?? (!store.apiKey.isEmpty ? "Аккаунт привязан, API-ключ сохранён" : "Быстрый вход через браузер с привязкой ключа"))
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
                Spacer()
                if neuralDeepOAuth.isAuthenticating {
                    ProgressView().controlSize(.small)
                    UIOutlineButton(title: "Отмена") {
                        neuralDeepOAuth.cancel()
                    }
                } else if !store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        if let url = URL(string: "https://hub.neuraldeep.ru/app/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Подключено")
                                .font(UIStyleFont.body(size: 13, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#10B981"))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(Color(hex: "#10B981").opacity(0.12))
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#10B981").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(TactileButtonStyle())
                    .help("Управление ключами и устройствами на hub.neuraldeep.ru")
                } else {
                    UIPrimaryButton(title: "Войти через браузер") {
                        neuralDeepOAuth.startBrowserLogin { result in
                            switch result {
                            case .success(let key):
                                store.apiKey = key
                                store.testConnection()
                            case .failure(let err):
                                store.testResultMessage = .formatted(key: "Ошибка входа: %@", arg: err.localizedDescription)
                                store.testOK = false
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.uiSidebar.opacity(0.5))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.uiHairline, lineWidth: 1))
        }

        AIInputField(title: "API-ключ", text: $store.apiKey, placeholder: "sk-…", isSecure: true)

        if preset.id == "ollama" {
            ollamaModelField
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("Модель"))
                    .font(UIStyleFont.body(size: 11, weight: .medium))
                    .foregroundColor(.uiMidGray)
                ModelFieldPicker(model: $store.model,
                                 models: $store.remoteModels,
                                 onLoad: { store.fetchRemoteModels() },
                                 isLoading: $store.isLoadingRemoteModels)
                if let error = store.modelsLoadError {
                    Text(error.localized)
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiEmber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        AIInputField(title: "Максимум токенов", text: $store.maxTokensString, placeholder: "4096")

        VStack(alignment: .leading, spacing: 4) {
            Text("Уровень ризонинга")
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            UIDropdownPicker(
                selection: $store.reasoningEffort,
                options: AIReasoningEffort.allCases.map {
                    UIDropdownOption($0.titleKey, value: $0)
                },
                fullWidth: true
            )
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Бюджет ризонинга")
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            UIDropdownPicker(
                selection: $store.thinkingBudgetMode,
                options: AIThinkingBudgetMode.allCases.map {
                    UIDropdownOption($0.titleKey, value: $0)
                },
                fullWidth: true
            )
            Text("Ограничивает токены на размышления для reasoning-моделей")
                .font(UIStyleFont.body(size: 11, weight: .regular))
                .foregroundColor(.uiMidGray)
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                UIOutlineButton(title: "Проверить") {
                    store.testConnection()
                }
                .disabled(store.isTesting)

                if store.isTesting {
                    ProgressView().controlSize(.small)
                    if !store.testPhase.statusKey.isEmpty {
                        Text(LocalizedStringKey(store.testPhase.statusKey))
                            .font(UIStyleFont.body(size: 11, weight: .regular))
                            .foregroundColor(.uiMidGray)
                    }
                }

                if let result = store.testResult {
                    Text(result)
                        .font(UIStyleFont.body(size: 12, weight: .medium))
                        .foregroundColor(store.testOK ? Color(hex: "#10B981") : .uiEmber)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if let ms = store.lastModelResponseMs {
                Text(L10n.format("Время ответа модели: %.1f с", Double(ms) / 1000))
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
            }
        }
    }

    private var ollamaModelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Модель")
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            HStack(spacing: 8) {
                UIDropdownPicker(selection: $store.model, options: {
                    var arr: [UIDropdownOption<String>] = []
                    if !store.model.isEmpty && !store.installedModels.contains(store.model) {
                        arr.append(.init(store.model, value: store.model))
                    }
                    arr.append(contentsOf: store.installedModels.map { .init($0, value: $0) })
                    return arr
                }(), fullWidth: true)

                Button(action: { store.refreshModels() }) {
                    if store.isLoadingModels {
                        ProgressView().controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.uiInk)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(TactileButtonStyle())
                .background(Color.uiPaper)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.uiHairline, lineWidth: 1))
                .help(LocalizedStringKey("Обновить список моделей"))
            }
            if store.installedModels.isEmpty && !store.isLoadingModels {
                Text("Нет скачанных моделей — запустите Ollama и нажмите ↻")
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if store.installedModels.isEmpty && !store.isLoadingModels {
                store.refreshModels()
            }
        }
    }
}

struct PresetChip: View {
    let preset: AIProviderPreset
    let isSelected: Bool
    var isPrimary: Bool = false
    var isFailover: Bool = false
    let onSelect: () -> Void
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                if isPrimary {
                    // Яркий статус основного провайдера
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#F59E0B"))
                        Text("Основной")
                            .font(UIStyleFont.body(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#F59E0B"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#F59E0B").opacity(0.18))
                    .cornerRadius(6)
                    .fixedSize(horizontal: true, vertical: false)
                } else if isFailover {
                    // Четкий статус резервного провайдера
                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "#3B82F6"))
                        Text("Резерв")
                            .font(UIStyleFont.body(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#3B82F6"))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#3B82F6").opacity(0.14))
                    .cornerRadius(6)
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    Circle()
                        .fill(Color.uiMidGray.opacity(0.5))
                        .frame(width: 6, height: 6)
                }

                Text(preset.name)
                    .font(UIStyleFont.body(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .uiPaper : .uiInk)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.uiInk : Color.uiPaper)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.uiInk : (isPrimary ? Color(hex: "#F59E0B") : (isFailover ? Color(hex: "#3B82F6") : Color.uiHairline)), lineWidth: (isPrimary || isFailover) && !isSelected ? 1.5 : 1))
        }
        .buttonStyle(TactileButtonStyle())
        .contextMenu {
            Button {
                onRename?()
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Адаптивный Flow Layout для переноса плашек по строкам

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxW && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(width: maxW, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

// MARK: - Модальное окно добавления кастомного LLM-провайдера

struct AddCustomAIProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AIProviderStore.shared

    @State private var name: String = ""
    @State private var baseURL: String = "https://api.openai.com/v1"
    @State private var model: String = ""
    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Новый ИИ-провайдер")
                .font(UIStyleFont.display(size: 15, weight: .bold))
                .foregroundColor(.uiInk)

            Text("Добавление произвольного OpenAI-совместимого сервиса (Ollama, vLLM, llama-swap, LiteLLM, OpenRouter и др.).")
                .font(UIStyleFont.body(size: 11, weight: .regular))
                .foregroundColor(.uiMidGray)

            VStack(alignment: .leading, spacing: 6) {
                Text("Название провайдера")
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiMidGray)
                TextField("например: vLLM Server или OpenRouter", text: $name)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.uiSidebar)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base URL")
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiMidGray)
                TextField("https://...", text: $baseURL)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.uiSidebar)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Модель")
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiMidGray)
                TextField("например: qwen2.5-coder:32b", text: $model)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.uiSidebar)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Ключ (опционально)")
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiMidGray)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.uiSidebar)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
            }

            HStack {
                Spacer()
                UIOutlineButton(title: "Отмена") { dismiss() }
                UIPrimaryButton(title: "Добавить") {
                    store.addCustomPreset(name: name, baseURL: baseURL, model: model, apiKey: apiKey)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 460)
        .background(Color.uiPaper)
    }
}

// MARK: - Модальное окно переименования инференса

struct RenamePresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AIProviderStore.shared
    let preset: AIProviderPreset
    @State private var name: String

    init(preset: AIProviderPreset) {
        self.preset = preset
        _name = State(initialValue: preset.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Переименовать инференс")
                .font(UIStyleFont.display(size: 15, weight: .bold))
                .foregroundColor(.uiInk)

            VStack(alignment: .leading, spacing: 6) {
                Text("Название для отображения")
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiMidGray)
                TextField("Название", text: $name)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.uiSidebar)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
            }

            HStack {
                Button("Сбросить") {
                    store.setPresetName("", for: preset.id)
                    dismiss()
                }
                .font(UIStyleFont.body(size: 12, weight: .regular))
                .foregroundColor(.uiMidGray)
                .buttonStyle(PlainButtonStyle())

                Spacer()
                UIOutlineButton(title: "Отмена") { dismiss() }
                UIPrimaryButton(title: "Сохранить") {
                    store.setPresetName(name, for: preset.id)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.uiPaper)
    }
}

struct AIInputField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(PlainTextFieldStyle())
            .font(UIStyleFont.body(size: 13, weight: .regular))
            .foregroundColor(.uiInk)
            .padding(8)
            .background(Color.uiCanvas)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
        }
    }
}
