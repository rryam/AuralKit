import Speech

enum DemoTranscriberPreset: String, CaseIterable, Identifiable {
    case manual
    case transcription
    case transcriptionWithAlternatives
    case progressive
    case timeIndexedProgressive

    var id: Self { self }

    var displayName: String {
        switch self {
        case .manual:
            return "AuralKit Default"
        case .transcription:
            return "Transcription"
        case .transcriptionWithAlternatives:
            return "Transcription + Alternatives"
        case .progressive:
            return "Progressive"
        case .timeIndexedProgressive:
            return "Progressive + Timecodes"
        }
    }

    var preset: SpeechTranscriber.Preset? {
        switch self {
        case .manual:
            return nil
        case .transcription:
            return .transcription
        case .transcriptionWithAlternatives:
            return .transcriptionWithAlternatives
        case .progressive:
            return .progressiveTranscription
        case .timeIndexedProgressive:
            return .timeIndexedProgressiveTranscription
        }
    }
}
