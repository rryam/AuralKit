import SwiftUI
import AuralKit
import Speech

@MainActor
final class CustomVocabularyDemoViewModel: ObservableObject {

    // MARK: - Published state

    @Published var status: SpeechSession.Status = .idle
    @Published var finalText: AttributedString = ""
    @Published var partialText: AttributedString = ""
    @Published var errorMessage: String?
    @Published var isCustomVocabularyEnabled: Bool = true
    @Published var vocabularyIdentifier: String = "tech-demo"
    @Published var vocabularyVersion: String = "1"
    @Published var vocabularyWeight: Double = 0.6
    @Published var phrases: [CustomVocabularyPhrase] = CustomVocabularyPreset.techDemo.phrases
    @Published var pronunciations: [CustomVocabularyPronunciation] = CustomVocabularyPreset.techDemo.pronunciations
    @Published var contextualTerms: String = "WebAssembly, TensorFlow, Kubernetes"
    @Published var isCompiling: Bool = false
    @Published var cacheKey: String?
    @Published var compilationDuration: TimeInterval?
    @Published var progressFraction: Double?

    // MARK: - Private state

    private let locale = Locale(identifier: "en_US")
    private let session: SpeechSession
    private var statusTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private weak var trackedProgress: Progress?
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Init / Deinit

    init(session: SpeechSession = SpeechSession()) {
        self.session = session
        bindStatusStream()
    }

    deinit {
        statusTask?.cancel()
        progressTask?.cancel()
        transcriptionTask?.cancel()
        progressObservation?.invalidate()
    }

    // MARK: - Intent Handlers

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
                    do {
                        cacheKey = try descriptor.stableCacheKey()
                    } catch {
                        cacheKey = nil
                        errorMessage = "Failed to compute cache key: \(error.localizedDescription)"
                    }
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
                // expected when stopped
            } catch {
                errorMessage = error.localizedDescription
                isCompiling = false
            }

            progressTask?.cancel()
            progressTask = nil
            resetProgressObservation(clearFraction: true)
            transcriptionTask = nil
        }
    }

    func stopTranscription() {
        progressTask?.cancel()
        progressTask = nil
        resetProgressObservation(clearFraction: true)
        transcriptionTask?.cancel()
        transcriptionTask = nil

        Task { @MainActor in
            await session.stopTranscribing()
            partialText = ""
        }
    }

    func pauseTranscription() {
        Task { @MainActor in
            await session.pauseTranscribing()
        }
    }

    func resumeTranscription() {
        Task { @MainActor in
            do {
                try await session.resumeTranscribing()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleToggleChange(_ isEnabled: Bool) {
        isCustomVocabularyEnabled = isEnabled
        if !isEnabled, status == .transcribing || status == .preparing {
            stopTranscription()
        }
    }

    func resetToPreset() {
        phrases = CustomVocabularyPreset.techDemo.phrases
        pronunciations = CustomVocabularyPreset.techDemo.pronunciations
        vocabularyIdentifier = "tech-demo"
        vocabularyVersion = "1"
        vocabularyWeight = 0.6
    }

    func teardown() {
        stopTranscription()
        statusTask?.cancel()
        statusTask = nil
    }

    // MARK: - Derived State

    var statusTitleText: String {
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

    var isStartDisabled: Bool {
        isCompiling || status == .preparing || status == .transcribing
    }

    var isStopDisabled: Bool {
        status == .idle || status == .stopping
    }

    // MARK: - Private helpers

    private func bindStatusStream() {
        statusTask?.cancel()
        statusTask = Task { @MainActor in
            for await newStatus in session.statusStream {
                status = newStatus
            }
        }
    }

    private func monitorDownloadProgress() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                if let progress = session.modelDownloadProgress {
                    track(progress)
                } else {
                    resetProgressObservation(clearFraction: true)
                }

                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    break
                }
            }
        }
    }

    private func buildDescriptor() -> SpeechSession.CustomVocabulary? {
        let cleanedPhrases = phrases
            .map { $0.normalized }
            .filter { !$0.text.isEmpty }
        guard !cleanedPhrases.isEmpty else { return nil }

        let cleanedPronunciations = pronunciations
            .map { $0.normalized }
            .filter { !$0.grapheme.isEmpty && !$0.phonemes.isEmpty }

        return SpeechSession.CustomVocabulary(
            locale: locale,
            identifier: vocabularyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            version: vocabularyVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            weight: vocabularyWeight,
            phrases: cleanedPhrases.map { .init(text: $0.text, count: $0.count) },
            pronunciations: cleanedPronunciations.map { .init(grapheme: $0.grapheme, phonemes: $0.phonemes) }
        )
    }

    private func buildContextualStrings() -> [AnalysisContext.ContextualStringsTag: [String]]? {
        let tokens = contextualTerms
            .split { $0 == "," || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }
        return [.general: tokens]
    }

    private func applyDictationResult(_ result: DictationTranscriber.Result) {
        if result.isFinal {
            finalText += result.text
            partialText = ""
        } else {
            partialText = result.text
        }
    }

    private func track(_ progress: Progress) {
        guard trackedProgress !== progress else { return }

        progressObservation?.invalidate()
        trackedProgress = progress
        progressFraction = progress.fractionCompleted

        progressObservation = progress.observe(
            \.fractionCompleted,
            options: [.initial, .new]
        ) { [weak self] progress, _ in
            Task { @MainActor in
                self?.progressFraction = progress.fractionCompleted
            }
        }
    }

    private func resetProgressObservation(clearFraction: Bool) {
        progressObservation?.invalidate()
        progressObservation = nil
        trackedProgress = nil
        if clearFraction {
            progressFraction = nil
        }
    }
}
