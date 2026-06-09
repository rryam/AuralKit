import Foundation
import AVFoundation
import Speech

#if swift(>=6.4)
@available(iOS 27.0, macOS 27.0, *)
extension SpeechSession {
    nonisolated var shouldUseNativeAssetInputProvider: Bool {
        get async {
            await MainActor.run {
                inputProviderPreference == .automatic
            }
        }
    }

    nonisolated func feedAudioFileWithNativeAnalyzer(
        _ file: AVAudioFile,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> Bool {
        guard !Task.isCancelled else { return false }

        if let progressHandler {
            await MainActor.run {
                progressHandler(0.0)
            }
        }

        guard let analyzer = await MainActor.run(body: { analyzer }) else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        let lastAudioTime = try await analyzer.analyzeSequence(from: file)
        if let lastAudioTime {
            try await analyzer.finalizeAndFinish(through: lastAudioTime)
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        return !Task.isCancelled
    }
}
#endif
