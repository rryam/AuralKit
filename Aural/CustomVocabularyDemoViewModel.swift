import SwiftUI
import Observation
import AuralKit
import Speech
import CoreMedia

@MainActor
@Observable
final class CustomVocabularyDemoViewModel {

    // MARK: - Published state

    var status: SpeechSession.Status = .idle
    var finalText: AttributedString = ""
    var partialText: AttributedString = ""
    var errorMessage: String?
    var currentTimeRange: String = ""
    var isCustomVocabularyEnabled: Bool = true
    var vocabularyIdentifier: String = "tech-demo"
    var vocabularyVersion: String = "1"
    var vocabularyWeight: Double = 0.6
    var phrases: [CustomVocabularyPhrase] = CustomVocabularyPreset.techDemo.phrases
    var pronunciations: [CustomVocabularyPronunciation] = CustomVocabularyPreset.techDemo.pronunciations
    var contextualTerms: String = "WebAssembly, TensorFlow, Kubernetes"
    var phrasesEnabled: Bool = true
    var contextualStringsEnabled: Bool = true
    var isCompiling: Bool = false
    var cacheKey: String?
    var compilationDuration: TimeInterval?
    var progressFraction: Double?

    // MARK: - Private state

    private let locale = Locale(identifier: "en_US")
    @ObservationIgnored private let session: SpeechSession
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private weak var trackedProgress: Progress?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?

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

        resetTranscriptionState()
        cancelExistingTasks()

        transcriptionTask = Task { @MainActor in
            do {
                let stream = try await prepareTranscriptionStream()
                monitorDownloadProgress()
                try await processTranscriptionStream(stream)
            } catch is CancellationError {
                // expected when stopped
            } catch {
                errorMessage = error.localizedDescription
                isCompiling = false
            }

            cleanupTasks()
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
            currentTimeRange = ""
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
        let cleanedPhrases = phrasesEnabled ? phrases
            .map { $0.normalized }
            .filter { !$0.text.isEmpty } : []
        if phrasesEnabled && cleanedPhrases.isEmpty {
            return nil
        }

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
        guard contextualStringsEnabled else { return nil }

        let tokens = contextualTerms
            .split { $0 == "," || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }
        return [.general: tokens]
    }

    private func applyDictationResult(_ result: DictationTranscriber.Result) {
        print("Received dictation result: \(result.text) (isFinal: \(result.isFinal))")
        if result.isFinal {
            finalText += result.text
            partialText = ""
        } else {
            partialText = result.text
            partialText.foregroundColor = Color.primary.opacity(0.4)
        }

        currentTimeRange = ""
        result.text.runs.forEach { run in
            if let range = run.audioTimeRange {
                let start = formatTime(range.start)
                let end = formatTime(range.end)
                currentTimeRange = "\(start) - \(end)"
            }
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = time.seconds
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, remainingSeconds, milliseconds)
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

// MARK: - Transcription Helpers
extension CustomVocabularyDemoViewModel {
    private func resetTranscriptionState() {
        errorMessage = nil
        finalText = ""
        partialText = ""
        currentTimeRange = ""
        cacheKey = nil
        compilationDuration = nil
    }

    private func cancelExistingTasks() {
        transcriptionTask?.cancel()
        progressTask?.cancel()
    }

    private func prepareTranscriptionStream() async throws -> AsyncThrowingStream<DictationTranscriber.Result, Error> {
        let startTime = Date()

        if isCustomVocabularyEnabled {
            guard let descriptor = buildDescriptor() else {
                let error = NSError(
                    domain: "CustomVocabularyDemoViewModel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Please provide at least one phrase."]
                )
                throw SpeechSessionError.customVocabularyCompilationFailed(error)
            }

            isCompiling = true
            defer { isCompiling = false }
            let stream = try await session.startTranscribing(
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
            return stream
        } else {
            return session.startDictationTranscribing(
                contextualStrings: buildContextualStrings()
            )
        }
    }

    private func processTranscriptionStream(
        _ stream: AsyncThrowingStream<DictationTranscriber.Result, Error>
    ) async throws {
        for try await result in stream {
            applyDictationResult(result)
        }
    }

    private func cleanupTasks() {
        progressTask?.cancel()
        progressTask = nil
        resetProgressObservation(clearFraction: true)
        transcriptionTask = nil
    }
}
