import Foundation
import SwiftUI

/// Фоновая одноразовая миграция архива WAV → AAC.
/// Устойчива к прерываниям: файлы, у которых уже есть `.m4a`, пропускаются.
/// Оригинал удаляется только после успешного кодирования и сверки длительности.
final class AudioStorageMigrator: ObservableObject {
    static let shared = AudioStorageMigrator()

    @Published private(set) var isRunning = false
    @Published private(set) var processed = 0
    @Published private(set) var total = 0
    @Published private(set) var savedBytes: Int64 = 0
    @Published private(set) var failed = 0
    @Published private(set) var summary = ""

    private let queue = DispatchQueue(label: "GolosYaka.AudioStorageMigrator", qos: .utility)

    func start() {
        guard !isRunning, let directory = AppPaths.audioDirectory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ))?.filter { $0.pathExtension.lowercased() == AudioStorage.legacyExtension } ?? []
        guard !files.isEmpty else { return }

        summary = ""
        total = files.count
        processed = 0
        savedBytes = 0
        failed = 0
        isRunning = true
        AppLogger.shared.info("Storage", "Миграция аудио начата", details: "файлов: \(files.count), AAC \(AudioStorage.aacBitrate / 1000) кбит/с")

        queue.async { [weak self] in
            guard let self else { return }
            for wav in files {
                autoreleasepool { self.convert(wav) }
                DispatchQueue.main.async { self.processed += 1 }
            }
            DispatchQueue.main.async {
                self.isRunning = false
                let message = "обработано: \(self.processed), ошибок: \(self.failed), сохранено: \(self.savedBytes / 1_048_576) МБ"
                self.summary = message
                AppLogger.shared.info("Storage", "Миграция аудио завершена", details: message)
            }
        }
    }

    private func convert(_ wav: URL) {
        let fm = FileManager.default
        let compressed = wav.deletingPathExtension().appendingPathExtension(AudioStorage.compressedExtension)
        guard !fm.fileExists(atPath: compressed.path) else { return }

        // Не трогаем запись, которая сейчас играет.
        if let id = AudioStorage.audioID(from: wav), AudioCapture.shared.playingItemId == id { return }

        guard let originalDuration = AudioStorage.duration(of: wav) else {
            noteFailure("не удалось прочитать длительность \(wav.lastPathComponent)")
            return
        }
        let before = (try? wav.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard AudioStorage.encodeAAC24(from: wav, to: compressed),
              let newDuration = AudioStorage.duration(of: compressed),
              abs(newDuration - originalDuration) < 0.5 else {
            try? fm.removeItem(at: compressed)
            noteFailure("проверка длительности не прошла: \(wav.lastPathComponent)")
            return
        }
        let after = (try? compressed.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        try? fm.removeItem(at: wav)
        let saved = Int64(max(0, before - after))
        DispatchQueue.main.async { self.savedBytes += saved }
    }

    private func noteFailure(_ reason: String) {
        AppLogger.shared.warn("Storage", "Миграция: файл пропущен", details: reason)
        DispatchQueue.main.async { self.failed += 1 }
    }
}
