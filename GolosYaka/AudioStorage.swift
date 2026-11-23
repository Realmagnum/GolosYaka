import Foundation
import AVFoundation

/// Формат хранения аудио заметок.
///
/// Раньше каждая запись копировалась как PCM WAV 16 кГц/16 бит/моно (256 кбит/с).
/// Теперь новые записи кодируются в AAC 24 кбит/с — примерно в 9 раз меньше места.
/// Старые `.wav` продолжают работать через фолбэк; для повторного распознавания
/// сжатый файл на лету декодируется в PCM WAV через бандл-ffmpeg (для воспроизведения
/// конвертация не нужна — AVAudioPlayer читает m4a напрямую).
enum AudioFileValidation: Equatable {
    case valid
    /// WAV с нулевой data-частью: звука нет, но текст и тайминги заметки целы.
    case empty
    /// Структура файла повреждена или Core Audio не может его прочитать.
    case unreadable
}

enum AudioStorage {
    static let compressedExtension = "m4a"
    static let legacyExtension = "wav"
    static let aacBitrate = 24_000

    /// Проверяет файл, не загружая его целиком: читается только заголовок.
    static func validation(of url: URL) -> AudioFileValidation {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 4096)) ?? Data()
        let totalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return validate(header, extension: url.pathExtension.lowercased(), totalBytes: totalBytes)
    }

    /// Чистая функция разбора RIFF/WAVE — проверяется в тестах без диска.
    static func validate(_ data: Data, extension ext: String, totalBytes: Int) -> AudioFileValidation {
        guard ext == legacyExtension else {
            return totalBytes > 1024 ? .valid : .unreadable
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              Array(bytes[0..<4]) == Array("RIFF".utf8),
              Array(bytes[8..<12]) == Array("WAVE".utf8) else { return .unreadable }

        var pos = 12
        while pos + 8 <= bytes.count {
            let id = Array(bytes[pos..<pos+4])
            let chunkSize = Int(bytes[pos+4])
                | (Int(bytes[pos+5]) << 8)
                | (Int(bytes[pos+6]) << 16)
                | (Int(bytes[pos+7]) << 24)
            if id == Array("data".utf8) {
                if chunkSize <= 0 || totalBytes <= pos + 8 { return .empty }
                return .valid
            }
            let step = 8 + chunkSize + (chunkSize & 1)
            if step <= 0 { return .unreadable }
            pos += step
        }
        return .unreadable
    }

    /// Возвращает реально существующий файл записи, а при отсутствии обоих —
    /// legacy-путь (чтобы проверки `fileExists` у вызывающих работали как раньше).
    static func url(for id: UUID) -> URL? {
        url(for: id, in: AppPaths.audioDirectory)
    }

    static func url(for id: UUID, in directory: URL?) -> URL? {
        guard let directory else { return nil }
        let base = directory.appendingPathComponent(id.uuidString)
        let compressed = base.appendingPathExtension(compressedExtension)
        let fm = FileManager.default
        if fm.fileExists(atPath: compressed.path) { return compressed }
        let legacy = base.appendingPathExtension(legacyExtension)
        return legacy
    }

    static func audioID(from url: URL) -> UUID? {
        UUID(uuidString: url.deletingPathExtension().lastPathComponent)
    }

    /// Длительность через Core Audio — работает и для WAV, и для m4a.
    static func duration(of url: URL) -> TimeInterval? {
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        return player.duration
    }

    /// Кодирует в AAC 24 кбит/с через системный afconvert (энкодер AAC есть в ФПИ,
    /// а вот бандл-ffmpeg умеет только декодировать). При неудаче — AVAudioFile.
    static func encodeAAC24(from source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(compressedExtension)")
        defer { try? fm.removeItem(at: temp) }

        var ok = false
        let afconvert = "/usr/bin/afconvert"
        if fm.isExecutableFile(atPath: afconvert) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: afconvert)
            task.arguments = ["-f", "m4af", "-d", "aac", "-b", String(aacBitrate),
                              source.path, temp.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                ok = task.terminationStatus == 0 && size > 1024
            } catch { ok = false }
        }
        if !ok { ok = encodeViaAVAudioFile(from: source, to: temp) }
        guard ok else { return false }

        if fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
        do {
            try fm.moveItem(at: temp, to: destination)
            return true
        } catch {
            return false
        }
    }

    private static func encodeViaAVAudioFile(from source: URL, to destination: URL) -> Bool {
        do {
            let input = try AVAudioFile(forReading: source)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: aacBitrate
            ]
            let output = try AVAudioFile(forWriting: destination, settings: settings)
            let capacity = AVAudioFrameCount(input.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity) else { return false }
            try input.read(into: buffer)
            try output.write(from: buffer)
            return true
        } catch {
            AppLogger.shared.warn("Storage", "AAC-кодирование через AVAudioFile не удалось", details: error.localizedDescription)
            return false
        }
    }

    /// Декодирование в 16 кГц/моно PCM для повторного распознавания.
    static func decodeToWAV(from source: URL, to destination: URL) -> Bool {
        guard let ffmpeg = ffmpegPath() else {
            AppLogger.shared.error("Storage", "ffmpeg не найден — декодирование аудио невозможно")
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = ["-y", "-loglevel", "error", "-i", source.path,
                          "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", destination.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return task.terminationStatus == 0 && size > 44
        } catch {
            AppLogger.shared.error("Storage", "Декодирование аудио не удалось", details: error.localizedDescription)
            return false
        }
    }

    static func ffmpegPath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let bundled = Bundle.main.path(forResource: "ffmpeg", ofType: nil) { candidates.append(bundled) }
        candidates += ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}
