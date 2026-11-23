// Локальный smoke-набор GolosYaka.
//
// Запускается без Xcode: `./scripts/run-tests.sh` компилирует приложение как модуль
// с `-enable-testing` и прогоняет проверки ниже. Полный набор на Swift Testing
// (GolosYakaTests/GolosYakaTests.swift) выполняется в CI через xcodebuild, где есть Xcode.
//
// Правило: каждая проверка — чистая функция без сети, UI и доступа к диску.

import Foundation
import AppKit
@testable import GolosYaka

// MARK: - Минимальный assert-раннер

final class SmokeRunner {
    private(set) var passed = 0
    private(set) var failed = 0
    private var failures: [String] = []

    func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            failures.append("\(file):\(line) — \(message)")
        }
    }

    func expectEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
        let left = lhs()
        let right = rhs()
        expect(left == right, "\(message): получили \(left), ожидали \(right)", file: file, line: line)
    }

    func report() -> Int32 {
        for failure in failures {
            print("  ✗ \(failure)")
        }
        print("")
        print(failed == 0 ? "✅ Smoke-тесты: \(passed) проверок, 0 падений" : "❌ Smoke-тесты: \(passed) прошло, \(failed) упало")
        return failed == 0 ? 0 : 1
    }
}

// MARK: - Проверки

let runner = SmokeRunner()
let r = runner

func timedWords(_ texts: [String]) -> [TimedWord] {
    texts.enumerated().map { TimedWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 1) }
}

func wordRanges(_ text: String, _ words: [TimedWord]) -> [NSRange] {
    SyncedTextView.Coordinator(onSeek: { _ in }).wordRanges(text: text, words: words)
}

// TextFormatter: абзацы
r.expectEqual(TextFormatter.formatIntoParagraphs(""), "", "Пустой текст остаётся пустым")
r.expectEqual(TextFormatter.formatIntoParagraphs("просто строка"), "просто строка", "Текст без пунктуации не меняется")
r.expectEqual(
    TextFormatter.formatIntoParagraphs("Привет. Как дела? Хорошо!"),
    "Привет. Как дела? Хорошо!",
    "Три предложения — один абзац"
)
r.expectEqual(
    TextFormatter.formatIntoParagraphs("Первое. Второе. Третье. Четвертое."),
    "Первое. Второе. Третье.\n\nЧетвертое.",
    "Разрыв абзаца после третьего предложения"
)
r.expectEqual(
    TextFormatter.formatIntoParagraphs("— Привет. — Здравствуй!"),
    "— Привет.\n\n— Здравствуй!",
    "Реплики диалога — отдельные абзацы"
)

// TextFormatter: числа
r.expectEqual(TextFormatter.normalizeRussianNumbers("у меня двадцать пять файлов"), "у меня 25 файлов", "Составное число")
r.expectEqual(TextFormatter.normalizeRussianNumbers("двадцать пять тысяч сто двадцать три"), "25123", "Большое число")
r.expectEqual(TextFormatter.normalizeRussianNumbers("пять миллионов триста тысяч"), "5300000", "Миллионы")
r.expectEqual(
    TextFormatter.normalizeRussianNumbers("пятый этаж, двадцать пять процентов."),
    "пятый этаж, 25 процентов.",
    "Порядковые числительные не трогаем"
)
r.expectEqual(TextFormatter.normalizeRussianNumbers("двадцать, пять, шесть и семь"), "20, 5, 6 и 7", "Числа через запятую")

// Границы чанков
r.expectEqual(
    AudioCapture.removeBoundaryDuplicate(previous: "... мы проверили этот код", current: "этот код и нашли ошибку"),
    "и нашли ошибку",
    "Дубль на стыке чанков удаляется"
)
r.expectEqual(
    AudioCapture.removeBoundaryDuplicate(previous: "... открыли настройки", current: "снова открыли настройки"),
    "снова открыли настройки",
    "Разные слова на стыке остаются"
)
r.expectEqual(
    AudioCapture.removeBoundaryDuplicate(previous: "да", current: "да, конечно"),
    "да, конечно",
    "Короткое совпадение не режется"
)

// Тайминги
do {
    let mapping = AudioCapture.TimeIntervalMapping(
        compressedStart: 0.0,
        compressedEnd: 1.0,
        originalStart: 0.0,
        originalEnd: 3.5
    )
    let result = AudioCapture.ClampedAudioResult(url: URL(fileURLWithPath: "/tmp/fake.wav"), mappings: [mapping])
    r.expectEqual(result.mapCompressedToOriginal(0.5), 0.5, "Тайминг внутри сегмента")
    r.expectEqual(result.mapCompressedToOriginal(1.5), 4.0, "Тайминг за пределами сегмента")
}

