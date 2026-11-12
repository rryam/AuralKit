import Foundation
import Speech
import Testing
@testable import AuralKit

@Suite("Speech detector monitor identity")
@MainActor
struct SpeechDetectorLifecycleTests {
    @Test("only the current monitor may complete the detector stream", arguments: [false, true])
    func replacementRejectsStaleCompletion(failed: Bool) throws {
        let session = makeSessionWithMonitor()
        defer { session.disableVoiceActivation() }
        let oldID = try #require(session.speechDetectorMonitorID)
        let oldTask = try #require(session.speechDetectorResultsTask)

        session.startSpeechDetectorMonitoring()
        let currentID = try #require(session.speechDetectorMonitorID)
        let currentTask = try #require(session.speechDetectorResultsTask)
        session.isSpeechDetected = false
        let error: Error? = failed ? DetectorTestError.failed : nil
        session.handleSpeechDetectorStreamCompletion(error: error, monitorID: oldID)

        #expect(oldTask.isCancelled)
        #expect(!currentTask.isCancelled)
        #expect(currentID != oldID)
        #expect(session.speechDetectorMonitorID == currentID)
        #expect(session.speechDetectorResultsTask != nil)
        #expect(session.speechDetectorResultsContinuation != nil)
        #expect(session.speechDetectorResultsStream != nil)
        #expect(!session.isSpeechDetected)

        session.handleSpeechDetectorStreamCompletion(error: error, monitorID: currentID)
        #expect(session.speechDetectorMonitorID == nil)
        #expect(session.speechDetectorResultsTask == nil)
        #expect(session.speechDetectorResultsContinuation == nil)
        #expect(session.speechDetectorResultsStream == nil)
        #expect(session.isSpeechDetected)
        currentTask.cancel()
    }

    @Test("disable revokes a monitor before reporting is reconfigured")
    func disableRejectsStaleCompletion() throws {
        let session = makeSessionWithMonitor()
        defer { session.disableVoiceActivation() }
        let oldID = try #require(session.speechDetectorMonitorID)
        let oldTask = try #require(session.speechDetectorResultsTask)
        session.disableVoiceActivation()
        session.configureVoiceActivation(reportResults: true)

        session.handleSpeechDetectorStreamCompletion(error: nil, monitorID: oldID)

        #expect(oldTask.isCancelled)
        #expect(session.speechDetectorMonitorID == nil)
        #expect(session.speechDetectorResultsTask == nil)
        #expect(session.speechDetectorResultsContinuation != nil)
        #expect(session.speechDetectorResultsStream != nil)
        #expect(session.isSpeechDetected)
    }

    private func makeSessionWithMonitor() -> SpeechSession {
        let session = SpeechSession()
        session.configureVoiceActivation(reportResults: true)
        session.speechDetector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: true
        )
        session.startSpeechDetectorMonitoring()
        return session
    }
}

private enum DetectorTestError: Error {
    case failed
}
