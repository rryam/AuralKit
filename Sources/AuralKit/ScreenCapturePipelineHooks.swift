import AVFoundation
import Speech

/// Instance-local native boundaries. Production keeps native authorization and analysis;
/// controlled collaborators can drive the same public setup and teardown orchestration.
@available(iOS 26.0, macOS 14.0, *)
struct ScreenCapturePreparedAnalysis {
    let format: AVAudioFormat
    let inputs: AsyncStream<AnalyzerInput>.Continuation
    let finalize: @MainActor () async -> Void
}

@available(iOS 26.0, macOS 14.0, *)
struct ScreenCapturePipelineHooks {
    let authorize: @MainActor () async throws -> Void
    let prepareAnalysis: @MainActor () async throws -> ScreenCapturePreparedAnalysis
    let makeProvider: @MainActor (
        AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation, @escaping @Sendable (Error) -> Void
    ) -> any ScreenCaptureInput
}
