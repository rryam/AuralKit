import Foundation
import Speech
import Testing
@testable import AuralKit

@Suite("Custom vocabulary artifact ownership")
@MainActor
struct CustomVocabularyOwnershipTests {
    func descriptor(_ version: String = "1") -> SpeechSession.CustomVocabulary {
        .init(locale: Locale(identifier: "en_US"), identifier: "ownership-test", version: version, weight: 0.4)
    }

    func session(_ preparation: VocabularyPreparation) -> SpeechSession {
        let session = SpeechSession(locale: Locale(identifier: "en_US"))
        session.customVocabularyCompiler = CustomVocabularyCompiler { descriptor, asset, configuration in
            try await preparation.prepare(descriptor, asset: asset, configuration: configuration)
        }
        return session
    }

    @Test("Equal descriptors have private production outputs and independent retirement")
    func twoSessionsRetireIndependently() async throws {
        let preparation = VocabularyPreparation()
        var first: SpeechSession? = session(preparation)
        var second: SpeechSession? = session(preparation)
        defer { first = nil; second = nil }
        weak var weakFirst = first
        weak var weakSecond = second
        try await first!.configureCustomVocabulary(descriptor())
        try await second!.configureCustomVocabulary(descriptor())
        let firstDirectory = try #require(first?.customVocabularyOutputDirectory)
        let secondDirectory = try #require(second?.customVocabularyOutputDirectory)
        #expect(firstDirectory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(firstDirectory != secondDirectory)
        #expect(first?.customVocabularyCacheKey == second?.customVocabularyCacheKey)
        #expect(second?.customVocabularyConfiguration?.weight?.doubleValue == 0.4)
        try await second!.configureCustomVocabulary(descriptor())
        #expect(second?.customVocabularyOutputDirectory == secondDirectory)
        #expect(await preparation.count == 2)

        try await first!.configureCustomVocabulary(nil)
        #expect(!FileManager.default.fileExists(atPath: firstDirectory.path))
        try assertFiles(in: secondDirectory)
        try await first!.configureCustomVocabulary(descriptor())
        let retired = try #require(first?.customVocabularyOutputDirectory)
        try await first!.configureCustomVocabulary(descriptor("replacement"))
        let replacement = try #require(first?.customVocabularyOutputDirectory)
        #expect(!FileManager.default.fileExists(atPath: retired.path))
        try assertFiles(in: secondDirectory)
        first = nil
        #expect(weakFirst == nil)
        #expect(!FileManager.default.fileExists(atPath: replacement.path))
        try assertFiles(in: secondDirectory)
        second = nil
        #expect(weakSecond == nil)
        #expect(!FileManager.default.fileExists(atPath: secondDirectory.path))
    }

    enum Rejection: Sendable, CaseIterable { case clear, replacement, cancellation }

    @Test("Pending compilation cannot publish after clear, replacement or cancellation", arguments: Rejection.allCases)
    func rejectedCompilationRetires(rejection: Rejection) async throws {
        let preparation = VocabularyPreparation()
        let session = session(preparation)
        let request = Task { @MainActor in
            defer { preparation.ready.continuation.finish() }
            try await session.configureCustomVocabulary(descriptor("blocked"))
        }
        do {
            // The collaborator signals only after production paths/configuration and real files exist.
            var ready = preparation.ready.stream.makeAsyncIterator()
            let rejectedDirectory = try #require(await ready.next())
            switch rejection {
            case .clear: try await session.configureCustomVocabulary(nil)
            case .replacement: try await session.configureCustomVocabulary(descriptor("replacement"))
            case .cancellation: request.cancel()
            }
            preparation.release.continuation.yield(())
            // Always join the actual request before any throwing assertion or fixture exit.
            let result = await request.result
            do {
                try result.get()
                Issue.record("Expected rejection")
            } catch is CancellationError { }
            #expect(!FileManager.default.fileExists(atPath: rejectedDirectory.path))
            if rejection == .replacement {
                let retained = try #require(session.customVocabularyOutputDirectory)
                try assertFiles(in: retained)
                #expect(session.customVocabularyDescriptor?.version == "replacement")
                try await session.configureCustomVocabulary(nil)
                #expect(!FileManager.default.fileExists(atPath: retained.path))
            } else {
                #expect(session.customVocabularyConfiguration == nil)
            }
        } catch {
            request.cancel()
            preparation.release.continuation.finish()
            _ = await request.result
            throw error
        }
    }

