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
        generation: Int
    ) async throws -> Bool {
        guard !Task.isCancelled else { return false }

        guard let analyzer = await MainActor.run(body: { generation == sessionGeneration ? analyzer : nil }) else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        try await prepareAnalyzerForStartIfNeeded(in: file.processingFormat)
        try Task.checkCancellation()
        await MainActor.run {
            guard !Task.isCancelled, generation == sessionGeneration else { return }
            startSpeechDetectorMonitoringIfNeeded()
        }
        try Task.checkCancellation()

        let lastAudioTime = try await analyzer.analyzeSequence(from: file)
        try Task.checkCancellation()
        if let lastAudioTime {
            try await analyzer.finalizeAndFinish(through: lastAudioTime)
        } else {
            await finishWithoutInput(generation: generation)
        }

        return !Task.isCancelled
    }
}
#endif
