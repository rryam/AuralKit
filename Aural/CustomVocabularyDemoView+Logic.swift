import SwiftUI
import AuralKit
import Speech
import CryptoKit

extension CustomVocabularyDemoView {
    func startTranscription() {
        guard status != .transcribing, status != .preparing else { return }

        errorMessage = nil
        finalText = ""
        partialText = ""
        cacheKey = nil
        compilationDuration = nil

        transcriptionTask?.cancel()
        progressTask?.cancel()

        transcriptionTask = Task { @MainActor in
            do {
                let stream: AsyncThrowingStream<DictationTranscriber.Result, Error>
                let startTime = Date()

                if isCustomVocabularyEnabled {
                    guard let descriptor = buildDescriptor() else {
                        errorMessage = "Please provide at least one phrase."
                        return
                    }

                    isCompiling = true
                    defer { isCompiling = false }
                    stream = try await session.startTranscribing(
                        customVocabulary: descriptor,
                        contextualStrings: buildContextualStrings()
                    )
                    compilationDuration = Date().timeIntervalSince(startTime)
                    cacheKey = cacheKey(for: descriptor)
                } else {
                    stream = session.startDictationTranscribing(
                        contextualStrings: buildContextualStrings()
                    )
                }

                monitorDownloadProgress()

                for try await result in stream {
                    applyDictationResult(result)
                }
            } catch is CancellationError {
                // expected on stop
            } catch {
                errorMessage = error.localizedDescription
                isCompiling = false
            }

            progressTask?.cancel()
            progressTask = nil
            progressObserver.reset()
            transcriptionTask = nil
        }
    }

    func stopTranscription() {
        progressTask?.cancel()
        progressTask = nil
        progressObserver.reset()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        Task { @MainActor in
            await session.stopTranscribing()
            partialText = ""
        }
    }

    func monitorDownloadProgress() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                if let progress = session.modelDownloadProgress {
                    progressObserver.track(progress)
                } else {
                    progressObserver.reset()
                }
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    break
                }
            }
        }
    }

    func buildDescriptor() -> SpeechSession.CustomVocabulary? {
        let cleanedPhrases = phrases
            .map { $0.normalized }
            .filter { !$0.text.isEmpty }
        guard !cleanedPhrases.isEmpty else { return nil }

        let cleanedPronunciations = pronunciations
            .map { $0.normalized }
            .filter { !$0.grapheme.isEmpty && !$0.phonemes.isEmpty }

        let descriptor = SpeechSession.CustomVocabulary(
            locale: locale,
            identifier: vocabularyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            version: vocabularyVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            weight: vocabularyWeight,
            phrases: cleanedPhrases.map { .init(text: $0.text, count: $0.count) },
            pronunciations: cleanedPronunciations.map { .init(grapheme: $0.grapheme, phonemes: $0.phonemes) }
        )

        return descriptor
    }

    func buildContextualStrings() -> [AnalysisContext.ContextualStringsTag: [String]]? {
        let tokens = contextualTerms
            .split { $0 == "," || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }
        return [.general: tokens]
    }

    func applyDictationResult(_ result: DictationTranscriber.Result) {
        if result.isFinal {
            finalText += result.text
            partialText = ""
        } else {
            partialText = result.text
        }
    }
}

// MARK: - Helpers

extension CustomVocabularyDemoView {
    var statusTitle: String {
        switch status {
        case .idle: return "Idle"
        case .preparing: return "Preparing"
        case .transcribing: return "Transcribing"
        case .paused: return "Paused"
        case .stopping: return "Stopping"
        }
    }

    var startButtonTitle: String {
        status == .transcribing || status == .preparing ? "Starting…" : "Start"
    }

    var startButtonIcon: String {
        status == .transcribing || status == .preparing ? "hourglass" : "play.fill"
    }

    func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .font(.footnote)
        }
    }

    func cacheKey(for descriptor: SpeechSession.CustomVocabulary) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(descriptor) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
