import Foundation
import Speech
import CryptoKit

extension SpeechSession {

    // swiftlint:disable nesting
    public struct CustomVocabulary: Sendable, Hashable {

        public struct Phrase: Sendable, Hashable {
            public let text: String
            public let count: Int

            public init(text: String, count: Int) {
                self.text = text
                self.count = count
            }
        }

        public struct Pronunciation: Sendable, Hashable {
            public let grapheme: String
            public let phonemes: [String]

            public init(grapheme: String, phonemes: [String]) {
                self.grapheme = grapheme
                self.phonemes = phonemes
            }
        }

        public struct Template: Sendable, Hashable {
            public let body: String
            public let count: Int
            public let classes: [String: [String]]

            public init(body: String, count: Int, classes: [String: [String]]) {
                self.body = body
                self.count = count
                self.classes = classes
            }
        }

        public let locale: Locale
        public let identifier: String
        public let version: String
        public let weight: Double?
        public let phrases: [Phrase]
        public let pronunciations: [Pronunciation]
        public let templates: [Template]

        public init(
            locale: Locale,
            identifier: String,
            version: String,
            weight: Double? = nil,
            phrases: [Phrase] = [],
            pronunciations: [Pronunciation] = [],
            templates: [Template] = []
        ) {
            self.locale = locale
            self.identifier = identifier
            self.version = version
            self.weight = weight
            self.phrases = phrases
            self.pronunciations = pronunciations
            self.templates = templates
        }

