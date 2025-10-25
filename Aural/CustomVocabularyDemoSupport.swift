import Foundation
import SwiftUI

struct CustomVocabularyPhrase: Identifiable {
    let id = UUID()
    var text: String
    var count: Int

    var normalized: CustomVocabularyPhrase {
        CustomVocabularyPhrase(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            count: max(1, count)
        )
    }
}

struct CustomVocabularyPronunciation: Identifiable {
    let id = UUID()
    var grapheme: String
    var phonemes: [String]

    var phonemeText: String {
        get { phonemes.joined(separator: " ") }
        set {
            phonemes = newValue
                .split(separator: " ")
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }
        }
    }

    init(grapheme: String, phonemes: [String]) {
        self.grapheme = grapheme
        self.phonemes = phonemes
    }

    var normalized: CustomVocabularyPronunciation {
        let cleanedGrapheme = grapheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPhonemes = phonemes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return CustomVocabularyPronunciation(grapheme: cleanedGrapheme, phonemes: cleanedPhonemes)
    }
}

enum CustomVocabularyPreset {
    case techDemo

    var phrases: [CustomVocabularyPhrase] {
        switch self {
        case .techDemo:
            return [
                .init(text: "WebAssembly", count: 6),
                .init(text: "GraphQL subscription", count: 4),
                .init(text: "TensorFlow Lite", count: 5),
                .init(text: "Zero-knowledge proof", count: 4)
            ]
        }
    }

    var pronunciations: [CustomVocabularyPronunciation] {
        switch self {
        case .techDemo:
            return [
                .init(grapheme: "GraphQL", phonemes: ["gɹæf", "kju", "ɛl"]),
                .init(grapheme: "WebAssembly", phonemes: ["wɛb", "ə", "sɛm", "bli"])
            ]
        }
    }
}

@MainActor
final class CustomVocabularyProgressObserver: ObservableObject {
    @Published var progressFraction: Double?
    private var observation: NSKeyValueObservation?
    private weak var trackedProgress: Progress?

    func track(_ progress: Progress) {
        guard trackedProgress !== progress else { return }

        observation?.invalidate()
        trackedProgress = progress
        progressFraction = progress.fractionCompleted

        observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.progressFraction = progress.fractionCompleted
            }
        }
    }

    func reset() {
        observation?.invalidate()
        observation = nil
        trackedProgress = nil
        progressFraction = nil
    }
}
