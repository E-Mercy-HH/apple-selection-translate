import SwiftUI
@preconcurrency import Translation

@MainActor
private final class LanguageSetupState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case englishToChinese
        case chineseToEnglish
        case complete

        var isPreparing: Bool {
            self == .englishToChinese || self == .chineseToEnglish
        }
    }

    @Published var phase: Phase = .idle
    @Published var configuration: TranslationSession.Configuration?
    @Published var message = "首次使用需要下载系统翻译语言包。翻译在本机完成。"
}

@MainActor
struct LanguageSetupView: View {
    private typealias Phase = LanguageSetupState.Phase
    @StateObject private var state = LanguageSetupState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("英中翻译语言包")
                .font(.headline)

            Text("准备英语与简体中文的双向翻译。系统可能会请求下载许可；语言包由 macOS 管理。")
                .fixedSize(horizontal: false, vertical: true)

            Button(state.phase == .complete ? "重新检查语言包" : "准备英中双向翻译") {
                beginPreparation()
            }
            .disabled(state.phase.isPreparing)

            if state.phase.isPreparing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
        .translationTask(state.configuration) { session in
            await prepare(using: session)
        }
        .onDisappear {
            if state.phase.isPreparing {
                state.phase = .idle
                state.configuration = nil
                state.message = "语言包准备已暂停，可重新尝试。"
            }
        }
    }

    private func beginPreparation() {
        state.phase = .englishToChinese
        state.message = "正在准备英语 → 简体中文…"
        state.configuration = TranslationSession.Configuration(
            source: TranslationLanguages.english,
            target: TranslationLanguages.simplifiedChinese,
            preferredStrategy: .highFidelity
        )
    }

    private func prepare(using session: TranslationSession) async {
        guard let source = session.sourceLanguage,
              let target = session.targetLanguage else {
            state.phase = .idle
            state.configuration = nil
            state.message = "语言设置不完整，请重试。"
            return
        }

        let requestedPhase: Phase
        if source == TranslationLanguages.english &&
            target == TranslationLanguages.simplifiedChinese {
            requestedPhase = .englishToChinese
        } else if source == TranslationLanguages.simplifiedChinese &&
                    target == TranslationLanguages.english {
            requestedPhase = .chineseToEnglish
        } else {
            state.phase = .idle
            state.configuration = nil
            state.message = "语言设置不完整，请重试。"
            return
        }
        guard state.phase == requestedPhase else { return }

        do {
            let availability = LanguageAvailability(preferredStrategy: .highFidelity)
            let status = await availability.status(from: source, to: target)
            try Task.checkCancellation()

            switch status {
            case .installed:
                break
            case .supported:
                try await session.prepareTranslation()
            case .unsupported:
                throw SystemTranslationError.pairingUnsupported
            @unknown default:
                throw SystemTranslationError.pairingUnsupported
            }

            try Task.checkCancellation()
            guard state.phase == requestedPhase else { return }

            if requestedPhase == .englishToChinese {
                state.phase = .chineseToEnglish
                state.message = "正在准备简体中文 → 英语…"
                // Replacing the configuration cancels this completed task and starts the next.
                state.configuration = TranslationSession.Configuration(
                    source: TranslationLanguages.simplifiedChinese,
                    target: TranslationLanguages.english,
                    preferredStrategy: .highFidelity
                )
                return
            }

            if requestedPhase == .chineseToEnglish {
                let englishToChinese = await availability.status(
                    from: TranslationLanguages.english,
                    to: TranslationLanguages.simplifiedChinese
                )
                let chineseToEnglish = await availability.status(
                    from: TranslationLanguages.simplifiedChinese,
                    to: TranslationLanguages.english
                )
                try Task.checkCancellation()
                guard state.phase == requestedPhase else { return }

                state.phase = .complete
                state.configuration = nil
                if englishToChinese == .installed && chineseToEnglish == .installed {
                    state.message = "英中双向翻译已就绪。"
                } else {
                    state.message = "已请求下载语言包。系统完成安装后即可使用翻译。"
                }
            }
        } catch is CancellationError {
            // Ignore SwiftUI's cancellation of a replaced or disappearing view.
            guard state.phase == requestedPhase, !Task.isCancelled else { return }
            state.phase = .idle
            state.configuration = nil
            state.message = "已取消语言包准备，可再次尝试。"
        } catch {
            guard state.phase == requestedPhase else { return }
            state.phase = .idle
            state.configuration = nil
            state.message = "准备语言包失败：\(error.localizedDescription)"
        }
    }
}
