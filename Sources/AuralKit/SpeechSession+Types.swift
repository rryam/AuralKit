import Foundation
import Speech

extension SpeechSession {

    /// Discrete lifecycle stages for a speech transcription session.
    public enum Status: Equatable, Sendable {
        case idle
        case preparing
        case transcribing
        case paused
        case stopping
    }

    /// Discrete source types currently feeding the analyzer pipeline.
    enum StreamingMode: Equatable, Sendable {
        case inactive
        case liveMicrophone
        case filePlayback
    }

    struct VoiceActivationConfiguration {
        let detectionOptions: SpeechDetector.DetectionOptions
        let reportResults: Bool
    }
}
