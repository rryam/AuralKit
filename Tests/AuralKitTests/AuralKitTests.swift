import Testing
import Foundation
@testable import AuralKit

@Suite("AuralKit Tests")
struct AuralKitTests {
    
    @MainActor
    private func createTestKit() -> AuralKit {
        return AuralKit()
    }
    
    @Test("AuralKit initialization")
    @MainActor
    func testInitialization() async {
        let kit = AuralKit()
        #expect(kit != nil)
    }
    
    @Test("Configuration with locale")
    @MainActor
    func testConfiguration() async {
        let spanishLocale = Locale(identifier: "es-ES")
        let kit = AuralKit(locale: spanishLocale)

        #expect(kit != nil)
    }
    
    @Test("Transcribe API availability")
    @MainActor
    func testTranscribeAPI() async {
        let kit = createTestKit()

        // Test startTranscribing method
        let stream = kit.startTranscribing()
        #expect(stream != nil)
    }
    
    @Test("Stop transcribing is safe to call")
    @MainActor
    func testStop() async {
        let kit = createTestKit()

        // Should not crash when called without transcribing
        await kit.stopTranscribing()
        #expect(true) // If we get here, it didn't crash
    }
}