do {
    let words = timedWords(["а", "б", "в"])
    let result = AudioCapture.interpolateTimings(words, from: 1.0, to: 4.0)
    r.expectEqual(result.count, 3, "Интерполяция сохраняет число слов")
    r.expectEqual(result[0].start, 1.0, "Интерполяция стартует с начала диапазона")
    r.expect(result[2].end <= 4.001, "Интерполяция не выходит за диапазон")
    for i in 1..<result.count {
        r.expect(result[i].start >= result[i - 1].end, "Слова не перекрываются")
        r.expect(result[i].end > result[i].start, "Длительность слова положительная")
    }
}

do {
    let msWords = [TimedWord(text: "Привет", start: 0, end: 7650.5), TimedWord(text: "мир", start: 7650.5, end: 8000)]
    let normalized = AudioCapture.normalizedWords(msWords, duration: 7.6)
    r.expectEqual(normalized[0].end, 7.6505, "Миллисекунды конвертируются в секунды")
    r.expectEqual(normalized[1].start, 7.6505, "Начало второго слова тоже конвертируется")

    let seconds = [TimedWord(text: "Так,", start: 0.76, end: 1.04), TimedWord(text: "звук", start: 1.2, end: 1.48)]
    r.expectEqual(AudioCapture.normalizedWords(seconds, duration: 6.6), seconds, "Секунды остаются как есть")
}

// Парсинг verbose_json от удаленного OpenAI-совместимого сервера
do {
    let flat: [String: Any] = [
        "text": "Привет мир",
        "words": [
            ["word": "Привет", "start": 0.1, "end": 0.8],
            ["word": "мир", "start": 1.0, "end": 1.8]
        ]
    ]
    let flatWords = AudioCapture.parseRemoteWords(flat)
    r.expectEqual(flatWords.map(\.text), ["Привет", "мир"], "Плоский words читается")
    r.expectEqual(flatWords[1].end, 1.8, "Таймкод последнего слова сохраняется")

    let segmented: [String: Any] = [
        "segments": [
            [
                "start": 0.0,
                "end": 2.0,
                "words": [
                    ["text": "Привет", "start": "0.2", "end": "0.9"],
                    ["text": "мир", "start": 1.0, "end": 1.8]
                ]
            ]
        ]
    ]
    let segWords = AudioCapture.parseRemoteWords(segmented)
    r.expectEqual(segWords.map(\.text), ["Привет", "мир"], "Слова из segments читаются")
    r.expectEqual(segWords[0].start, 0.2, "Строковые таймкоды парсятся")

    let whisperCpp: [String: Any] = [
        "transcription": [
            ["text": "Привет", "offsets": ["from": 100, "to": 800]],
            ["text": "мир", "offsets": ["from": 1000, "to": 1800]]
        ]
    ]
    let msWords = AudioCapture.parseRemoteWords(whisperCpp)
    r.expectEqual(msWords[0].start, 0.1, "Миллисекунды whisper.cpp конвертируются в секунды")
    r.expectEqual(msWords[1].end, 1.8, "Миллисекунды конца тоже конвертируются")

    let sparse: [String: Any] = [
        "words": [
            ["word": "", "start": 0.1, "end": 0.8],
            ["word": "слово"],
            ["word": "ок", "start": 1.0, "end": 1.5]
        ]
    ]
    r.expectEqual(AudioCapture.parseRemoteWords(sparse).map(\.text), ["ок"], "Пустые и бессрочные записи пропускаются")
}

// Субтитры
do {
    let words = [
        TimedWord(text: "Привет,", start: 0.0, end: 0.5),
        TimedWord(text: "мир.", start: 0.5, end: 1.0),
        TimedWord(text: "Как", start: 1.5, end: 1.7),
        TimedWord(text: "дела?", start: 1.7, end: 2.2)
    ]
    let cues = AudioCapture.makeSubtitleCues(from: words)
    r.expectEqual(cues.count, 2, "Две фразы — две реплики")
    r.expectEqual(cues[0].text, "Привет, мир.", "Первая реплика собрана")
    r.expectEqual(cues[1].text, "Как дела?", "Вторая реплика собрана")

    let srt = AudioCapture.srtContent(cues: [SubtitleCue(start: 0.0, end: 2.36, text: "Привет, это проверка")])
    r.expectEqual(srt, "1\n00:00:00,000 --> 00:00:02,360\nПривет, это проверка\n\n", "SRT форматируется верно")

    let vtt = AudioCapture.vttContent(cues: [SubtitleCue(start: 1.5, end: 3.0, text: "Текст")])
    r.expect(vtt.hasPrefix("WEBVTT\n\n"), "VTT начинается с заголовка")
    r.expect(vtt.contains("00:00:01.500 --> 00:00:03.000"), "VTT использует точку в таймкоде")

    r.expectEqual(AudioCapture.srtTime(3661.5), "01:01:01,500", "SRT-время")
    r.expectEqual(AudioCapture.vttTime(3661.5), "01:01:01.500", "VTT-время")
}