    @Test("Failed preparation removes partial production output")
    func failedCompilationRetires() async throws {
        let preparation = VocabularyPreparation()
        let session = session(preparation)
        do {
            try await session.configureCustomVocabulary(descriptor("failure"))
            Issue.record("Expected preparation error")
        } catch SpeechSessionError.customVocabularyCompilationFailed { }
        let failed = try #require(await preparation.directories.first)
        #expect(!FileManager.default.fileExists(atPath: failed.path))
        #expect(session.customVocabularyConfiguration == nil)
    }

    @Test("Detached transcriber state retains files after session retirement")
    func detachedStateRetainsArtifacts() async throws {
        let preparation = VocabularyPreparation()
        var owner: SpeechSession? = session(preparation)
        defer { owner = nil }
        try await owner!.configureCustomVocabulary(descriptor())
        let directory = try #require(owner?.customVocabularyOutputDirectory)
        // Constructs the real customized module; no asset install or analyzer start.
        _ = try await owner!.createDictationTranscriber()
        var detached: SpeechSession.DetachedTranscriberState? = owner!.detachTranscriberState()
        try await owner!.configureCustomVocabulary(nil)
        owner = nil
        try assertFiles(in: directory)
        await SpeechSession().finalizeDetachedTranscriberState(try #require(detached))
        try assertFiles(in: directory)
        detached = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Queued result consumer retains artifacts through terminal cleanup")
    func resultConsumerRetainsArtifacts() async throws {
        let preparation = VocabularyPreparation()
        var owner: SpeechSession? = session(preparation)
        defer { owner = nil }
        weak var weakOwner = owner
        try await owner!.configureCustomVocabulary(descriptor())
        let directory = try #require(owner?.customVocabularyOutputDirectory)
        let results = AsyncStream<Int>.makeStream()
        let output = AsyncThrowingStream<Int, Error>.makeStream()
        let reader = owner!.createRecognizerTask(
            label: "Ownership fixture",
            vocabularyArtifacts: owner?.customVocabularyArtifacts,
            results: results.stream,
            streamContinuation: output.continuation,
            generation: owner!.sessionGeneration
        )
        // Drop the session's ownership before the queued reader's first actor turn.
        owner!.clearCustomVocabularyArtifacts(removeDescriptor: true)
        owner = nil
        #expect(weakOwner != nil)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        results.continuation.finish()
        await reader.value
        #expect(weakOwner == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    func assertFiles(in directory: URL) throws {
        #expect(try Data(contentsOf: directory.appendingPathComponent("languageModel.bin")) == Data("model".utf8))
        #expect(try Data(contentsOf: directory.appendingPathComponent("vocabulary.bin")) == Data("vocabulary".utf8))
    }
}

/// Substitutes only Apple export/preparation, keeping production allocation and configuration.
actor VocabularyPreparation {
    enum Failure: Error { case expected }
    nonisolated let ready = AsyncStream<URL>.makeStream()
    nonisolated let release = AsyncStream<Void>.makeStream()
    private(set) var directories: [URL] = []
    var count: Int { directories.count }

    func prepare(
        _ descriptor: SpeechSession.CustomVocabulary,
        asset: URL,
        configuration: SFSpeechLanguageModel.Configuration
    ) async throws {
        let directory = configuration.languageModel.deletingLastPathComponent()
        directories.append(directory)
        try Data("source".utf8).write(to: asset)
        try Data("model".utf8).write(to: configuration.languageModel)
        try Data("vocabulary".utf8).write(to: #require(configuration.vocabulary))
        if descriptor.version == "failure" { throw Failure.expected }
        if descriptor.version == "blocked" {
            ready.continuation.yield(directory)
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
            try Task.checkCancellation()
        }
    }
}
