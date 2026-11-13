import Foundation
import Testing
@testable import AuralKit

extension CustomVocabularyOwnershipTests {
    @Test("Already-cancelled configuration leaves the pending request intact")
    func cancelledRequestDoesNotSupersede() async throws {
        let preparation = VocabularyPreparation()
        let session = session(preparation)
        let pending = Task { @MainActor in
            defer { preparation.ready.continuation.finish() }
            try await session.configureCustomVocabulary(descriptor("blocked"))
        }
        var ready = preparation.ready.stream.makeAsyncIterator()
        #expect(await ready.next() != nil)
        let cancelled = Task { @MainActor in
            try await session.configureCustomVocabulary(descriptor("replacement"))
        }
        cancelled.cancel()
        let cancelledResult = await cancelled.result
        preparation.release.continuation.finish()
        let pendingResult = await pending.result
        do {
            try cancelledResult.get()
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        try pendingResult.get()
        #expect(session.customVocabularyDescriptor?.version == "blocked")
    }

    @Test("Caller cancellation takes precedence over a joined compiler failure")
    func cancellationAfterCompilerFailure() async throws {
        let session = SpeechSession(locale: Locale(identifier: "en_US"))
        let compiler = CancellingVocabularyCompiler()
        session.customVocabularyCompiler = compiler
        let start = AsyncStream<Void>.makeStream()
        let request = Task { @MainActor in
            for await _ in start.stream { break }
            try await session.configureCustomVocabulary(descriptor())
        }
        await compiler.cancelOnFailure(request)
        start.continuation.finish()
        do {
            try await request.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        #expect(session.customVocabularyConfiguration == nil)
    }

    enum Reuse: Sendable, CaseIterable { case configure, dictation }

    @Test("Purged files are rebuilt before configuration reuse or dictation", arguments: Reuse.allCases)
    func purgedFilesAreRebuilt(reuse: Reuse) async throws {
        let preparation = VocabularyPreparation()
        let session = session(preparation)
        try await session.configureCustomVocabulary(descriptor())
        let purged = try #require(session.customVocabularyOutputDirectory)
        try FileManager.default.removeItem(at: purged.appendingPathComponent("vocabulary.bin"))
        switch reuse {
        case .configure:
            try await session.configureCustomVocabulary(descriptor())
        case .dictation:
            _ = try await session.createDictationTranscriber()
        }
        let rebuilt = try #require(session.customVocabularyOutputDirectory)
        #expect(await preparation.count == 2)
        #expect(rebuilt != purged)
        #expect(!FileManager.default.fileExists(atPath: purged.path))
        try assertFiles(in: rebuilt)
    }
}

private actor CancellingVocabularyCompiler: CustomVocabularyCompiling {
    private var request: Task<Void, Error>?

    func cancelOnFailure(_ request: Task<Void, Error>) { self.request = request }

    func compile(descriptor: SpeechSession.CustomVocabulary) async throws -> CustomVocabularyCompilation {
        request?.cancel()
        request = nil
        throw VocabularyPreparation.Failure.expected
    }
}
