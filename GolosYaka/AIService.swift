import Foundation
import SwiftUI

struct AIChatMessage: Codable {
    let role: String
    let content: String
}

struct AIProviderPreset: Identifiable, Codable {
    let id: String
    var name: String
    var hint: String
    var baseURL: String
    var defaultModel: String
    var needsKey: Bool
    var isCustom: Bool = false
}

enum AIProviderPresets {
    static let builtin: [AIProviderPreset] = [
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            hint: "gpt-4o-mini, gpt-4o",
            baseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            needsKey: true
        ),
        AIProviderPreset(
            id: "neuraldeep",
            name: "Neuraldeep (NP)",
            hint: "neuraldeep.ru — API & OAuth2",
            baseURL: "https://api.neuraldeep.ru/v1",
            defaultModel: "qwen3.6-fp8-noreason",
            needsKey: true
        ),
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            hint: "deepseek-flash, deepseek-v4-pro",
            baseURL: "https://api.deepseek.com",
            defaultModel: "deepseek-flash",
            needsKey: true
        ),
        AIProviderPreset(
            id: "groq",
            name: "Groq",
            hint: "llama-3.3-70b-versatile",
            baseURL: "https://api.groq.com/openai/v1",
            defaultModel: "llama-3.3-70b-versatile",
            needsKey: true
        ),
        AIProviderPreset(
            id: "ollama",
            name: "Local AI",
            hint: "LM Studio / Ollama / Local",
            baseURL: "http://localhost:11434/v1",
            defaultModel: "gemma3:1b",
            needsKey: false
        )
    ]

    static var all: [AIProviderPreset] {
        AIProviderStore.shared.allPresets
    }

    static func preset(id: String) -> AIProviderPreset? {
        builtin.first { $0.id == id } ?? all.first { $0.id == id }
    }
}

enum AIReasoningEffort: String, CaseIterable, Identifiable {
    case off = "off"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Выкл (не передавать)"
        case .low: return "Low (минимальный)"
        case .medium: return "Medium (средний)"
        case .high: return "High (глубокий)"
        }
    }
}

enum AIThinkingBudgetMode: String, CaseIterable, Identifiable {
    case off = "off"
    case fixed1024 = "fixed1024"
    case proportional = "proportional"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Выкл (как сейчас)"
        case .fixed1024: return "Фиксированный (1024 токена)"
        case .proportional: return "Текст × 2 токена"
        }
    }
}

struct AIProviderConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let reasoningEffort: AIReasoningEffort
    let thinkingBudgetMode: AIThinkingBudgetMode
    let maxTokens: Int
}

final class AICancelableRequest {
    private let lock = NSLock()
    private var currentTask: URLSessionDataTask?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func bind(_ task: URLSessionDataTask?) {
        lock.lock()
        if cancelled {
            lock.unlock()
            task?.cancel()
            return
        }
        currentTask = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = currentTask
        currentTask = nil
        lock.unlock()
        task?.cancel()
    }
}

enum AIError: LocalizedError {
    case notConfigured
    case invalidURL
    case network(String)
    case http(Int, String)
    case emptyResponse
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.tr("ИИ-провайдер не настроен")
        case .invalidURL:
            return L10n.tr("Некорректный baseURL")
        case .network(let message):
            return L10n.tr("Сетевая ошибка") + ": \(message)"
        case .http(let code, let message):
            return L10n.tr("Ошибка сервера") + " \(code): \(message)"
        case .emptyResponse:
            return L10n.tr("Модель вернула пустой ответ")
        case .parse(let message):
            return L10n.tr("Не удалось разобрать ответ") + ": \(message)"
        }
    }
}

/// Один этап проверки провайдера. Данные, а не готовая строка: UI сам решает,
/// что показать пользователю, а логи получают полную техническую причину.
struct AIProviderCheckStage: Equatable {
    enum Kind: String { case models, chat }

    let kind: Kind
    let ok: Bool
    let elapsedMs: Int
    let detail: String
    var modelIDs: [String] = []

    var technicalSummary: String {
        "\(kind.rawValue): \(ok ? "ok" : "fail") \(elapsedMs) мс — \(detail)"
    }
}

struct AIProviderCheck: Equatable {
    let baseURL: String
    let model: String
    let stages: [AIProviderCheckStage]

    var modelsStage: AIProviderCheckStage? { stages.first { $0.kind == .models } }
    var chatStage: AIProviderCheckStage? { stages.first { $0.kind == .chat } }

    /// Годен ли провайдер для реальной работы: /models может отсутствовать,
    /// а вот /chat/completions с выбранной моделью обязателен.
    var isUsable: Bool { chatStage?.ok == true }

    var technicalSummary: String {
        stages.map(\.technicalSummary).joined(separator: " | ")
    }
}

enum AIConnectionTestPhase: Equatable {
    case idle, models, chat, finished

    var statusKey: String {
        switch self {
        case .idle: return ""
        case .models: return "Проверка списка моделей…"
        case .chat: return "Проверка генерации…"
        case .finished: return ""
        }
    }
}

final class AIProviderStore: ObservableObject {
    static let shared = AIProviderStore()

    /// Провайдер, который реально используется для ИИ-запросов.
    /// Назначается только вручную и не меняется при просмотре настроек других провайдеров.
    @Published private(set) var providerID: String {
        didSet {
            Self.defaults.set(providerID, forKey: "ai.primaryProviderID")
            Self.defaults.set(providerID, forKey: "ai.providerID")
        }
    }

    /// Провайдер, открытый в настройках для просмотра и редактирования.
    /// Это состояние UI: оно не влияет на выбор основного провайдера.
    @Published var inspectedProviderID: String {
        didSet { Self.defaults.set(inspectedProviderID, forKey: "ai.inspectedProviderID") }
    }

    @Published var isFailoverEnabled: Bool { didSet { Self.defaults.set(isFailoverEnabled, forKey: "ai.failover.enabled") } }
    @Published var failoverProviderID: String { didSet { Self.defaults.set(failoverProviderID, forKey: "ai.failover.providerID") } }

