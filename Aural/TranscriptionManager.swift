import SwiftUI
import AuralKit
import CoreMedia

@Observable
@MainActor
class TranscriptionManager {
    var isTranscribing = false
    var volatileText: AttributedString = ""
    var finalizedText: AttributedString = ""
    var transcriptionHistory: [TranscriptionRecord] = []
    var selectedLocale: Locale = .current
    var error: String?
    var currentTimeRange = ""

    private var transcriptionTask: Task<Void, Never>?
    private var speechSession: SpeechSession?

    init() {}

    var fullTranscript: AttributedString {
        finalizedText + volatileText
    }

    var currentTranscript: String {
        String(fullTranscript.characters)
    }
    
    func startTranscription() {
        guard !isTranscribing else { return }

        isTranscribing = true
        error = nil
        volatileText = ""
        finalizedText = ""
        currentTimeRange = ""
        
        // Create configured SpeechSession instance
        speechSession = SpeechSession(locale: selectedLocale)

        transcriptionTask = Task {
            do {
                guard let speechSession = speechSession else { return }

                for try await result in speechSession.startTranscribing() {
                    await MainActor.run {
                        handleTranscriptionResult(result)
                    }
                }
            } catch let error as NSError {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isTranscribing = false
                }
            }
        }
    }
    
    private func handleTranscriptionResult(_ result: TranscriptionResult) {
        if result.isFinal {
            // Final text - append to finalized transcript (preserving timing metadata)
            finalizedText += result.text
            volatileText = ""
        } else {
            // Volatile (partial) text - replace previous partial
            var styledText = result.text
            styledText.foregroundColor = .purple.opacity(0.4)
            volatileText = styledText
        }

        // Extract time range from AttributedString if available
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
        guard isTranscribing else { return }
        
        transcriptionTask?.cancel()
        Task {
            await speechSession?.stopTranscribing()
        }
        isTranscribing = false
        
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
    }
    
    func toggleTranscription() {
        if isTranscribing {
            stopTranscription()
        } else {
            startTranscription()
        }
    }
    
    func clearHistory() {
        transcriptionHistory.removeAll()
    }
    
    func deleteRecord(_ record: TranscriptionRecord) {
        transcriptionHistory.removeAll { $0.id == record.id }
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
