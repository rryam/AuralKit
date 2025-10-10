import SwiftUI
import AuralKit
import CoreMedia
import Speech

@Observable
@MainActor
class TranscriptionManager {
    var status: SpeechSession.Status = .idle
    var volatileText: AttributedString = ""
    var finalizedText: AttributedString = ""
    var transcriptionHistory: [TranscriptionRecord] = []
    var selectedLocale: Locale = .current
    var error: String?
    var currentTimeRange = ""

    private var transcriptionTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var speechSession: SpeechSession?

    init() {}

    var fullTranscript: AttributedString {
        finalizedText + volatileText
    }

    var currentTranscript: String {
        String(fullTranscript.characters)
    }

    var isTranscribing: Bool {
        status == .transcribing
    }
    
    func startTranscription() {
        guard status == .idle else { return }

        error = nil
        volatileText = ""
        finalizedText = ""
        currentTimeRange = ""

        let session = SpeechSession(locale: selectedLocale)
        speechSession = session
        observeStatus(from: session)

        transcriptionTask = Task { @MainActor in
            do {
                for try await result in session.startTranscribing() {
                    self.handleTranscriptionResult(result)
                }
                self.finishSession()
            } catch is CancellationError {
                self.cleanupSession()
            } catch {
                self.error = error.localizedDescription
                self.finishSession()
            }
        }
    }

    private func observeStatus(from session: SpeechSession) {
        statusTask?.cancel()
        statusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = session.statusStream
            for await newStatus in stream {
                self.status = newStatus
            }
        }
    }

    private func handleTranscriptionResult(_ result: SpeechTranscriber.Result) {
        result.apply(
            to: &finalizedText,
            partialText: &volatileText,
            partialStyler: { $0.foregroundColor = Color.purple.opacity(0.4) }
        )

        currentTimeRange = ""
        result.text.runs.forEach { run in
            if let audioRange = run.audioTimeRange {
                let start = formatTime(audioRange.start)
                let end = formatTime(audioRange.end)
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
    
    func stopTranscription() {
        guard status != .idle, status != .stopping else { return }
        Task { @MainActor in
            await self.speechSession?.stopTranscribing()
        }
    }

    func pauseTranscription() {
        guard status == .transcribing else { return }
        Task { @MainActor in
            await self.speechSession?.pauseTranscribing()
        }
    }

    func resumeTranscription() {
        guard status == .paused else { return }
        error = nil
        Task { @MainActor in
            do {
                try await self.speechSession?.resumeTranscribing()
            } catch {
                self.error = error.localizedDescription
                self.finishSession()
            }
        }
    }

    func primaryAction() {
        switch status {
        case .idle:
            startTranscription()
        case .preparing:
            stopTranscription()
        case .transcribing:
            pauseTranscription()
        case .paused:
            resumeTranscription()
        case .stopping:
            break
        }
    }

    func toggleTranscription() {
        primaryAction()
    }

    func clearHistory() {
        transcriptionHistory.removeAll()
    }
    
    func deleteRecord(_ record: TranscriptionRecord) {
        transcriptionHistory.removeAll { $0.id == record.id }
    }

    private func finishSession() {
        if !currentTranscript.isEmpty {
            let record = TranscriptionRecord(
                id: UUID(),
                text: currentTranscript,
                locale: selectedLocale,
                timestamp: Date(),
                alternatives: [],
                timeRange: currentTimeRange
            )
            transcriptionHistory.insert(record, at: 0)
        }

        cleanupSession()
    }

    private func cleanupSession() {
        volatileText = ""
        currentTimeRange = ""
        transcriptionTask = nil
        statusTask?.cancel()
        statusTask = nil
        speechSession = nil
        status = .idle
    }
}

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let text: String
    let localeIdentifier: String
    let timestamp: Date
    let alternatives: [String]
    let timeRange: String
    
    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
    
    init(id: UUID, text: String, locale: Locale, timestamp: Date, alternatives: [String] = [], timeRange: String = "") {
        self.id = id
        self.text = text
        self.localeIdentifier = locale.identifier
        self.timestamp = timestamp
        self.alternatives = alternatives
        self.timeRange = timeRange
    }
}

extension SpeechTranscriber.Result {
    func apply(
        to finalText: inout AttributedString,
        partialText: inout AttributedString,
        partialStyler: ((inout AttributedString) -> Void)? = nil
    ) {
        if isFinal {
            finalText += text
            partialText = ""
        } else {
            var styledText = text
            partialStyler?(&styledText)
            partialText = styledText
        }
    }
}