// Сравнение версий апдейтера
r.expectEqual(AudioCapture.compareVersions("v1.12.2", "1.12.1"), .orderedDescending, "Новая версия больше")
r.expectEqual(AudioCapture.compareVersions("1.10.0", "1.12.1"), .orderedAscending, "Старая версия меньше")
r.expectEqual(AudioCapture.compareVersions("1.12.1", "1.12.1"), .orderedSame, "Равные версии")
r.expectEqual(AudioCapture.compareVersions("2.0", "1.99.9"), .orderedDescending, "Разная длина версий")

// Доверие к источнику обновлений
r.expect(AudioCapture.isTrustedReleaseAsset(URL(string: "https://github.com/Realmagnum/GolosYaka/releases/download/v1/dmg")!), "GitHub-ассет доверенный")
r.expect(AudioCapture.isTrustedReleaseAsset(URL(string: "https://objects.githubusercontent.com/file")!), "CDN GitHub доверенный")
r.expect(!AudioCapture.isTrustedReleaseAsset(URL(string: "http://github.com/file")!), "HTTP не доверяем")
r.expect(!AudioCapture.isTrustedReleaseAsset(URL(string: "https://evil.example.com/GolosYaka.dmg")!), "Чужой хост не доверяем")

// Выравнивание слов
do {
    let text = "Привет! Это проверка."
    let ranges = wordRanges(text, timedWords(["Привет!", "Это", "проверка."]))
    r.expectEqual(ranges.count, 3, "Три слова — три диапазона")
    r.expectEqual(ranges[0], NSRange(location: 0, length: 7), "Первый диапазон точный")
    r.expectEqual(ranges[2], NSRange(location: 12, length: 9), "Третий диапазон точный")

    let replaced = wordRanges("привет Tailscale мир", timedWords(["привет", "тейлскейл", "мир"]))
    r.expectEqual(replaced[1], NSRange(location: 7, length: 9), "Заменённый термин занимает весь промежуток")

    let missing = wordRanges("привет мир", timedWords(["привет", "неттакого", "мир"]))
    r.expectEqual(missing[1].location, NSNotFound, "Отсутствующее слово — NSNotFound")

    r.expect(wordRanges("", timedWords(["слово"])).isEmpty, "Пустой текст — нет диапазонов")
}

// Поиск по транскрипту
do {
    let words = timedWords(["Привет", "мир", "ПРИВЕТ", "дом"])
    r.expectEqual(TranscriptSearch.matchedWordIndices(in: words, query: "привет"), [0, 2], "Поиск без учёта регистра")
    r.expectEqual(TranscriptSearch.matchedWordIndices(in: timedWords(["прилетел", "привет", "ушёл"]), query: "при"), [0, 1], "Поиск по подстроке")
    r.expectEqual(TranscriptSearch.matchedWordIndices(in: timedWords(["еле", "ёлка", "ёж"]), query: "е"), [0, 1, 2], "Поиск без учёта диакритики")
    r.expect(TranscriptSearch.matchedWordIndices(in: words, query: "").isEmpty, "Пустой запрос — нет совпадений")
    r.expectEqual(TranscriptSearch.matchedRanges(in: "кот пошёл к коту за котёнком", query: "кот").count, 3, "Все вхождения в тексте")
    r.expect(TranscriptSearch.matchedRanges(in: "текст", query: "").isEmpty, "Пустой запрос в тексте — нет совпадений")
}

// Ренейм и миграция данных
r.expectEqual(AppPaths.folderName, "GolosYaka", "Каталог данных нового бренда")
r.expectEqual(AppPaths.legacyFolderName, "Golosok", "Каталог предыдущей версии")
r.expectEqual(LegacyMigration.legacyBundleIdentifier, "kozak-developer.Golosok", "Bundle id предыдущей версии")

// Дашборд
do {
    let empty = DashboardCalculator.calculate(from: [])
    r.expectEqual(empty.totalNotes, 0, "Пустая история — 0 заметок")
    r.expectEqual(empty.hoursSaved, "0.00", "Пустая история — 0 часов")
    r.expectEqual(empty.levelName, "НОВИЧОК", "Стартовый уровень")
    r.expectEqual(empty.wpm, 0, "Пустая история — 0 wpm")
}

