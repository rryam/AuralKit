import Testing
@testable import AuralKit

@Suite("SpeechSession State")
struct SpeechSessionStateTests {

    @Test("Model download progress starts nil")
    @MainActor
    func modelDownloadProgressStartsNil() {
        let session = SpeechSession()
        #expect(session.modelDownloadProgress == nil)
    }

    @Test("Stop transcribing without session is a no-op")
    @MainActor
    func stopTranscribingWithoutSessionIsNoOp() async {
        let session = SpeechSession()
        await session.stopTranscribing()
        #expect(session.modelDownloadProgress == nil)
        #expect(session.status == .idle)
    }
}

@Suite("SpeechSession Voice Activation")
struct SpeechSessionVoiceActivationTests {

    @Test("Voice activation configuration toggles state")
    @MainActor
    func voiceActivationConfigurationTogglesState() {
        let session = SpeechSession()
        #expect(session.isVoiceActivationEnabled == false)
        #expect(session.speechDetectorResultsStream == nil)
        #expect(session.isSpeechDetected == true)

        session.configureVoiceActivation(reportResults: true)
        #expect(session.isVoiceActivationEnabled == true)
        #expect(session.speechDetectorResultsStream != nil)
        #expect(session.isSpeechDetected == true)

        session.disableVoiceActivation()
        #expect(session.isVoiceActivationEnabled == false)
        #expect(session.speechDetectorResultsStream == nil)
        #expect(session.isSpeechDetected == true)
    }
}

@Suite("SpeechSession Logging")
struct SpeechSessionLoggingTests {

    @Test("Logging level can be configured globally", arguments: SpeechSession.LogLevel.allCases)
    @MainActor
    func loggingLevelRoundTrips(level: SpeechSession.LogLevel) async {
        await SpeechSessionLoggingLock.shared.withLock {
            let originalLevel = SpeechSession.logging
            defer { SpeechSession.logging = originalLevel }

            SpeechSession.logging = level

            #expect(SpeechSession.logging == level)
        }
    }
}

private actor SpeechSessionLoggingLock {
    static let shared = SpeechSessionLoggingLock()

    func withLock(_ body: @MainActor @Sendable () throws -> Void) async rethrows {
        try await body()
    }
}
