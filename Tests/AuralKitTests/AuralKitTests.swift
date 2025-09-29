import Testing
@testable import AuralKit

@Suite("AuralKit")
struct AuralKitTests {

    @Test("Model download progress starts nil")
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
}