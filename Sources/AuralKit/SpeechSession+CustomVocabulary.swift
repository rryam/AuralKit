import Foundation
import Speech
import CryptoKit
import OSLog

private let customVocabularyLogger = Logger(subsystem: "com.auralkit.speech", category: "CustomVocabulary")

func logCustomVocabularyError(_ message: StaticString, path: String, error: Error) {
    Task { @MainActor in
        guard SpeechSession.shouldLog(.error) else { return }
        customVocabularyLogger.error("\(message) path: \(path, privacy: .public)")
        customVocabularyLogger.error("error: \(error.localizedDescription, privacy: .public)")
    }
}

extension SpeechSession {

    // swiftlint:disable nesting
    public struct CustomVocabulary: Sendable, Hashable, Encodable {
        public struct Phrase: Sendable, Hashable, Encodable {
            public let text: String
            public let count: Int

            public init(text: String, count: Int) {
                self.text = text
                self.count = count
            }
        }

        public struct Pronunciation: Sendable, Hashable, Encodable {
            public let grapheme: String
            public let phonemes: [String]

            public init(grapheme: String, phonemes: [String]) {
                self.grapheme = grapheme
                self.phonemes = phonemes
            }
        }

        public struct Template: Sendable, Hashable, Encodable {
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

        /// Deterministic identifier derived from the descriptor contents.
        ///
        /// Uses `JSONEncoder` with sorted keys to ensure identical inputs
        /// produce identical digests across processes and launches.
        public func stableCacheKey() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
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

        enum CodingKeys: String, CodingKey {
            case locale
            case identifier
            case version
            case weight
            case phrases
            case pronunciations
            case templates
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(locale.identifier(.bcp47), forKey: .locale)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(version, forKey: .version)
            try container.encodeIfPresent(weight, forKey: .weight)
            try container.encode(phrases, forKey: .phrases)
            try container.encode(pronunciations, forKey: .pronunciations)
            try container.encode(templates, forKey: .templates)
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
        let cacheKey = try descriptor.stableCacheKey()
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

        // Clean up any existing temp file before creating new one
        try? fileManager.removeItem(at: assetURL)

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

        defer {
            // Best-effort cleanup of temp asset file
            do {
                try fileManager.removeItem(at: paths.assetURL)
            } catch {
                // Only log if file still exists after failed attempt
                if fileManager.fileExists(atPath: paths.assetURL.path) {
                    logCustomVocabularyError(
                        "Failed to clean up temp vocabulary asset.",
                        path: paths.assetURL.path,
                        error: error
                    )
                }
            }
        }

        do {
            try await modelData.export(to: paths.assetURL)
            try await Task.detached(priority: .userInitiated) {
                try await SFSpeechLanguageModel.prepareCustomLanguageModel(
                    for: paths.assetURL,
                    configuration: configuration
                )
            }.value
        } catch {
            throw SpeechSessionError.customVocabularyCompilationFailed(error)
        }
    }
}
