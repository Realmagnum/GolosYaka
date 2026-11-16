import Foundation

/// Единственная точка правды для путей приложения.
///
/// Раньше каталог `~/Library/Application Support/GolosYaka` собирался литералами в семи
/// файлах — из-за этого ренейм бренда превращался в россыпь правок, а миграция данных
/// из старой версии была невозможна. Теперь все сторы ходят сюда.
enum AppPaths {
    /// Текущее имя каталога данных.
    static let folderName = "GolosYaka"
    /// Каталог предыдущей версии продукта (до ренейма) — источник однократной миграции.
    static let legacyFolderName = "Golosok"

    /// `~/Library/Application Support/GolosYaka`, создаётся при обращении.
    static var applicationSupportDirectory: URL? {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        // Миграция должна случиться до создания каталога, иначе move не сработает.
        LegacyMigration.runIfNeeded()
        let directory = base.appendingPathComponent(folderName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// `.../GolosYaka/Audio` — записи заметок и тайминги слов.
    static var audioDirectory: URL? {
        guard let support = applicationSupportDirectory else { return nil }
        let directory = support.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// `.../GolosYaka/Models` — скачанные локальные модели распознавания.
    static var modelsDirectory: URL? {
        guard let support = applicationSupportDirectory else { return nil }
        return support.appendingPathComponent("Models", isDirectory: true)
    }

    /// `.../GolosYaka/Logs` — файл app.log.
    static var logsDirectory: URL? {
        guard let support = applicationSupportDirectory else { return nil }
        let directory = support.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