// Диагностика ИИ-провайдеров
do {
    let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
    let reason = AIService.describeTransportError(timeout)
    r.expect(reason.contains("тайм-аут"), "Тайм-аут прямо назван в причине сбоя")
    r.expect(reason.contains("-1001"), "Код NSURLErrorTimedOut сохранён в причине")

    let other = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
    r.expect(!AIService.describeTransportError(other).contains("тайм-аут"), "Другая сетевая ошибка не выдаётся за тайм-аут")

    let flat = AIService.parseModelIDs(["data": [["id": "gpt-6-luna"], ["id": "gemini-3.5"]]])
    r.expectEqual(flat, ["gpt-6-luna", "gemini-3.5"], "Список моделей из data[].id")
    let nested = AIService.parseModelIDs(["models": [["name": "assistant"]]])
    r.expectEqual(nested, ["assistant"], "Список моделей из models[].name")
    r.expect(AIService.parseModelIDs(["data": []]).isEmpty, "Пустой список моделей")

    let modelsFail = AIProviderCheckStage(kind: .models, ok: false, elapsedMs: 15, detail: "HTTP 404")
    let chatOK = AIProviderCheckStage(kind: .chat, ok: true, elapsedMs: 1200, detail: "генерация 4 симв.")
    let check = AIProviderCheck(baseURL: "https://example.invalid/v1", model: "m", stages: [modelsFail, chatOK])
    r.expect(check.isUsable, "Провайдер годен, если работает чат, даже без /models")
    r.expect(check.technicalSummary.contains("models: fail"), "В сводке виден сбой /models")
    r.expect(check.technicalSummary.contains("chat: ok"), "В сводке виден успех чата")
    let badChat = AIProviderCheck(baseURL: "x", model: "m", stages: [modelsFail, AIProviderCheckStage(kind: .chat, ok: false, elapsedMs: 15000, detail: "тайм-аут")])
    r.expect(!badChat.isUsable, "Провайдер не годен при сбое чата")
}

// Режим отображения логов
r.expectEqual(LogDisplayMode(rawValue: "window"), .window, "Режим отдельного окна читается из настроек")
r.expectEqual(LogDisplayMode(rawValue: "unknown"), nil, "Неизвестный режим не ломает переключатель")
r.expectEqual(LogDisplayMode.section.rawValue, "section", "Режим раздела читается из настроек")

// Экономичное хранилище аудио
do {
    let id = UUID()
    let dir = URL(fileURLWithPath: "/tmp/golosyaka-audio-storage-test")
    let resolved = AudioStorage.url(for: id, in: dir)
    r.expectEqual(resolved?.lastPathComponent, "\(id.uuidString).wav", "Без сжатого файла используется legacy WAV-путь")
    r.expectEqual(AudioStorage.audioID(from: resolved!), id, "ID записи восстанавливается из имени файла")
    r.expect(AudioStorage.audioID(from: URL(fileURLWithPath: "/tmp/not-a-uuid.wav")) == nil, "Некорректное имя файла не ломает миграцию")
    r.expectEqual(AudioStorage.compressedExtension, "m4a", "Сжатое хранилище — m4a")
    r.expectEqual(AudioStorage.aacBitrate, 24_000, "AAC 24 кбит/с")

    func appendLE(_ data: inout Data, _ value: Int, _ count: Int) {
        for i in 0..<count { data.append(UInt8((value >> (8 * i)) & 0xff)) }
    }
    func fakeWAV(dataSize: Int) -> Data {
        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8)); appendLE(&d, 36 + dataSize, 4)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); appendLE(&d, 16, 4)
        d.append(contentsOf: [1, 0, 1, 0]); appendLE(&d, 16_000, 4); appendLE(&d, 32_000, 4)
        d.append(contentsOf: [2, 0, 16, 0])
        d.append(contentsOf: Array("data".utf8)); appendLE(&d, dataSize, 4)
        if dataSize > 0 { d.append(contentsOf: [UInt8](repeating: 0, count: min(dataSize, 16))) }
        return d
    }

    r.expectEqual(AudioStorage.validate(fakeWAV(dataSize: 100), extension: "wav", totalBytes: 144), .valid,
                  "WAV с данными валиден")
    r.expectEqual(AudioStorage.validate(fakeWAV(dataSize: 0), extension: "wav", totalBytes: 44), .empty,
                  "WAV с нулевой data-частью распознаётся как пустой")
    r.expectEqual(AudioStorage.validate(Data([1, 2, 3]), extension: "wav", totalBytes: 3), .unreadable,
                  "Битый заголовок — не пустой, а нечитаемый файл")
    r.expectEqual(AudioStorage.validate(Data([1, 2, 3]), extension: "m4a", totalBytes: 2000), .valid,
                  "Для m4a валидация по заголовку не применяется")
}

exit(runner.report())
