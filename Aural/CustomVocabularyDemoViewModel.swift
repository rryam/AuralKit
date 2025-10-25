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

        transcriptionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream: AsyncThrowingStream<DictationTranscriber.Result, Error>
                let startTime = Date()

                if self.isCustomVocabularyEnabled {
                    guard let descriptor = self.buildDescriptor() else {
                        self.errorMessage = "Please provide at least one phrase."
                        return
                    }

                    self.isCompiling = true
                    defer { self.isCompiling = false }
                    stream = try await self.session.startTranscribing(
                        customVocabulary: descriptor,
                        contextualStrings: self.buildContextualStrings()
                    )
                    self.compilationDuration = Date().timeIntervalSince(startTime)
                    self.cacheKey = try? descriptor.stableCacheKey()
                } else {
                    stream = self.session.startDictationTranscribing(
                        contextualStrings: self.buildContextualStrings()
                    )
                }

                self.monitorDownloadProgress()

                for try await result in stream {
                    self.applyDictationResult(result)
                }
            } catch is CancellationError {
                // expected when stopped
            } catch {
                self.errorMessage = error.localizedDescription
                self.isCompiling = false
            }

            self.progressTask?.cancel()
            self.progressTask = nil
            self.resetProgressObservation(clearFraction: true)
            self.transcriptionTask = nil
        }
    }

    func stopTranscription() {
        progressTask?.cancel()
        progressTask = nil
        resetProgressObservation(clearFraction: true)
        transcriptionTask?.cancel()
        transcriptionTask = nil

        Task { [weak self] in
            guard let self else { return }
            await self.session.stopTranscribing()
            self.partialText = ""
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
        statusTask = Task { [weak self] in
            guard let self else { return }
            for await newStatus in self.session.statusStream {
                await MainActor.run {
                    self.status = newStatus
                }
            }
        }
    }

    private func monitorDownloadProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let progress = self.session.modelDownloadProgress {
                    self.track(progress)
                } else {
                    self.resetProgressObservation(clearFraction: true)
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
            Task { @MainActor [weak self] in
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
