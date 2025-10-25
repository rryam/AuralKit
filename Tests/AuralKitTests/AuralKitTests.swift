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
    func statusStreamBroadcastsToMultipleSubscribers() async throws {
        let session = SpeechSession()

        var iteratorA = session.statusStream.makeAsyncIterator()
        var iteratorB = session.statusStream.makeAsyncIterator()

        let firstA = try await awaitResult {
            await iteratorA.next()
        }
        let firstB = try await awaitResult {
            await iteratorB.next()
        }

        #expect(firstA == .some(.idle))
        #expect(firstB == .some(.idle))

        let nextA = Task {
            await iteratorA.next()
        }
        let nextB = Task {
            await iteratorB.next()
        }
        defer {
            nextA.cancel()
            nextB.cancel()
        }

        session.setStatus(.preparing)

        let valueA = try await awaitResult {
            await nextA.value
        }
        let valueB = try await awaitResult {
            await nextB.value
        }
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
    func audioInputStreamBroadcastsNil() async throws {
        let session = SpeechSession()

        var iteratorA = session.audioInputConfigurationStream.makeAsyncIterator()
        var iteratorB = session.audioInputConfigurationStream.makeAsyncIterator()

        let valueA = Task {
            await iteratorA.next()
        }
        let valueB = Task {
            await iteratorB.next()
        }
        defer {
            valueA.cancel()
            valueB.cancel()
        }

        await Task.yield()
        session.broadcastAudioInputInfo(nil)

        let firstA = try await awaitResult {
            await valueA.value
        }
        let firstB = try await awaitResult {
            await valueB.value
        }
        let flattenedA = firstA?.flatMap { $0 }
        let flattenedB = firstB?.flatMap { $0 }
        #expect(flattenedA == nil)
        #expect(flattenedB == nil)
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
