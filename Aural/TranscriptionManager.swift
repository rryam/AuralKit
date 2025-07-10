import SwiftUI
import AuralKit
import CoreMedia

@available(iOS 26.0, macOS 26.0, *)
@Observable
class TranscriptionManager {
    var isTranscribing = false
    var currentTranscript = ""
    var volatileText = ""
    var finalizedText = ""
    var transcriptionHistory: [TranscriptionRecord] = []
    var selectedLocale: Locale = .current
    var error: String?
    var currentTimeRange = ""
    
    private var transcriptionTask: Task<Void, Never>?
    private var auralKit: AuralKit?
    
    init() {}
    
    var fullTranscript: String {
        finalizedText + (volatileText.isEmpty ? "" : " " + volatileText)
    }
    
    func startTranscription() {
        guard !isTranscribing else { return }
        
        isTranscribing = true
        error = nil
        currentTranscript = ""
        volatileText = ""
        finalizedText = ""
        currentAlternatives = []
        currentTimeRange = ""
        
        
        // Create configured AuralKit instance
        auralKit = AuralKit(locale: selectedLocale)
        
        transcriptionTask = Task {
            do {
                guard let auralKit = auralKit else { return }
                
                for try await attributedText in auralKit.startTranscribing() {
                    await MainActor.run {
                        handleTranscriptionResult(attributedText)
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
    
    private func handleTranscriptionResult(_ attributedText: AttributedString) {
        // Check if this is volatile (partial) or final text
        let isVolatile = attributedText.runs.contains { run in
            run.foregroundColor != nil
        }
        
        let text = String(attributedText.characters)
        
        if !isVolatile {
            // Final text
            finalizedText = text
            volatileText = ""
        } else {
            // Volatile text - extract only the new part
            let finalizedLength = finalizedText.count
            if text.count > finalizedLength {
                let index = text.index(text.startIndex, offsetBy: finalizedLength)
                volatileText = String(text[index...])
            } else {
                volatileText = text
            }
        }
        currentTranscript = fullTranscript
        
        // Extract time range from AttributedString if available
        currentTimeRange = ""
        attributedText.runs.forEach { run in
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
            await auralKit?.stopTranscribing()
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