        func cacheKey() throws -> String {
            var payload: [String: Any] = [
                "locale": locale.identifier(.bcp47),
                "identifier": identifier,
                "version": version
            ]

            if let weight {
                payload["weight"] = weight
            }

            payload["phrases"] = phrases.map { ["text": $0.text, "count": $0.count] }
            payload["pronunciations"] = pronunciations.map { ["grapheme": $0.grapheme, "phonemes": $0.phonemes] }
            payload["templates"] = templates.map { template in
                [
                    "body": template.body,
                    "count": template.count,
                    "classes": template.classes
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        func makeModelData() -> SFCustomLanguageModelData {
            let data = SFCustomLanguageModelData(
                locale: locale,
                identifier: identifier,
                version: version
            )

            for phrase in phrases {
                let phraseCount = SFCustomLanguageModelData.PhraseCount(phrase: phrase.text, count: phrase.count)
                data.insert(phraseCount: phraseCount)
            }

            for pronunciation in pronunciations {
                let term = SFCustomLanguageModelData.CustomPronunciation(
                    grapheme: pronunciation.grapheme,
                    phonemes: pronunciation.phonemes
                )
                data.insert(term: term)
            }

            for template in templates {
                let generator = SFCustomLanguageModelData.TemplatePhraseCountGenerator()
                for (className, values) in template.classes {
                    generator.define(className: className, values: values)
                }
                generator.insert(template: template.body, count: template.count)
                data.insert(phraseCountGenerator: generator)
            }

            return data
        }
    }
    // swiftlint:enable nesting
}

struct CustomVocabularyCompilation: Sendable {
    let configuration: SFSpeechLanguageModel.Configuration
    let cacheKey: String
    let outputDirectory: URL
}

protocol CustomVocabularyCompiling: Sendable {
    func compile(descriptor: SpeechSession.CustomVocabulary) async throws -> CustomVocabularyCompilation
}

final class CustomVocabularyCompiler: CustomVocabularyCompiling, @unchecked Sendable {

    private struct CompilationPaths {
        let outputDirectory: URL
        let languageModelURL: URL
        let vocabularyURL: URL
        let assetURL: URL
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func compile(descriptor: SpeechSession.CustomVocabulary) async throws -> CustomVocabularyCompilation {
        let cacheKey = try descriptor.cacheKey()
        let paths = try preparePaths(for: cacheKey)
        let configuration = makeConfiguration(for: descriptor, paths: paths)
        try await exportModelData(descriptor, with: paths, configuration: configuration)

        return CustomVocabularyCompilation(
            configuration: configuration,
            cacheKey: cacheKey,
            outputDirectory: paths.outputDirectory
        )
    }

    private func preparePaths(for cacheKey: String) throws -> CompilationPaths {
        let baseDirectories = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let baseDirectory = baseDirectories.first else {
            throw SpeechSessionError.customVocabularyPreparationFailed
        }

        let outputDirectory = baseDirectory
            .appendingPathComponent("com.auralkit.vocabulary", isDirectory: true)
            .appendingPathComponent(cacheKey, isDirectory: true)

        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        let languageModelURL = outputDirectory.appendingPathComponent("languageModel.bin")
        let vocabularyURL = outputDirectory.appendingPathComponent("vocabulary.bin")
        let assetURL = fileManager.temporaryDirectory
            .appendingPathComponent("auralkit-custom-vocabulary-\(cacheKey).bin")

        if fileManager.fileExists(atPath: assetURL.path) {
            try fileManager.removeItem(at: assetURL)
        }

        return CompilationPaths(
            outputDirectory: outputDirectory,
            languageModelURL: languageModelURL,
            vocabularyURL: vocabularyURL,
            assetURL: assetURL
        )
    }

    private func makeConfiguration(
        for descriptor: SpeechSession.CustomVocabulary,
        paths: CompilationPaths
    ) -> SFSpeechLanguageModel.Configuration {
        if let weight = descriptor.weight {
            return SFSpeechLanguageModel.Configuration(
                languageModel: paths.languageModelURL,
                vocabulary: paths.vocabularyURL,
                weight: NSNumber(value: weight)
            )
        }

        return SFSpeechLanguageModel.Configuration(
            languageModel: paths.languageModelURL,
            vocabulary: paths.vocabularyURL
        )
    }

    private func exportModelData(
        _ descriptor: SpeechSession.CustomVocabulary,
        with paths: CompilationPaths,
        configuration: SFSpeechLanguageModel.Configuration
    ) async throws {
        let modelData = descriptor.makeModelData()

        do {
            try await modelData.export(to: paths.assetURL)
            try await Task.detached(priority: .userInitiated) {
                try await SFSpeechLanguageModel.prepareCustomLanguageModel(
                    for: paths.assetURL,
                    configuration: configuration
                )
            }.value
        } catch {
            try? fileManager.removeItem(at: paths.assetURL)
            throw SpeechSessionError.customVocabularyCompilationFailed(error)
        }

        try? fileManager.removeItem(at: paths.assetURL)
    }
}

@MainActor
extension SpeechSession {

    public func configureCustomVocabulary(_ vocabulary: CustomVocabulary?) async throws {
        if streamingMode != .inactive {
            throw SpeechSessionError.customVocabularyRequiresIdleSession
        }

        guard let vocabulary else {
            clearCustomVocabularyArtifacts(removeDescriptor: true)
            return
        }

        let requestedLocale = vocabulary.locale.identifier(.bcp47)
        let sessionLocale = locale.identifier(.bcp47)
        guard requestedLocale == sessionLocale else {
            throw SpeechSessionError.customVocabularyUnsupportedLocale(vocabulary.locale)
        }

        let cacheKey: String
        do {
            cacheKey = try vocabulary.cacheKey()
        } catch {
            throw SpeechSessionError.customVocabularyCompilationFailed(error)
        }

        if cacheKey == customVocabularyCacheKey,
           customVocabularyConfiguration != nil {
            customVocabularyDescriptor = vocabulary
            return
        }

        let compilation = try await customVocabularyCompiler.compile(descriptor: vocabulary)

        if let previousDirectory = customVocabularyOutputDirectory,
           previousDirectory != compilation.outputDirectory {
            try? FileManager.default.removeItem(at: previousDirectory)
        }

        customVocabularyDescriptor = vocabulary
        customVocabularyConfiguration = compilation.configuration
        customVocabularyCacheKey = compilation.cacheKey
        customVocabularyOutputDirectory = compilation.outputDirectory
    }

    public func startDictationTranscribing(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) -> AsyncThrowingStream<DictationTranscriber.Result, Error> {
        let (stream, newContinuation) = AsyncThrowingStream<DictationTranscriber.Result, Error>.makeStream()

        newContinuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.cleanup(cancelRecognizer: true)
            }
        }

        guard continuation == nil, recognizerTask == nil, streamingMode == .inactive else {
            newContinuation.finish(throwing: SpeechSessionError.recognitionStreamSetupFailed)
            return stream
        }

        setStatus(.preparing)
        continuation = .dictation(newContinuation)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startDictationPipeline(with: newContinuation, contextualStrings: contextualStrings)
        }

        return stream
    }

    public func startTranscribing(
        customVocabulary: CustomVocabulary,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> AsyncThrowingStream<DictationTranscriber.Result, Error> {
        try await configureCustomVocabulary(customVocabulary)
        return startDictationTranscribing(contextualStrings: contextualStrings)
    }

    func clearCustomVocabularyArtifacts(removeDescriptor: Bool) {
        if let directory = customVocabularyOutputDirectory {
            try? FileManager.default.removeItem(at: directory)
        }

        customVocabularyConfiguration = nil
        customVocabularyCacheKey = nil
        customVocabularyOutputDirectory = nil

        if removeDescriptor {
            customVocabularyDescriptor = nil
        }
    }
}
