import Foundation

public extension SpeechSessionError {
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return NSLocalizedString("Microphone permission denied. Please grant microphone access in Settings.",
                                     comment: "Error when microphone permission is not granted")

        case .speechRecognitionPermissionDenied:
            return NSLocalizedString(
                "Speech recognition permission denied. Please grant speech recognition access in Settings.",
                comment: "Error when speech recognition permission is not granted"
            )

        case .unsupportedLocale(let locale):
            return String(format: NSLocalizedString("The locale '%@' is not supported by SpeechAnalyzer.",
                                                   comment: "Error when specified locale is not supported"),
                          locale.identifier)

        case .recognitionStreamSetupFailed:
            return NSLocalizedString("Failed to set up speech recognition stream.",
                                     comment: "Error when speech recognition stream setup fails")

        case .invalidAudioDataType:
            return NSLocalizedString("Invalid audio data type provided.",
                                     comment: "Error when audio data type is invalid")

        case .bufferConverterCreationFailed:
            return NSLocalizedString("Failed to create audio buffer converter.",
                                     comment: "Error when audio buffer converter creation fails")

        case .conversionBufferCreationFailed:
            return NSLocalizedString("Failed to create audio conversion buffer.",
                                     comment: "Error when audio conversion buffer creation fails")

        case .audioConversionFailed(let underlyingError):
            if let underlyingError {
                return String(
                    format: NSLocalizedString(
                        "Audio conversion failed: %@",
                        comment: "Error when audio conversion fails with underlying error"
                    ),
                    underlyingError.localizedDescription
                )
            }
            return NSLocalizedString("Audio conversion failed.",
                                     comment: "Error when audio conversion fails")

        case .audioFileNotFound(let url):
            return String(format: NSLocalizedString("Audio file not found at path %@.",
                                                   comment: "Error when the requested audio file cannot be located"),
                          url.path)

        case .audioFileUnsupportedFormat(let description):
            return String(format: NSLocalizedString("Audio file format is not supported: %@.",
                                                   comment: "Error when audio file format cannot be processed"),
                          description)

        case .audioFileTooLong(let maximum, let actual):
            let maximumFormatted = String(format: "%.2f", maximum)
            let actualFormatted = String(format: "%.2f", actual)
            return String(
                format: NSLocalizedString(
                    "Audio file duration (%@ seconds) exceeds the allowed limit of %@ seconds.",
                    comment: "Error when audio file is longer than permitted"
                ),
                actualFormatted,
                maximumFormatted
            )

        case .audioFileReadFailed(let underlyingError):
            if let underlyingError {
                return String(
                    format: NSLocalizedString(
                        "Failed to read audio file: %@",
                        comment: "Error when reading audio file fails with underlying error"
                    ),
                    underlyingError.localizedDescription
                )
            }
            return NSLocalizedString("Failed to read audio file.",
                                     comment: "Error when reading audio file fails")

        case .modelDownloadNoInternet:
            return NSLocalizedString("Speech model download failed. No internet connection detected.",
                                     comment: "Error when device is offline during model download")

        case .modelDownloadFailed(let underlyingError):
            if let underlyingError {
                return String(
                    format: NSLocalizedString(
                        "Speech model download failed: %@",
                        comment: "Error when speech model download fails with underlying error"
                    ),
                    underlyingError.localizedDescription
                )
            }
            return NSLocalizedString("Speech model download failed.",
                                     comment: "Generic model download failure")

        case .modelReservationFailed(let locale, let underlyingError):
            return String(
                format: NSLocalizedString(
                    "Failed to reserve speech assets for locale '%@': %@.",
                    comment: "Error when reserving speech model locale fails"
                ),
                locale.identifier,
                underlyingError.localizedDescription
            )

        case .contextSetupFailed(let underlyingError):
            return String(format: NSLocalizedString("Failed to set up analysis context: %@",
                                                   comment: "Error when analysis context setup fails"),
                          underlyingError.localizedDescription)

