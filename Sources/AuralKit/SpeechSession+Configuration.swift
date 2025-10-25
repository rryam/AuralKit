import Foundation
import Speech
#if os(iOS)
@preconcurrency import AVFoundation
#endif

public extension SpeechSession {

    /// Default reporting options: provides partial results and alternative transcriptions.
    static let defaultReportingOptions: Set<SpeechTranscriber.ReportingOption> = [
        .volatileResults,
        .alternativeTranscriptions
    ]

    /// Default attribute options: includes timing and confidence metadata.
    static let defaultAttributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = [
        .audioTimeRange,
        .transcriptionConfidence
    ]

#if os(iOS)
    /// Declarative wrapper describing how `SpeechSession` should configure `AVAudioSession` on iOS.
    struct AudioSessionConfiguration: Sendable {
        /// High-level audio category applied before starting capture.
        public let category: AVAudioSession.Category
        /// Audio session mode (for example `.spokenAudio`).
        public let mode: AVAudioSession.Mode
        /// Additional session options such as `.duckOthers` or `.allowBluetooth`.
        public let options: AVAudioSession.CategoryOptions

        /// Creates a new configuration.
        /// - Parameters correspond directly to the stored properties and default to values tuned for speech capture.
        public init(
            category: AVAudioSession.Category = .playAndRecord,
            mode: AVAudioSession.Mode = .spokenAudio,
            options: AVAudioSession.CategoryOptions = .duckOthers
        ) {
            self.category = category
            self.mode = mode
            self.options = options
        }

        /// Default configuration used when a custom one is not provided.
        public static let `default` = AudioSessionConfiguration()
    }
#endif
}
