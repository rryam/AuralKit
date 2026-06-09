import Foundation
import AVFoundation
import Speech

extension SpeechSession {
    func prepareAnalyzerForStartIfNeeded(in audioFormat: AVAudioFormat?) async throws {
#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            try await prepareNativeAnalyzerForStart(in: audioFormat)
        }
#endif
    }
}

#if swift(>=6.4)
@available(iOS 27.0, macOS 27.0, *)
extension SpeechSession.AnalyzerConfiguration {
    var nativeOptions: SpeechAnalyzer.Options {
        SpeechAnalyzer.Options(
            priority: priority,
            modelRetention: modelRetention.nativeValue
        )
    }
}

@available(iOS 27.0, macOS 27.0, *)
extension SpeechSession.AnalyzerModelRetention {
    var nativeValue: SpeechAnalyzer.Options.ModelRetention {
        switch self {
        case .whileInUse:
            return .whileInUse
        case .lingering:
            return .lingering
        case .processLifetime:
            return .processLifetime
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
extension SpeechSession {
    func prepareNativeAnalyzerForStart(in audioFormat: AVAudioFormat?) async throws {
        guard analyzerConfiguration.preparesAnalyzerBeforeStart, let analyzer else {
            return
        }

        try await analyzer.prepareToAnalyze(in: audioFormat)
    }
}
#endif
