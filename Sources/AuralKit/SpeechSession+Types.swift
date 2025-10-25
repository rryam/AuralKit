import Foundation
import AVFoundation
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

    enum TranscriptionResultKind: Equatable, Sendable {
        case speech
        case dictation
    }

    enum TranscriptionContinuation {
        case speech(AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation)
        case dictation(AsyncThrowingStream<DictationTranscriber.Result, Error>.Continuation)
    }

    struct VoiceActivationConfiguration {
        let detectionOptions: SpeechDetector.DetectionOptions
        let reportResults: Bool
    }

    struct SendablePCMBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }
}
