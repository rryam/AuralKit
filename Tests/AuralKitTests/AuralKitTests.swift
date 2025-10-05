import Testing
@testable import AuralKit

@Suite("AuralKit")
struct AuralKitTests {

    @Test("Model download progress starts nil")
    func testInitialDownloadProgressIsNil() async {
        let kit = SpeechSession()
        let progress = await kit.modelDownloadProgress
        #expect(progress == nil)
    }

    @Test("Stop transcribing without session is a no-op")
    @MainActor
    func testStopWithoutSession() async {
        let kit = SpeechSession()
        await kit.stopTranscribing()
        #expect(await kit.modelDownloadProgress == nil)
    }
}
