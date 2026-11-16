import Foundation

/// Однократная миграция данных из предыдущей версии продукта (`Golosok` → `GolosYaka`).
///
/// При ренейме меняется bundle id, а вместе с ним домен `UserDefaults`, имя элемента
/// Keychain и каталог в Application Support. Без миграции пользователь теряет историю
/// заметок, словарь терминов, промпты и сохранённые API-ключи. Миграция идемпотентна:
/// флаг в новом домене гарантирует, что она выполнится ровно один раз.
enum LegacyMigration {
    /// Bundle id предыдущей сборки. Меняется только вместе с историей версий.
    static let legacyBundleIdentifier = "kozak-developer.Golosok"

    private static let completedKey = "migration.fromGolosok.completed"
    private static let lock = NSLock()
    private static var didRun = false

    static func runIfNeeded() {
        lock.lock()
        if didRun {
            lock.unlock()
            return
        }
        // Ставим флаг до работы: миграция не должна рекурсивно вызывать саму себя
        // через AppLogger/AppPaths, которые могут понадобиться ниже.
        didRun = true
        lock.unlock()

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: completedKey) else { return }

        migrateApplicationSupport()
        migratePreferences()
        KeyStore.adoptLegacyPack(from: legacyBundleIdentifier)

        defaults.set(true, forKey: completedKey)
        log("Миграция из Golosok завершена")
    }

    // MARK: - Application Support

    private static func migrateApplicationSupport() {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = base.appendingPathComponent(AppPaths.legacyFolderName, isDirectory: true)
        let current = base.appendingPathComponent(AppPaths.folderName, isDirectory: true)

        guard fileManager.fileExists(atPath: legacy.path) else { return }
        guard !fileManager.fileExists(atPath: current.path) else {
            log("Каталог \(AppPaths.folderName) уже существует — данные Golosok оставлены как есть")
            return
        }

        do {
            try fileManager.moveItem(at: legacy, to: current)
            log("Перенесён каталог данных Application Support")
        } catch {
            log("Не удалось перенести каталог данных: \(error.localizedDescription)")
        }
    }

    // MARK: - UserDefaults

    private static func migratePreferences() {
        guard let legacy = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        let standard = UserDefaults.standard
        let existing = standard.dictionaryRepresentation()
        let skippedPrefixes = ["NS", "Apple", "AK", "WebKit", completedKey]

        var copied = 0
        for (key, value) in legacy.dictionaryRepresentation() {
            if skippedPrefixes.contains(where: { key.hasPrefix($0) }) { continue }
            if existing[key] != nil { continue }
            standard.set(value, forKey: key)
            copied += 1
        }

        if copied > 0 {
            log("Перенесено настроек: \(copied)")
        }
    }

    // MARK: - Логирование

    /// Во время миграции AppLogger ещё не готов (его путь сам зависит от AppPaths),
    /// поэтому пишем в stderr — это видно в Console.app и не создаёт рекурсию.
    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[GolosYaka][migration] \(message)\n".utf8))
    }
}
