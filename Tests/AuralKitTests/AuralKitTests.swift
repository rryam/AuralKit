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

    @Test("Status stream broadcasts updates to multiple subscribers")
    @MainActor
    func statusStreamBroadcastsToMultipleSubscribers() async {
        let session = SpeechSession()

        var iteratorA = session.statusStream.makeAsyncIterator()
        var iteratorB = session.statusStream.makeAsyncIterator()

        let firstA = await iteratorA.next()
        let firstB = await iteratorB.next()

        #expect(firstA == .some(.idle))
        #expect(firstB == .some(.idle))

        async let nextA = iteratorA.next()
        async let nextB = iteratorB.next()

        session.setStatus(.preparing)

        let (valueA, valueB) = await (nextA, nextB)
        #expect(valueA == .some(.preparing))
        #expect(valueB == .some(.preparing))
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

@Suite("SpeechSession Audio Input Stream")
struct SpeechSessionAudioInputStreamTests {

    @Test("Audio input stream fans out nil updates")
    @MainActor
    func audioInputStreamBroadcastsNil() async {
        let session = SpeechSession()

        var iteratorA = session.audioInputConfigurationStream.makeAsyncIterator()
        var iteratorB = session.audioInputConfigurationStream.makeAsyncIterator()

        async let valueA = iteratorA.next()
        async let valueB = iteratorB.next()

        session.broadcastAudioInputInfo(nil)

        let (firstA, firstB) = await (valueA, valueB)
        #expect(firstA != nil)
        #expect(firstB != nil)
        #expect(firstA! == nil)
        #expect(firstB! == nil)
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