    @Published var baseURL: String {
        didSet {
            Self.defaults.set(baseURL, forKey: "ai.provider.\(inspectedProviderID).baseURL")
            if inspectedProviderID == providerID {
                Self.defaults.set(baseURL, forKey: "ai.baseURL")
            }
        }
    }
    @Published var model: String {
        didSet {
            Self.defaults.set(model, forKey: "ai.provider.\(inspectedProviderID).model")
            if inspectedProviderID == providerID {
                Self.defaults.set(model, forKey: "ai.model")
            }
        }
    }
    @Published var apiKey: String {
        didSet {
            if apiKey != oldValue {
                KeyStore.set(apiKey, for: "ai.provider.\(inspectedProviderID).apiKey")
            }
        }
    }
    @Published var allowInsecureHTTP: Bool { didSet { Self.defaults.set(allowInsecureHTTP, forKey: "ai.allowInsecureHTTP") } }
    @Published var reasoningEffort: AIReasoningEffort { didSet { Self.defaults.set(reasoningEffort.rawValue, forKey: "ai.reasoningEffort") } }
    @Published var thinkingBudgetMode: AIThinkingBudgetMode { didSet { Self.defaults.set(thinkingBudgetMode.rawValue, forKey: "ai.thinkingBudgetMode") } }
    @Published var maxTokensString: String { didSet { Self.defaults.set(maxTokensString, forKey: "ai.maxTokens") } }

    var maxTokens: Int {
        if let val = Int(maxTokensString.trimmingCharacters(in: .whitespaces)), val > 0 {
            return val
        }
        return 4096
    }

    private static func sortedModels(_ names: [String]) -> [String] {
        names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// true, пока текущий ИИ-запрос обслуживается резервным провайдером.
    /// Используется плавающим виджетом, чтобы показать это пользователю.
    @Published var isUsingFailover = false
    @Published var lastFailoverReason: String?

    @Published var isTesting = false
    @Published var testPhase: AIConnectionTestPhase = .idle
    @Published var testResultMessage: LocalizedMessage?
    var testResult: String? { testResultMessage?.localized }
    /// Время ответа модели на последней проверке (мс), из stage chat-completions.
    @Published var lastModelResponseMs: Int?
    @Published var testOK = false
    @Published var installedModels: [String] = []
    @Published var isLoadingModels = false
    /// Модели, полученные из /models текущего провайдера (не локальные Ollama).
    @Published var remoteModels: [String] = []
    @Published var isLoadingRemoteModels = false
    @Published var modelsLoadError: LocalizedMessage?
    @Published var customPresets: [AIProviderPreset] = []
    @Published var customDisplayNames: [String: String] = [:]

    var allPresets: [AIProviderPreset] {
        (AIProviderPresets.builtin + customPresets).map { preset in
            var p = preset
            if let customName = customDisplayNames[preset.id], !customName.isEmpty {
                p.name = customName
            }
            return p
        }
    }

    private static let defaults = UserDefaults.standard

    private var customPresetsFileURL: URL? {
        AppPaths.applicationSupportDirectory?.appendingPathComponent("custom_ai_providers.json")
    }

    private init() {
        var names: [String: String] = [:]
        if let savedNames = Self.defaults.dictionary(forKey: "ai.provider.custom_names") as? [String: String] {
            names = savedNames
        }
        self.customDisplayNames = names

        // Загрузка кастомных провайдеров
        var loadedCustom: [AIProviderPreset] = []
        if let dir = AppPaths.applicationSupportDirectory {
            let fileURL = dir.appendingPathComponent("custom_ai_providers.json")
            if let data = try? Data(contentsOf: fileURL),
               let list = try? JSONDecoder().decode([AIProviderPreset].self, from: data) {
                loadedCustom = list
            }
        }
        self.customPresets = loadedCustom

        // Миграция: один и тот же сохранённый ID раньше был и активным, и просматриваемым.
        let savedPrimaryID = Self.defaults.string(forKey: "ai.primaryProviderID")
            ?? Self.defaults.string(forKey: "ai.providerID")
            ?? ""
        let savedInspectedID = Self.defaults.string(forKey: "ai.inspectedProviderID") ?? savedPrimaryID

        func resolve(_ id: String) -> AIProviderPreset? {
            loadedCustom.first(where: { $0.id == id })
                ?? AIProviderPresets.builtin.first(where: { $0.id == id })
        }

        let primaryPreset = resolve(savedPrimaryID) ?? AIProviderPresets.builtin[0]
        let inspectedPreset = resolve(savedInspectedID) ?? primaryPreset
        // Глобальные ai.baseURL / ai.model / ai.apiKey читаем только один раз — при первом запуске
        // после обновления. Дальше источником правды остаются профили провайдеров.
        let needsLegacyMigration = Self.defaults.string(forKey: "ai.primaryProviderID") == nil
        let legacyID: String? = needsLegacyMigration ? (savedPrimaryID.isEmpty ? primaryPreset.id : savedPrimaryID) : nil

        self.providerID = primaryPreset.id
        self.inspectedProviderID = inspectedPreset.id
        self.isFailoverEnabled = Self.defaults.object(forKey: "ai.failover.enabled") as? Bool ?? false
        self.failoverProviderID = Self.defaults.string(forKey: "ai.failover.providerID") ?? "ollama"

        // Однократная миграция старых глобальных настроек в изолированный профиль основного провайдера.
        let primaryBaseURL = Self.savedBaseURL(for: primaryPreset, legacyID: legacyID)
        let primaryModel = Self.savedModel(for: primaryPreset, legacyID: legacyID)
        let primaryAPIKey = Self.savedAPIKey(for: primaryPreset, legacyID: legacyID)
        if Self.defaults.string(forKey: "ai.provider.\(primaryPreset.id).baseURL") == nil {
            Self.defaults.set(primaryBaseURL, forKey: "ai.provider.\(primaryPreset.id).baseURL")
        }
        if Self.defaults.string(forKey: "ai.provider.\(primaryPreset.id).model") == nil {
            Self.defaults.set(primaryModel, forKey: "ai.provider.\(primaryPreset.id).model")
        }
        if (KeyStore.get("ai.provider.\(primaryPreset.id).apiKey") ?? "").isEmpty, !primaryAPIKey.isEmpty {
            KeyStore.set(primaryAPIKey, for: "ai.provider.\(primaryPreset.id).apiKey")
        }

        self.baseURL = Self.savedBaseURL(for: inspectedPreset, legacyID: nil)
        self.model = Self.savedModel(for: inspectedPreset, legacyID: nil)
        self.apiKey = Self.savedAPIKey(for: inspectedPreset, legacyID: nil)
        self.allowInsecureHTTP = Self.defaults.object(forKey: "ai.allowInsecureHTTP") as? Bool ?? true

        if let rawEffort = Self.defaults.string(forKey: "ai.reasoningEffort"),
           let effort = AIReasoningEffort(rawValue: rawEffort) {
            self.reasoningEffort = effort
        } else {
            self.reasoningEffort = .low
        }

        if let rawBudget = Self.defaults.string(forKey: "ai.thinkingBudgetMode"),
           let budget = AIThinkingBudgetMode(rawValue: rawBudget) {
            self.thinkingBudgetMode = budget
        } else {
            self.thinkingBudgetMode = .fixed1024
        }

        self.maxTokensString = Self.defaults.string(forKey: "ai.maxTokens") ?? "4096"

        // Фиксируем нормализованные роли, чтобы миграция старых глобальных ключей выполнилась один раз.
        Self.defaults.set(self.providerID, forKey: "ai.primaryProviderID")
        Self.defaults.set(self.inspectedProviderID, forKey: "ai.inspectedProviderID")
    }

    // MARK: - Разрешение сохранённых настроек провайдера

    private static func savedBaseURL(for preset: AIProviderPreset, legacyID: String?) -> String {
        if let value = defaults.string(forKey: "ai.provider.\(preset.id).baseURL"), !value.isEmpty {
            return value
        }
        if preset.id == legacyID, let legacy = defaults.string(forKey: "ai.baseURL"), !legacy.isEmpty {
            return legacy
        }
        return preset.baseURL
    }

    private static func savedModel(for preset: AIProviderPreset, legacyID: String?) -> String {
        var value = defaults.string(forKey: "ai.provider.\(preset.id).model")
            ?? (preset.id == legacyID ? defaults.string(forKey: "ai.model") : nil)
            ?? preset.defaultModel
        // Пустое значение — единственный случай, когда подставляем дефолт пресета.
        // Осознанный выбор пользователя (включая устаревшие id вроде deepseek-chat) не перезаписываем.
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = preset.defaultModel
        }
        // Единственное исключение: retired id модели Neuraldeep, который больше не существует в API.
        if preset.id == "neuraldeep" && value == "neuraldeep/qwen3.8-27b" {
            value = "qwen3.6-fp8-noreason"
        }
        return value
    }

