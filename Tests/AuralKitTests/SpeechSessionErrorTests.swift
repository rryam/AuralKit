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

    @Test("all error cases have non-empty errorDescription")
    func allErrorsHaveDescription() {
        for error in Self.allErrors {
            let description = error.errorDescription
            #expect(description != nil, "Missing errorDescription for \(error)")
            #expect(description?.isEmpty == false, "Empty errorDescription for \(error)")
        }
    }

    @Test("all error cases have non-empty failureReason")
    func allErrorsHaveFailureReason() {
        for error in Self.allErrors {
            let reason = error.failureReason
            #expect(reason != nil, "Missing failureReason for \(error)")
            #expect(reason?.isEmpty == false, "Empty failureReason for \(error)")
        }
    }

    @Test("all error cases have non-empty recoverySuggestion")
    func allErrorsHaveRecoverySuggestion() {
        for error in Self.allErrors {
            let suggestion = error.recoverySuggestion
            #expect(suggestion != nil, "Missing recoverySuggestion for \(error)")
            #expect(suggestion?.isEmpty == false, "Empty recoverySuggestion for \(error)")
        }
    }
}
