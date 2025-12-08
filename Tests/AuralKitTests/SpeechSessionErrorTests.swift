import Testing
import Foundation
@testable import AuralKit

@Suite("SpeechSessionError Localization")
struct SpeechSessionErrorTests {

    private static var allErrors: [SpeechSessionError] {
        let dummyLocale = Locale(identifier: "en_US")
        let dummyURL = URL(fileURLWithPath: "/test/path")
        let dummyError = NSError(domain: "test", code: 1)

        return [
            .microphonePermissionDenied,
            .speechRecognitionPermissionDenied,
            .unsupportedLocale(dummyLocale),
            .recognitionStreamSetupFailed,
            .invalidAudioDataType,
            .bufferConverterCreationFailed,
            .conversionBufferCreationFailed,
            .audioConversionFailed(dummyError),
            .audioConversionFailed(nil),
            .audioFileNotFound(dummyURL),
            .audioFileInvalidURL(dummyURL),
            .audioFileOutsideAllowedDirectories(dummyURL),
            .audioFileUnsupportedFormat("test format"),
            .audioFileTooLong(maximum: 60.0, actual: 120.0),
            .audioFileReadFailed(dummyError),
            .audioFileReadFailed(nil),
            .modelDownloadNoInternet,
            .modelDownloadFailed(dummyError),
            .modelDownloadFailed(nil),
            .modelReservationFailed(dummyLocale, dummyError),
            .contextSetupFailed(dummyError),
            .customVocabularyRequiresIdleSession,
            .customVocabularyUnsupportedLocale(dummyLocale),
            .customVocabularyPreparationFailed,
            .customVocabularyCompilationFailed(dummyError)
        ]
    }

    enum LocalizedProperty: String, CaseIterable, Sendable {
        case errorDescription
        case failureReason
        case recoverySuggestion

        func value(for error: SpeechSessionError) -> String? {
            switch self {
            case .errorDescription:
                return error.errorDescription
            case .failureReason:
                return error.failureReason
            case .recoverySuggestion:
                return error.recoverySuggestion
            }
        }
    }

    @Test("all error cases have non-empty localized strings", arguments: LocalizedProperty.allCases)
    func allErrorsHaveNonEmptyLocalizedStrings(property: LocalizedProperty) {
        for error in Self.allErrors {
            let value = property.value(for: error)
            #expect(value != nil, "Missing \(property.rawValue) for \(error)")
            #expect(value?.isEmpty == false, "Empty \(property.rawValue) for \(error)")
        }
    }
}
