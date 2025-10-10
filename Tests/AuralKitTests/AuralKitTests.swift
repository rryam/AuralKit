import Testing
@testable import AuralKit

@Suite("AuralKit")
struct AuralKitTests {

    @Test("Model download progress starts nil")
    @MainActor
    func testInitialDownloadProgressIsNil() {
        let kit = SpeechSession()
        #expect(kit.modelDownloadProgress == nil)
    }

    @Test("Stop transcribing without session is a no-op")
    @MainActor
    func testStopWithoutSession() async {
        let kit = SpeechSession()
        await kit.stopTranscribing()
        #expect(kit.modelDownloadProgress == nil)
    }

    @Test("Voice activation configuration updates state")
    @MainActor
    func testVoiceActivationConfiguration() {
        let kit = SpeechSession()
        #expect(kit.isVoiceActivationEnabled == false)
        #expect(kit.speechDetectorResultsStream == nil)
        #expect(kit.isSpeechDetected == true)

        kit.configureVoiceActivation(reportResults: true)
        #expect(kit.isVoiceActivationEnabled == true)
        #expect(kit.speechDetectorResultsStream != nil)
        #expect(kit.isSpeechDetected == true)

        kit.disableVoiceActivation()
        #expect(kit.isVoiceActivationEnabled == false)
        #expect(kit.speechDetectorResultsStream == nil)
        #expect(kit.isSpeechDetected == true)
    }

    @Test("Logging level can be configured globally")
    @MainActor
    func testLoggingLevelConfiguration() {
        let originalLevel = SpeechSession.logging
        SpeechSession.logging = .off

        SpeechSession.logging = .debug
        #expect(SpeechSession.logging == .debug)

        SpeechSession.logging = originalLevel
    }
}
