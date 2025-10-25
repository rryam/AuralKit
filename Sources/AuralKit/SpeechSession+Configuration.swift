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
    /// Audio session configuration for iOS.
    struct AudioSessionConfiguration: Sendable {
        public let category: AVAudioSession.Category
        public let mode: AVAudioSession.Mode
        public let options: AVAudioSession.CategoryOptions

        public init(
            category: AVAudioSession.Category = .playAndRecord,
            mode: AVAudioSession.Mode = .spokenAudio,
            options: AVAudioSession.CategoryOptions = .duckOthers
        ) {
            self.category = category
            self.mode = mode
            self.options = options
        }

        public static let `default` = AudioSessionConfiguration()
    }
#endif
}