        case .customVocabularyRequiresIdleSession:
            return NSLocalizedString(
                "Custom vocabulary can only be configured when the session is idle.",
                comment: "Error when attempting to configure vocabulary during an active session"
            )

        case .customVocabularyUnsupportedLocale(let locale):
            return String(
                format: NSLocalizedString(
                    "Custom vocabulary locale '%@' does not match the session locale.",
                    comment: "Error when custom vocabulary locale mismatches session"
                ),
                locale.identifier
            )

        case .customVocabularyPreparationFailed:
            return NSLocalizedString(
                "Unable to prepare storage for the custom vocabulary model.",
                comment: "Error when preparing custom vocabulary storage fails"
            )

        case .customVocabularyCompilationFailed(let underlyingError):
            return String(
                format: NSLocalizedString(
                    "Custom vocabulary compilation failed: %@",
                    comment: "Error when compiling custom vocabulary fails"
                ),
                underlyingError.localizedDescription
            )
        }
    }

    var failureReason: String? {
        switch self {
        case .microphonePermissionDenied:
            return NSLocalizedString("The app requires microphone access to record audio for transcription.",
                                     comment: "Failure reason for microphone permission error")

        case .speechRecognitionPermissionDenied:
            return NSLocalizedString("The app requires speech recognition access to convert speech to text.",
                                     comment: "Failure reason for speech recognition permission error")

        case .unsupportedLocale:
            return NSLocalizedString("The selected language is not available on this device.",
                                     comment: "Failure reason for unsupported locale error")

        case .recognitionStreamSetupFailed:
            return NSLocalizedString("Unable to initialize the speech recognition system.",
                                     comment: "Failure reason for recognition stream setup error")

        case .invalidAudioDataType:
            return NSLocalizedString("The audio format is not compatible with speech recognition.",
                                     comment: "Failure reason for invalid audio data type error")

        case .bufferConverterCreationFailed, .conversionBufferCreationFailed, .audioConversionFailed:
            return NSLocalizedString("Unable to process the audio data for speech recognition.",
                                     comment: "Failure reason for audio processing errors")

        case .audioFileNotFound:
            return NSLocalizedString("The specified audio file could not be found.",
                                     comment: "Failure reason for missing audio file")

        case .audioFileUnsupportedFormat:
            return NSLocalizedString("The audio encoding is not compatible with the transcription pipeline.",
                                     comment: "Failure reason for unsupported audio file format")

        case .audioFileTooLong:
            return NSLocalizedString("The audio file is longer than the allowed duration for offline transcription.",
                                     comment: "Failure reason when audio file exceeds maximum duration")

        case .audioFileReadFailed:
            return NSLocalizedString("The audio samples could not be read from disk.",
                                     comment: "Failure reason when audio file reading fails")

        case .modelDownloadNoInternet:
            return NSLocalizedString(
                "The device is offline, so the required speech model could not be downloaded.",
                comment: "Failure reason when model download lacks internet"
            )

        case .modelDownloadFailed:
            return NSLocalizedString("The speech model could not be downloaded.",
                                     comment: "Failure reason when model download fails")

        case .modelReservationFailed:
            return NSLocalizedString(
                "The speech framework couldn't allocate the locale for offline assets.",
                comment: "Failure reason when locale reservation fails"
            )

        case .contextSetupFailed:
            return NSLocalizedString(
                "Unable to configure the speech analyzer with the provided contextual strings.",
                comment: "Failure reason when context setup fails"
            )

        case .customVocabularyRequiresIdleSession:
            return NSLocalizedString(
                "Custom vocabulary updates cannot be applied while transcription is active.",
                comment: "Failure reason when configuring vocabulary during active session"
            )

        case .customVocabularyUnsupportedLocale:
            return NSLocalizedString(
                "The custom vocabulary uses a different locale than the session.",
                comment: "Failure reason when vocabulary locale mismatches"
            )

        case .customVocabularyPreparationFailed:
            return NSLocalizedString(
                "The storage location for the custom language model could not be created.",
                comment: "Failure reason when preparing vocabulary storage fails"
            )

        case .customVocabularyCompilationFailed:
            return NSLocalizedString(
                "The speech framework rejected the provided vocabulary data.",
                comment: "Failure reason when vocabulary compilation fails"
            )
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return NSLocalizedString(
                "Go to Settings > Privacy & Security > Microphone and enable access for this app.",
                comment: "Recovery suggestion for microphone permission error"
            )

        case .speechRecognitionPermissionDenied:
            return NSLocalizedString(
                "Go to Settings > Privacy & Security > Speech Recognition and enable access for this app.",
                comment: "Recovery suggestion for speech recognition permission error"
            )

        case .unsupportedLocale:
            return NSLocalizedString("Try selecting a different language or check if the language pack is installed.",
                                     comment: "Recovery suggestion for unsupported locale error")

        case .recognitionStreamSetupFailed:
            return NSLocalizedString(
                "Try restarting the app or check your device's speech recognition capabilities.",
                comment: "Recovery suggestion for recognition stream setup error"
            )

        case .invalidAudioDataType, .bufferConverterCreationFailed,
             .conversionBufferCreationFailed, .audioConversionFailed:
            return NSLocalizedString(
                "Try recording audio again or check your device's microphone.",
                comment: "Recovery suggestion for audio processing errors"
            )

        case .audioFileNotFound:
            return NSLocalizedString(
                "Verify the file path and ensure the audio asset is bundled with the app or accessible on disk.",
                comment: "Recovery suggestion for missing audio file"
            )

        case .audioFileUnsupportedFormat:
            return NSLocalizedString(
                "Export the audio as linear PCM (for example WAV or CAF) or another supported format and try again.",
                comment: "Recovery suggestion for unsupported audio format"
            )

        case .audioFileTooLong:
            return NSLocalizedString("Trim the audio file or increase the allowed duration before retrying.",
                                     comment: "Recovery suggestion for lengthy audio file")

        case .audioFileReadFailed:
            return NSLocalizedString(
                "Ensure the file is not corrupted and that the app has permission to read it, then try again.",
                comment: "Recovery suggestion when audio file reading fails"
            )

        case .modelDownloadNoInternet:
            return NSLocalizedString("Connect to the internet and try downloading the speech model again.",
                                     comment: "Recovery suggestion when offline during model download")

        case .modelDownloadFailed:
            return NSLocalizedString("Try again later or verify your network connection.",
                                     comment: "Recovery suggestion when model download fails")

        case .modelReservationFailed:
            return NSLocalizedString(
                "Close other apps using on-device speech assets or choose a different locale, then try again.",
                comment: "Recovery suggestion when locale reservation fails"
            )

        case .contextSetupFailed:
            return NSLocalizedString("Try starting transcription again or simplify the contextual strings provided.",
                                     comment: "Recovery suggestion when context setup fails")

        case .customVocabularyRequiresIdleSession:
            return NSLocalizedString(
                "Stop the active transcription session before configuring a custom vocabulary.",
                comment: "Recovery suggestion for active session vocabulary configuration"
            )

        case .customVocabularyUnsupportedLocale:
            return NSLocalizedString(
                "Create the custom vocabulary using the same locale as the transcription session.",
                comment: "Recovery suggestion for mismatched vocabulary locale"
            )

        case .customVocabularyPreparationFailed:
            return NSLocalizedString(
                "Ensure the app can write to the Application Support directory and try again.",
                comment: "Recovery suggestion when vocabulary storage preparation fails"
            )

        case .customVocabularyCompilationFailed:
            return NSLocalizedString(
                "Check the vocabulary entries for invalid data or try recompiling later.",
                comment: "Recovery suggestion when vocabulary compilation fails"
            )
        }
    }
}