    private static func savedAPIKey(for preset: AIProviderPreset, legacyID: String?) -> String {
        if let key = KeyStore.get("ai.provider.\(preset.id).apiKey"), !key.isEmpty {
            return key
        }
        if preset.id == legacyID, let key = KeyStore.get("ai.apiKey"), !key.isEmpty {
            return key
        }
        return ""
    }

    private func providerConfig(for presetID: String) -> AIProviderConfig {
        let preset = allPresets.first(where: { $0.id == presetID }) ?? AIProviderPresets.builtin[0]
        return AIProviderConfig(
            baseURL: Self.savedBaseURL(for: preset, legacyID: nil),
            apiKey: Self.savedAPIKey(for: preset, legacyID: nil),
            model: Self.savedModel(for: preset, legacyID: nil),
            reasoningEffort: reasoningEffort,
            thinkingBudgetMode: thinkingBudgetMode,
            maxTokens: maxTokens
        )
    }

    /// Конфигурация основного (Primary) провайдера, которая используется всеми ИИ-запросами.
    var config: AIProviderConfig {
        providerConfig(for: providerID)
    }

    /// Черновая конфигурация провайдера, открытого в настройках.
    /// Применяется только для кнопок «Проверить» и обновления списка моделей.
    var draftConfig: AIProviderConfig {
        AIProviderConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            reasoningEffort: reasoningEffort,
            thinkingBudgetMode: thinkingBudgetMode,
            maxTokens: maxTokens
        )
    }

    /// Конфигурация для резервного провайдера (Failover)
    var failoverConfig: AIProviderConfig? {
        guard isFailoverEnabled, !failoverProviderID.isEmpty, failoverProviderID != providerID else { return nil }
        guard let preset = failoverPreset else { return nil }
        let cfg = providerConfig(for: preset.id)
        guard !cfg.baseURL.trimmingCharacters(in: .whitespaces).isEmpty,
              !cfg.model.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return cfg
    }

    var isConfigured: Bool {
        let cfg = config
        return !cfg.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !cfg.model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Ручное назначение ролей

    var primaryPreset: AIProviderPreset? {
        allPresets.first { $0.id == providerID }
    }

    var currentPreset: AIProviderPreset? {
        allPresets.first { $0.id == inspectedProviderID }
    }

    var failoverPreset: AIProviderPreset? {
        allPresets.first { $0.id == failoverProviderID }
    }

    func isPrimary(_ presetID: String) -> Bool {
        providerID == presetID
    }

    func isFailover(_ presetID: String) -> Bool {
        isFailoverEnabled && failoverProviderID == presetID && failoverProviderID != providerID
    }

    /// Открыть провайдера для просмотра/редактирования, не меняя основной.
    func inspect(_ preset: AIProviderPreset) {
        inspectedProviderID = preset.id
        loadInspectedSettings()
        resetTestState()
        if preset.id == "ollama" {
            refreshModels()
        }
        AppLogger.shared.info("AI", "Открыт провайдер \(preset.name)", details: preset.baseURL)
    }

    /// Явно назначить провайдера основным (Primary).
    func makePrimary(_ preset: AIProviderPreset) {
        guard providerID != preset.id else { return }
        providerID = preset.id
        if failoverProviderID == preset.id {
            isFailoverEnabled = false
        }
        if inspectedProviderID != preset.id {
            inspect(preset)
        }
        testResultMessage = nil
        testOK = false
        AppLogger.shared.info("AI", "Основной провайдер назначен вручную", details: "\(preset.name) (\(preset.id))")
    }

    /// Явно включить или выключить резервного провайдера (Failover).
    func setFailover(_ preset: AIProviderPreset, enabled: Bool) {
        guard preset.id != providerID else { return }
        if enabled {
            failoverProviderID = preset.id
            isFailoverEnabled = true
            AppLogger.shared.info("AI", "Резервный провайдер назначен вручную", details: "\(preset.name) (\(preset.id))")
        } else if failoverProviderID == preset.id {
            isFailoverEnabled = false
            AppLogger.shared.info("AI", "Резервный провайдер отключён вручную", details: preset.id)
        }
    }

    private func loadInspectedSettings() {
        guard let preset = currentPreset else { return }
        baseURL = Self.savedBaseURL(for: preset, legacyID: nil)
        model = Self.savedModel(for: preset, legacyID: nil)
        apiKey = Self.savedAPIKey(for: preset, legacyID: nil)
    }

    private func resetTestState() {
        testResultMessage = nil
        testOK = false
        installedModels = []
    }

    // MARK: - Управление кастомными провайдерами

    func setPresetName(_ newName: String, for presetId: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            customDisplayNames.removeValue(forKey: presetId)
        } else {
            customDisplayNames[presetId] = clean
        }
        Self.defaults.set(customDisplayNames, forKey: "ai.provider.custom_names")
        objectWillChange.send()
    }

    func addCustomPreset(name: String, baseURL: String, model: String, apiKey: String?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanURL.isEmpty else { return }

        let id = "custom_" + UUID().uuidString.prefix(8)
        let preset = AIProviderPreset(
            id: id,
            name: cleanName,
            hint: cleanURL,
            baseURL: cleanURL,
            defaultModel: cleanModel.isEmpty ? "default" : cleanModel,
            needsKey: false,
            isCustom: true
        )
        customPresets.append(preset)
        persistCustomPresets()

        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            KeyStore.set(key, for: "ai.provider.\(id).apiKey")
        }

        // Добавление провайдера не делает его основным: приоритет назначается вручную.
        inspect(preset)
    }

    func deleteCustomPreset(id: String) {
        let wasPrimary = providerID == id
        let wasFailover = failoverProviderID == id

        customPresets.removeAll { $0.id == id }
        customDisplayNames.removeValue(forKey: id)
        Self.defaults.set(customDisplayNames, forKey: "ai.provider.custom_names")
        persistCustomPresets()
        KeyStore.delete("ai.provider.\(id).apiKey")

        if wasFailover {
            isFailoverEnabled = false
        }
        if wasPrimary, let fallback = AIProviderPresets.builtin.first {
            providerID = fallback.id
        }
        // Если удалён просматриваемый провайдер (или текущий просмотр стал невалидным),
        // переключаем просмотр на основной. Приоритет при этом не меняется.
        if currentPreset == nil, let primary = primaryPreset {
            inspect(primary)
        } else {
            objectWillChange.send()
        }
    }

    private func persistCustomPresets() {
        guard let url = customPresetsFileURL,
              let data = try? JSONEncoder().encode(customPresets) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func refreshModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        installedModels = []
        AIService.shared.listModels(using: draftConfig) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingModels = false
                switch result {
                case .success(let models):
                    self.installedModels = Self.sortedModels(models)
                case .failure:
                    self.installedModels = []
                }
            }
        }
    }

    func testConnection() {
        let cleanURL = baseURL.trimmingCharacters(in: .whitespaces)
        let cleanModel = model.trimmingCharacters(in: .whitespaces)

        if cleanURL.isEmpty {
            testOK = false
            testPhase = .finished
            testResultMessage = .key("Заполните Base URL")
            return
        }
        if cleanModel.isEmpty {
            testOK = false
            testPhase = .finished
            testResultMessage = .key("Укажите модель")
            return
        }

        let trimmedURL = cleanURL.lowercased()
        if trimmedURL.hasPrefix("http://") && !allowInsecureHTTP {
            testOK = false
            testPhase = .finished
            testResultMessage = .key("HTTP запрещён. Включите разрешение HTTP или используйте HTTPS.")
            return
        }

        isTesting = true
        testPhase = .models
        testResultMessage = nil
        lastModelResponseMs = nil
        testOK = false
        let checkedConfig = draftConfig
        AIService.shared.checkProvider(using: checkedConfig) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTesting = false
                self.testPhase = .finished
                switch result {
                case .success(let check):
                    self.lastModelResponseMs = check.chatStage?.elapsedMs
                    if let models = check.modelsStage, models.ok {
                        self.remoteModels = Self.sortedModels(models.modelIDs)
                    }
                    if check.isUsable {
                        self.testOK = true
                        AIService.shared.clearProviderFailure(checkedConfig)
                        if let models = check.modelsStage, !models.ok {
                            self.testResultMessage = .formatted(key: "Подключено, но список моделей недоступен: %@", arg: models.detail)
                            AppLogger.shared.warn("AI", "Проверка: чат работает, /models недоступен", details: check.technicalSummary)
                        } else {
                            self.testResultMessage = .key("Подключено")
                            AppLogger.shared.info("AI", "Проверка провайдера успешна", details: check.technicalSummary)
                        }
                    } else {
                        self.testOK = false
                        let reason = check.chatStage?.detail ?? L10n.tr("Нет ответа от сервера")
                        self.testResultMessage = .formatted(key: "Проверка не пройдена: %@", arg: reason)
                        AppLogger.shared.error("AI", "Проверка провайдера выявила сбой чата", details: check.technicalSummary)
                    }
                case .failure(let error):
                    self.testOK = false
                    self.testResultMessage = .formatted(key: "Проверка не пройдена: %@", arg: error.localizedDescription)
                    AppLogger.shared.error("AI", "Проверка провайдера не выполнена", details: error.localizedDescription)
                }
            }
        }
    }

    /// Загрузить список моделей с /models текущего провайдера. Ошибка показывает точную
    /// причину (.HTTP-код / текст сервера / тайм-аут), а не пустой список.
    func fetchRemoteModels() {
        guard !isLoadingRemoteModels else { return }
        let cleanURL = baseURL.trimmingCharacters(in: .whitespaces)
        if cleanURL.isEmpty {
            modelsLoadError = .key("Заполните Base URL")
            return
        }
        isLoadingRemoteModels = true
        modelsLoadError = nil
        let checkedConfig = draftConfig
        AIService.shared.listModels(using: checkedConfig) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingRemoteModels = false
                switch result {
                case .success(let names):
                    self.remoteModels = Self.sortedModels(names)
                    if names.isEmpty {
                        self.modelsLoadError = .key("Сервер вернул пустой список моделей")
                        AppLogger.shared.warn("AI", "Список моделей пуст", details: "\(checkedConfig.baseURL) / \(checkedConfig.model)")
                    } else {
                        AppLogger.shared.info("AI", "Список моделей загружен", details: "\(checkedConfig.baseURL), моделей: \(names.count)")
                    }
                case .failure(let error):
                    self.remoteModels = []
                    self.modelsLoadError = .formatted(key: "Не удалось загрузить модели: %@", arg: error.localizedDescription)
                    AppLogger.shared.error("AI", "Загрузка списка моделей не удалась", details: error.localizedDescription)
                }
            }
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let session: URLSession

    /// Память о недавно упавших провайдерах. Без неё каждый запрос к мёртвому
    /// основному платит полный тайм-аут, и только потом уходит в failover.
    private static let failureCooldown: TimeInterval = 5 * 60
    private let healthLock = NSLock()
    private var providerFailures: [String: (until: Date, reason: String)] = [:]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    private func healthKey(_ config: AIProviderConfig) -> String {
        "\(config.baseURL)|\(config.model)"
    }

    private func activeFailure(for config: AIProviderConfig) -> (until: Date, reason: String)? {
        healthLock.lock()
        defer { healthLock.unlock() }
        guard let failure = providerFailures[healthKey(config)], failure.until > Date() else { return nil }
        return failure
    }

    private func markFailed(_ config: AIProviderConfig, reason: String) {
        healthLock.lock()
        providerFailures[healthKey(config)] = (Date().addingTimeInterval(Self.failureCooldown), reason)
        healthLock.unlock()
    }

    func clearProviderFailure(_ config: AIProviderConfig) {
        healthLock.lock()
        providerFailures.removeValue(forKey: healthKey(config))
        healthLock.unlock()
    }

    /// Состояние «сейчас работает резерв» читает плавающий виджет.
    private func setFailoverInUse(_ value: Bool, reason: String? = nil) {
        DispatchQueue.main.async {
            let store = AIProviderStore.shared
            store.isUsingFailover = value
            if let reason { store.lastFailoverReason = reason }
        }
    }

    private static func elapsedMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private func buildUniversalPayload(
        messages: [AIChatMessage],
        config: AIProviderConfig,
        promptLength: Int?,
        stream: Bool,
        isFallback: Bool
    ) -> (data: Data?, debugDesc: String) {
        let userMaxTokens = config.maxTokens > 0 ? config.maxTokens : 4096
        let chars = promptLength ?? messages.reduce(0) { $0 + $1.content.count }
        let approxPromptTokens = max(64, chars / 4)
        let minTokensForOutput = approxPromptTokens + 512

        var payload: [String: Any] = [:]
        if !config.model.isEmpty {
            payload["model"] = config.model
        }

        let encodedMessages: [[String: String]] = messages.map { ["role": $0.role, "content": $0.content] }
        payload["messages"] = encodedMessages
        if stream {
            payload["stream"] = true
        }

        let modelLower = config.model.lowercased()
        let baseURLLower = config.baseURL.lowercased()
        let isOpenAI = baseURLLower.contains("api.openai.com")
        let isOpenAI_O_Series = isOpenAI && (modelLower.hasPrefix("o1") || modelLower.hasPrefix("o3") || modelLower.contains("-o1-") || modelLower.contains("-o3-"))
        let isDeepSeek = baseURLLower.contains("deepseek.com") || modelLower.contains("deepseek")
        let isNeuralDeep = baseURLLower.contains("neuraldeep")
        let isQwen = isNeuralDeep || modelLower.contains("qwen")
        let isOpenRouter = baseURLLower.contains("openrouter.ai")

        // 1. Fallback режим: чистый совместимый стандарт OpenAI
        if isFallback {
            payload["temperature"] = 0.3
            payload["max_tokens"] = userMaxTokens
            let data = try? JSONSerialization.data(withJSONObject: payload)
            return (data, "fallback=true, max_tokens=\(userMaxTokens)")
        }

        // 2. Расчет лимита токенов
        var maxTokensParam = userMaxTokens
        let isReasoningOff = (config.reasoningEffort == .off && config.thinkingBudgetMode == .off)

        if !isReasoningOff {
            switch config.thinkingBudgetMode {
            case .off:
                maxTokensParam = max(userMaxTokens, minTokensForOutput)
            case .fixed1024:
                let budget = 1024
                maxTokensParam = max(userMaxTokens, budget + minTokensForOutput)
            case .proportional:
                let budget = max(256, approxPromptTokens * 2)
                maxTokensParam = max(userMaxTokens, budget + minTokensForOutput)
            }
        }

        if isOpenAI_O_Series {
            payload["max_completion_tokens"] = maxTokensParam
        } else {
            payload["max_tokens"] = maxTokensParam
        }

        // 3. Температура
        if !isOpenAI_O_Series {
            if config.thinkingBudgetMode != .off && baseURLLower.contains("anthropic") {
                payload["temperature"] = 1.0
            } else {
                payload["temperature"] = 0.3
            }
        }

        // 4. Управление ризонингом
        if isReasoningOff {
            // Гарантированное выключение
            if isQwen {
                payload["chat_template_kwargs"] = ["enable_thinking": false]
            }
            if isDeepSeek {
                payload["thinking"] = ["type": "disabled"]
            }
            if isOpenRouter {
                payload["reasoning"] = ["max_tokens": 0]
            }
        } else {
            // Включение ризонинга по контрактам провайдеров
            if isOpenAI_O_Series {
                payload["reasoning_effort"] = config.reasoningEffort.rawValue
            } else if isDeepSeek {
                payload["thinking"] = ["type": "enabled"]
                let effortStr = (config.reasoningEffort == .low) ? "low" : "high"
                payload["reasoning_effort"] = effortStr
            } else if isQwen {
                payload["chat_template_kwargs"] = ["enable_thinking": true]
            } else if isOpenRouter {
                payload["reasoning"] = ["effort": config.reasoningEffort.rawValue]
            }

            if config.thinkingBudgetMode != .off {
                let budget: Int
                switch config.thinkingBudgetMode {
                case .off: budget = 0
                case .fixed1024: budget = 1024
                case .proportional: budget = max(256, approxPromptTokens * 2)
                }
                if budget > 0 {
                    payload["thinking"] = ["type": "enabled", "budget_tokens": budget]
                    payload["max_thinking_tokens"] = budget
                }
            }
        }

        let data = try? JSONSerialization.data(withJSONObject: payload)
        let desc = "reasoningOff=\(isReasoningOff), max_tokens=\(maxTokensParam)"
        return (data, desc)
    }

    @discardableResult
    func chatStream(
        messages: [AIChatMessage],
        using config: AIProviderConfig,
        promptLength: Int? = nil,
        isFallback: Bool = false,
        handle: AICancelableRequest? = nil,
        onChunk: @escaping (String, String?) -> Void,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> AICancelableRequest? {
        let requestHandle = handle ?? AICancelableRequest()
        if requestHandle.isCancelled { return requestHandle }

        guard let url = url(config.baseURL, path: "chat/completions") else {
            completion(.failure(.invalidURL))
            return nil
        }
        if url.scheme?.lowercased() == "http" && !AIProviderStore.shared.allowInsecureHTTP {
            completion(.failure(.network(L10n.tr("HTTP запрещён. Включите разрешение HTTP или используйте HTTPS."))))
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payloadInfo = buildUniversalPayload(
            messages: messages,
            config: config,
            promptLength: promptLength,
            stream: true,
            isFallback: isFallback
        )
        guard let data = payloadInfo.data else {
            completion(.failure(.parse("кодирование запроса")))
            return nil
        }
        request.httpBody = data

        AppLogger.shared.info("AI", isFallback ? "Стриминг-запрос (fallback)" : "Стриминг-запрос к модели", details: "\(config.baseURL) / \(config.model), \(payloadInfo.debugDesc)")

        let allowReasoning = (config.reasoningEffort != .off || config.thinkingBudgetMode != .off)

        let task = SSEStreamManager.shared.startStream(
            with: request,
            allowReasoning: allowReasoning,
            onChunk: onChunk
        ) { [weak self] result in
            if requestHandle.isCancelled { return }
            switch result {
            case .failure(let error):
                if case .http(let code, let msg) = error, code == 400, !isFallback {
                    AppLogger.shared.warn("AI", "Стриминг вернул HTTP 400, выполняем повтор с чистым fallback payload", details: msg)
                    _ = self?.chatStream(
                        messages: messages,
                        using: config,
                        promptLength: promptLength,
                        isFallback: true,
                        handle: requestHandle,
                        onChunk: onChunk,
                        completion: completion
                    )
                    return
                }

                // Проверяем автоматический Failover на резервного провайдера
                if let backup = AIProviderStore.shared.failoverConfig, backup.baseURL != config.baseURL || backup.model != config.model {
                    if self?.shouldTriggerFailover(for: error) == true {
                        self?.setFailoverInUse(true, reason: error.localizedDescription)
                        AppLogger.shared.warn("AI", "Основной провайдер недоступен, автоматическое переключение на резервный (Failover)", details: "\(backup.baseURL) / \(backup.model)")
                        _ = self?.chatStream(
                            messages: messages,
                            using: backup,
                            promptLength: promptLength,
                            isFallback: false,
                            handle: requestHandle,
                            onChunk: onChunk,
                            completion: completion
                        )
                        return
                    }
                }

                completion(.failure(error))
            case .success(let val):
                completion(.success(val))
            }
        }
        requestHandle.bind(task)
        return requestHandle
    }

    @discardableResult
    func chat(
        messages: [AIChatMessage],
        using config: AIProviderConfig,
        promptLength: Int? = nil,
        timeout: TimeInterval = 15,
        isFallback: Bool = false,
        handle: AICancelableRequest? = nil,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> AICancelableRequest? {
        let requestHandle = handle ?? AICancelableRequest()
        if requestHandle.isCancelled { return requestHandle }
        let startedAt = Date()
        // Каждый новый запрос начинается с основного — сбрасываем индикатор резерва.
        if !isFallback { setFailoverInUse(false) }

        // Если основной недавно упал, не ждём ещё один полный тайм-аут — сразу резерв.
        if !isFallback,
           let backup = AIProviderStore.shared.failoverConfig,
           backup.baseURL != config.baseURL || backup.model != config.model,
           let failure = activeFailure(for: config) {
            AppLogger.shared.warn("AI", "Основной провайдер в карантине, запрос сразу уходит в failover", details: "\(config.baseURL) / \(config.model); причина: \(failure.reason); резерв: \(backup.baseURL) / \(backup.model)")
            setFailoverInUse(true, reason: failure.reason)
            return chat(messages: messages, using: backup, promptLength: promptLength, timeout: timeout, handle: requestHandle, completion: completion)
        }

        guard let url = url(config.baseURL, path: "chat/completions") else {
            completion(.failure(.invalidURL))
            return nil
        }
        if url.scheme?.lowercased() == "http" && !AIProviderStore.shared.allowInsecureHTTP {
            completion(.failure(.network(L10n.tr("HTTP запрещён. Включите разрешение HTTP или используйте HTTPS."))))
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payloadInfo = buildUniversalPayload(
            messages: messages,
            config: config,
            promptLength: promptLength,
            stream: false,
            isFallback: isFallback
        )
        guard let data = payloadInfo.data else {
            completion(.failure(.parse("кодирование запроса")))
            return nil
        }
        request.httpBody = data

        AppLogger.shared.info("AI", isFallback ? "Запрос к модели (fallback)" : "Запрос к модели", details: "\(config.baseURL) / \(config.model), timeout=\(Int(timeout))с, \(payloadInfo.debugDesc)")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if requestHandle.isCancelled { return }
            if let error {
                if (error as NSError).code == NSURLErrorCancelled {
                    AppLogger.shared.info("AI", "Запрос к модели отменён пользователем")
                    return
                }
                let nsError = error as NSError
                let elapsed = Self.elapsedMs(since: startedAt)
                let reason = "\(nsError.domain) code=\(nsError.code): \(error.localizedDescription), \(elapsed) мс"
                AppLogger.shared.error("AI", "Сетевой сбой chat-completions", details: "\(config.baseURL) / \(config.model); \(reason)")
                let aiError = AIError.network(error.localizedDescription)
                if let backup = AIProviderStore.shared.failoverConfig, backup.baseURL != config.baseURL || backup.model != config.model {
                    if self?.shouldTriggerFailover(for: aiError) == true {
                        self?.markFailed(config, reason: reason)
                        self?.setFailoverInUse(true, reason: reason)
                        AppLogger.shared.warn("AI", "Основной провайдер недоступен (тайм-аут/сеть), переключение на резервный (Failover)", details: "причина: \(reason); основной: \(config.baseURL) / \(config.model); резерв: \(backup.baseURL) / \(backup.model)")
                        _ = self?.chat(messages: messages, using: backup, promptLength: promptLength, timeout: timeout, handle: requestHandle, completion: completion)
                        return
                    }
                }
                completion(.failure(aiError))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network("нет HTTP-ответа")))
                return
            }
            guard let data else {
                completion(.failure(.emptyResponse))
                return
            }
            if !(200..<300).contains(http.statusCode) {
                let errDetail = Self.extractError(from: data) ?? "HTTP \(http.statusCode)"
                if http.statusCode == 400 && !isFallback {
                    AppLogger.shared.warn("AI", "Провайдер вернул HTTP 400, выполняем повтор с чистым fallback payload", details: errDetail)
                    _ = self?.chat(
                        messages: messages,
                        using: config,
                        promptLength: promptLength,
                        timeout: timeout,
                        isFallback: true,
                        handle: requestHandle,
                        completion: completion
                    )
                    return
                }

                let httpErr = AIError.http(http.statusCode, errDetail)
                let reason = "HTTP \(http.statusCode): \(errDetail), \(Self.elapsedMs(since: startedAt)) мс"
                AppLogger.shared.error("AI", "Ошибка ответа chat-completions", details: "\(config.baseURL) / \(config.model); \(reason)")
                // Failover при 401, 403, 404, 429, 5xx
                if let backup = AIProviderStore.shared.failoverConfig, backup.baseURL != config.baseURL || backup.model != config.model {
                    if self?.shouldTriggerFailover(for: httpErr) == true {
                        self?.markFailed(config, reason: reason)
                        self?.setFailoverInUse(true, reason: reason)
                        AppLogger.shared.warn("AI", "Сбой основного провайдера (\(http.statusCode)), переключение на резервный (Failover)", details: "причина: \(reason); основной: \(config.baseURL) / \(config.model); резерв: \(backup.baseURL) / \(backup.model)")
                        _ = self?.chat(messages: messages, using: backup, promptLength: promptLength, timeout: timeout, handle: requestHandle, completion: completion)
                        return
                    }
                }

                completion(.failure(httpErr))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                AppLogger.shared.error("AI", "Ответ chat-completions не является JSON", details: "\(config.baseURL) / \(config.model); \(Self.elapsedMs(since: startedAt)) мс")
                completion(.failure(.parse("не JSON")))
                return
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.isEmpty else {
                AppLogger.shared.error("AI", "Модель вернула пустой ответ", details: "\(config.baseURL) / \(config.model); \(Self.elapsedMs(since: startedAt)) мс")
                completion(.failure(.emptyResponse))
                return
            }
            self?.clearProviderFailure(config)
            if isFallback {
                AppLogger.shared.info("AI", "Запрос выполнен через резервный провайдер", details: "\(config.baseURL) / \(config.model); \(Self.elapsedMs(since: startedAt)) мс")
            }
            completion(.success(content))
        }
        requestHandle.bind(task)
        task.resume()
        return requestHandle
    }

    private func shouldTriggerFailover(for error: AIError) -> Bool {
        switch error {
        case .network:
            return true
        case .http(let code, _):
            return code == 401 || code == 403 || code == 404 || code == 429 || code >= 500
        case .emptyResponse, .invalidURL, .notConfigured:
            return true
        case .parse:
            return false
        }
    }

    private static let checkTimeout: TimeInterval = 15

    /// Полная проверка: и /models, и реальный /chat/completions с выбранной моделью.
    /// Раньше тест ограничивался /models — поэтому «Подключено» показывалось даже
    /// когда чат с моделью висел до тайм-аута (ровно так проявлялся наш сбой).
    func checkProvider(using config: AIProviderConfig, completion: @escaping (Result<AIProviderCheck, AIError>) -> Void) {
        var stages: [AIProviderCheckStage] = []
        checkModelsEndpoint(config) { modelsStage in
            stages.append(modelsStage)
            self.checkChatEndpoint(config) { chatStage in
                stages.append(chatStage)
                let check = AIProviderCheck(baseURL: config.baseURL, model: config.model, stages: stages)
                AppLogger.shared.info("AI", "Диагностика провайдера завершена", details: check.technicalSummary)
                completion(.success(check))
            }
        }
    }

    /// Обратная совместимость: старый тест теперь считает подключение успешным
    /// только если проходит и генерация, а не один /models.
    func test(using config: AIProviderConfig, completion: @escaping (Result<Void, AIError>) -> Void) {
        checkProvider(using: config) { result in
            switch result {
            case .success(let check):
                if check.isUsable {
                    completion(.success(()))
                } else {
                    completion(.failure(.network(check.chatStage?.detail ?? "нет ответа от сервера")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func checkModelsEndpoint(_ config: AIProviderConfig, then: @escaping (AIProviderCheckStage) -> Void) {
        let started = Date()
        guard let url = url(config.baseURL, path: "models") else {
            then(.init(kind: .models, ok: false, elapsedMs: 0, detail: "некорректный URL /models"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.checkTimeout
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        session.dataTask(with: request) { data, response, error in
            let elapsed = Self.elapsedMs(since: started)
            let stage: AIProviderCheckStage
            if let error {
                stage = .init(kind: .models, ok: false, elapsedMs: elapsed, detail: Self.describeTransportError(error))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let detail = data.flatMap(Self.extractError) ?? "HTTP \(http.statusCode)"
                stage = .init(kind: .models, ok: false, elapsedMs: elapsed, detail: "HTTP \(http.statusCode): \(detail)")
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let ids = Self.parseModelIDs(json)
                stage = .init(kind: .models, ok: true, elapsedMs: elapsed,
                              detail: ids.isEmpty ? "список моделей пуст" : "моделей: \(ids.count)",
                              modelIDs: ids)
            } else {
                stage = .init(kind: .models, ok: false, elapsedMs: elapsed, detail: "не удалось разобрать ответ /models")
            }
            AppLogger.shared.info("AI", "Диагностика /models: \(stage.ok ? "OK" : "сбой")", details: stage.technicalSummary)
            then(stage)
        }.resume()
    }

    private func checkChatEndpoint(_ config: AIProviderConfig, then: @escaping (AIProviderCheckStage) -> Void) {
        let started = Date()
        guard let url = url(config.baseURL, path: "chat/completions") else {
            then(.init(kind: .chat, ok: false, elapsedMs: 0, detail: "некорректный URL /chat/completions"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.checkTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        // Минимальный совместимый payload: проверяем именно модель и доступность генерации.
        let payload = buildUniversalPayload(
            messages: [AIChatMessage(role: "user", content: "ping")],
            config: config,
            promptLength: 4,
            stream: false,
            isFallback: true
        )
        guard let body = payload.data else {
            then(.init(kind: .chat, ok: false, elapsedMs: 0, detail: "не удалось собрать запрос"))
            return
        }
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            let elapsed = Self.elapsedMs(since: started)
            let stage: AIProviderCheckStage
            if let error {
                stage = .init(kind: .chat, ok: false, elapsedMs: elapsed, detail: Self.describeTransportError(error))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let detail = data.flatMap(Self.extractError) ?? "HTTP \(http.statusCode)"
                stage = .init(kind: .chat, ok: false, elapsedMs: elapsed, detail: "HTTP \(http.statusCode): \(detail)")
            } else if let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let text = message["content"] as? String,
                      !text.isEmpty {
                stage = .init(kind: .chat, ok: true, elapsedMs: elapsed, detail: "генерация \(text.count) симв.")
            } else {
                stage = .init(kind: .chat, ok: false, elapsedMs: elapsed, detail: "пустой или невалидный ответ")
            }
            if stage.ok {
                AppLogger.shared.info("AI", "Диагностика /chat/completions: OK", details: stage.technicalSummary)
            } else {
                AppLogger.shared.error("AI", "Диагностика /chat/completions: сбой", details: stage.technicalSummary)
            }
            then(stage)
        }.resume()
    }

    /// Тайм-аут URLSession отделяем от прочих сетевых ошибок — это главная
    /// причина «зависания» этапа ИИ, и пользователь должен видеть именно её.
    static func describeTransportError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.code == NSURLErrorTimedOut {
            return "тайм-аут (code=\(ns.code)): \(error.localizedDescription)"
        }
        return "\(ns.domain) code=\(ns.code): \(error.localizedDescription)"
    }

    static func parseModelIDs(_ json: [String: Any]) -> [String] {
        if let items = json["data"] as? [[String: Any]] {
            let ids = items.compactMap { $0["id"] as? String }
            if !ids.isEmpty { return ids }
        }
        if let items = json["models"] as? [[String: Any]] {
            return items.compactMap { $0["name"] as? String }
        }
        return []
    }

    func listModels(using config: AIProviderConfig, completion: @escaping (Result<[String], AIError>) -> Void) {
        guard let url = url(config.baseURL, path: "models") else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        session.dataTask(with: request) { data, response, error in
            if let error {
                let reason = Self.describeTransportError(error)
                AppLogger.shared.error("AI", "Список моделей: сетевая ошибка", details: "\(config.baseURL); \(reason)")
                completion(.failure(.network(reason)))
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let detail = data.flatMap(Self.extractError) ?? "HTTP \(status)"
                AppLogger.shared.error("AI", "Список моделей: ошибка ответа", details: "\(config.baseURL); \(detail)")
                completion(.failure(.http(status, detail)))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                AppLogger.shared.error("AI", "Список моделей: не JSON", details: config.baseURL)
                completion(.failure(.parse("не JSON")))
                return
            }
            completion(.success(Self.parseModelIDs(json)))
        }.resume()
    }

    private func url(_ base: String, path: String) -> URL? {
        URL(string: "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))/\(path)")
    }

    static func extractError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }
}

final class SSEStreamManager: NSObject, URLSessionDataDelegate {
    static let shared = SSEStreamManager()

    private class TaskContext {
        var buffer = ""
        var fullContent = ""
        var fullReasoning = ""
        var isInThinkTag = false
        var hasCompleted = false
        var httpStatusCode: Int?
        var errorData: Data?
        let allowReasoning: Bool
        let onChunk: (String, String?) -> Void
        let completion: (Result<String, AIError>) -> Void

        init(allowReasoning: Bool, onChunk: @escaping (String, String?) -> Void, completion: @escaping (Result<String, AIError>) -> Void) {
            self.allowReasoning = allowReasoning
            self.onChunk = onChunk
            self.completion = completion
        }
    }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var contexts: [Int: TaskContext] = [:]
    private let lock = NSLock()

    func startStream(
        with request: URLRequest,
        allowReasoning: Bool = true,
        onChunk: @escaping (String, String?) -> Void,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        let context = TaskContext(allowReasoning: allowReasoning, onChunk: onChunk, completion: completion)
        lock.lock()
        contexts[task.taskIdentifier] = context
        lock.unlock()
        task.resume()
        return task
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let ctx = contexts[dataTask.taskIdentifier]
        lock.unlock()

        if let http = response as? HTTPURLResponse {
            ctx?.httpStatusCode = http.statusCode
            if !(200..<300).contains(http.statusCode) {
                ctx?.errorData = Data()
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let ctx = contexts[dataTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        lock.unlock()

        if let status = ctx.httpStatusCode, !(200..<300).contains(status) {
            ctx.errorData?.append(data)
            return
        }

        guard let text = String(data: data, encoding: .utf8) else { return }
        ctx.buffer.append(text)

        var lines: [String] = []
        while let range = ctx.buffer.range(of: "\n") {
            let line = String(ctx.buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.buffer.removeSubrange(..<range.upperBound)
            if !line.isEmpty {
                lines.append(line)
            }
        }

        for line in lines {
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    completeTask(dataTask.taskIdentifier, with: .success(ctx.fullContent))
                    return
                }
                guard let jsonData = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let delta = firstChoice["delta"] as? [String: Any] else {
                    continue
                }

                let rawContent = delta["content"] as? String
                let rawReasoning = ctx.allowReasoning ? ((delta["reasoning_content"] as? String) ?? (delta["thinking"] as? String)) : nil

                var contentChunk: String? = nil
                var reasoningChunk: String? = nil

                if let rawReasoning, !rawReasoning.isEmpty {
                    reasoningChunk = rawReasoning
                }

                if var text = rawContent, !text.isEmpty {
                    if text.contains("<think>") {
                        ctx.isInThinkTag = true
                        text = text.replacingOccurrences(of: "<think>", with: "")
                    }
                    if ctx.isInThinkTag {
                        if text.contains("</think>") {
                            ctx.isInThinkTag = false
                            let parts = text.components(separatedBy: "</think>")
                            let thinkPart = parts.first ?? ""
                            let cleanPart = parts.dropFirst().joined(separator: "</think>")
                            if ctx.allowReasoning && !thinkPart.isEmpty {
                                reasoningChunk = (reasoningChunk ?? "") + thinkPart
                            }
                            if !cleanPart.isEmpty {
                                contentChunk = cleanPart
                            }
                        } else {
                            if ctx.allowReasoning {
                                reasoningChunk = (reasoningChunk ?? "") + text
                            }
                        }
                    } else {
                        contentChunk = text
                    }
                }

                if let contentChunk, !contentChunk.isEmpty {
                    ctx.fullContent.append(contentChunk)
                }
                if let reasoningChunk, !reasoningChunk.isEmpty {
                    ctx.fullReasoning.append(reasoningChunk)
                }

                if (contentChunk != nil && !contentChunk!.isEmpty) || (reasoningChunk != nil && !reasoningChunk!.isEmpty) {
                    DispatchQueue.main.async {
                        ctx.onChunk(contentChunk ?? "", reasoningChunk)
                    }
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        lock.lock()
        guard let ctx = contexts[taskID] else {
            lock.unlock()
            return
        }
        lock.unlock()

        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled {
                AppLogger.shared.info("AI", "Стриминг остановлен пользователем", details: "длина текста: \(ctx.fullContent.count)")
                if !ctx.fullContent.isEmpty {
                    completeTask(taskID, with: .success(ctx.fullContent))
                } else {
                    removeTask(taskID)
                }
                return
            }
            completeTask(taskID, with: .failure(.network(error.localizedDescription)))
            return
        }

        if let status = ctx.httpStatusCode, !(200..<300).contains(status) {
            let errorMsg = ctx.errorData.flatMap { AIService.extractError(from: $0) } ?? "HTTP \(status)"
            completeTask(taskID, with: .failure(.http(status, errorMsg)))
            return
        }

        if !ctx.fullContent.isEmpty {
            completeTask(taskID, with: .success(ctx.fullContent))
        } else {
            completeTask(taskID, with: .failure(.emptyResponse))
        }
    }

    private func completeTask(_ id: Int, with result: Result<String, AIError>) {
        lock.lock()
        guard let ctx = contexts[id], !ctx.hasCompleted else {
            lock.unlock()
            return
        }
        ctx.hasCompleted = true
        contexts.removeValue(forKey: id)
        lock.unlock()

        DispatchQueue.main.async {
            ctx.completion(result)
        }
    }

    private func removeTask(_ id: Int) {
        lock.lock()
        contexts.removeValue(forKey: id)
        lock.unlock()
    }
}
