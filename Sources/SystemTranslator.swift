import Foundation
import NaturalLanguage
@preconcurrency import Translation

enum TranslationLanguages {
    static let english = Locale.Language(identifier: "en")
    static let simplifiedChinese = Locale.Language(identifier: "zh-Hans")
    static let traditionalChinese = Locale.Language(identifier: "zh-Hant")
}

enum SystemTranslationError: LocalizedError {
    case emptySelection
    case languageUnknown
    case languageUnsupported
    case pairingUnsupported
    case languagePackMissing
    case translationFailed

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "没有可翻译的选中文本。"
        case .languageUnknown:
            return "无法识别选中文字的语言，请选中更长的英文或中文内容。"
        case .languageUnsupported:
            return "目前仅支持英文与中文互译。"
        case .pairingUnsupported:
            return "系统翻译不支持当前语言组合。繁体中文可能尚未受支持。"
        case .languagePackMissing:
            return "缺少系统翻译语言包。请从菜单栏打开语言设置，下载所需语言包后重试。"
        case .translationFailed:
            return "系统翻译暂时失败，请重试。"
        }
    }
}

@MainActor
final class SystemTranslator {
    private var activeSession: TranslationSession?
    private var generation: UInt64 = 0

    func translate(_ text: String) async throws -> String {
        cancel()
        let currentGeneration = generation

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SystemTranslationError.emptySelection
        }

        let (source, target) = try languagePair(for: text)
        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        let status = await availability.status(from: source, to: target)
        try checkCurrent(currentGeneration)

        switch status {
        case .installed:
            break
        case .supported:
            throw SystemTranslationError.languagePackMissing
        case .unsupported:
            throw SystemTranslationError.pairingUnsupported
        @unknown default:
            throw SystemTranslationError.pairingUnsupported
        }

        let session = TranslationSession(installedSource: source,
                                         target: target,
                                         preferredStrategy: .highFidelity)
        activeSession = session
        defer {
            if generation == currentGeneration {
                activeSession = nil
            }
        }

        do {
            let response = try await session.translate(text)
            try checkCurrent(currentGeneration)
            return response.targetText
        } catch {
            try checkCurrent(currentGeneration)

            if TranslationError.notInstalled ~= error {
                throw SystemTranslationError.languagePackMissing
            }
            if TranslationError.unsupportedSourceLanguage ~= error ||
                TranslationError.unsupportedTargetLanguage ~= error ||
                TranslationError.unsupportedLanguagePairing ~= error {
                throw SystemTranslationError.pairingUnsupported
            }
            if TranslationError.unableToIdentifyLanguage ~= error {
                throw SystemTranslationError.languageUnknown
            }
            if TranslationError.nothingToTranslate ~= error {
                throw SystemTranslationError.emptySelection
            }
            if TranslationError.alreadyCancelled ~= error {
                throw CancellationError()
            }
            throw SystemTranslationError.translationFailed
        }
    }

    func cancel() {
        generation &+= 1
        activeSession?.cancel()
        activeSession = nil
    }

    private func checkCurrent(_ expectedGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == expectedGeneration else {
            throw CancellationError()
        }
    }

    private func languagePair(for text: String) throws -> (Locale.Language, Locale.Language) {
        let scriptFallback = scriptFallbackLanguage(for: text)
        // NaturalLanguage can classify a single English word as another Latin language,
        // or a common simplified Chinese phrase as traditional Chinese.
        if text.count <= 20, let scriptFallback {
            return try pair(for: scriptFallback)
        }

        let recognized = NLLanguageRecognizer.dominantLanguage(for: text)
        let language: NLLanguage
        if let recognized, recognized != .undetermined {
            language = recognized
        } else if let scriptFallback {
            language = scriptFallback
        } else {
            throw SystemTranslationError.languageUnknown
        }

        return try pair(for: language)
    }

    private func pair(for language: NLLanguage) throws -> (Locale.Language, Locale.Language) {
        switch language {
        case .english:
            return (TranslationLanguages.english, TranslationLanguages.simplifiedChinese)
        case .simplifiedChinese:
            return (TranslationLanguages.simplifiedChinese, TranslationLanguages.english)
        case .traditionalChinese:
            return (TranslationLanguages.traditionalChinese, TranslationLanguages.english)
        default:
            throw SystemTranslationError.languageUnsupported
        }
    }

    private func scriptFallbackLanguage(for text: String) -> NLLanguage? {
        var hasHan = false
        var hasLatin = false

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0x20000...0x2FA1F:
                hasHan = true
            case 0x41...0x5A, 0x61...0x7A:
                hasLatin = true
            default:
                // Do not guess if the selection contains letters from another script.
                if CharacterSet.letters.contains(scalar) {
                    return nil
                }
            }
        }

        if hasHan && !hasLatin {
            // Shared Chinese characters cannot reveal a script; prefer simplified.
            return .simplifiedChinese
        }
        if hasLatin && !hasHan {
            return .english
        }
        return nil
    }
}
