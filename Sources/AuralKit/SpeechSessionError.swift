import Foundation

/// Errors that can occur during speech transcription operations
public enum SpeechSessionError: LocalizedError {
    /// Microphone permission was denied or not granted
    case microphonePermissionDenied

    /// Speech recognition permission was denied or not granted
    case speechRecognitionPermissionDenied

    /// The specified locale is not supported by SpeechAnalyzer
    case unsupportedLocale(Locale)

    /// Failed to set up the speech recognition stream
    case recognitionStreamSetupFailed

    /// Invalid audio data type provided
    case invalidAudioDataType

    /// Failed to create audio buffer converter
    case bufferConverterCreationFailed

    /// Failed to create audio conversion buffer
    case conversionBufferCreationFailed

    /// Audio buffer conversion failed
    case audioConversionFailed(NSError?)

    /// Model download failed due to lack of connectivity
    case modelDownloadNoInternet

    /// Model download failed for other reasons
    case modelDownloadFailed(NSError?)

    /// Failed to set up analysis context with contextual strings
    case contextSetupFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return NSLocalizedString("Microphone permission denied. Please grant microphone access in Settings.",
                                   comment: "Error when microphone permission is not granted")

        case .speechRecognitionPermissionDenied:
            return NSLocalizedString("Speech recognition permission denied. Please grant speech recognition access in Settings.",
                                   comment: "Error when speech recognition permission is not granted")

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
                return String(format: NSLocalizedString("Audio conversion failed: %@",
                                                       comment: "Error when audio conversion fails with underlying error"),
                             underlyingError.localizedDescription)
            } else {
                return NSLocalizedString("Audio conversion failed.",
                                       comment: "Error when audio conversion fails")
            }
        case .modelDownloadNoInternet:
            return NSLocalizedString("Speech model download failed. No internet connection detected.",
                                   comment: "Error when device is offline during model download")

        case .modelDownloadFailed(let underlyingError):
            if let underlyingError {
                return String(format: NSLocalizedString("Speech model download failed: %@",
                                                       comment: "Error when speech model download fails with underlying error"),
                             underlyingError.localizedDescription)
            } else {
                return NSLocalizedString("Speech model download failed.",
                                       comment: "Generic model download failure")
            }

        case .contextSetupFailed(let underlyingError):
            return String(format: NSLocalizedString("Failed to set up analysis context: %@",
                                                   comment: "Error when analysis context setup fails"),
                         underlyingError.localizedDescription)
        }
    }

    public var failureReason: String? {
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

        case .modelDownloadNoInternet:
            return NSLocalizedString("The device is offline, so the required speech model could not be downloaded.",
                                   comment: "Failure reason when model download lacks internet")

        case .modelDownloadFailed:
            return NSLocalizedString("The speech model could not be downloaded.",
                                   comment: "Failure reason when model download fails")

        case .contextSetupFailed:
            return NSLocalizedString("Unable to configure the speech analyzer with the provided contextual strings.",
                                   comment: "Failure reason when context setup fails")
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return NSLocalizedString("Go to Settings > Privacy & Security > Microphone and enable access for this app.",
                                   comment: "Recovery suggestion for microphone permission error")

        case .speechRecognitionPermissionDenied:
            return NSLocalizedString("Go to Settings > Privacy & Security > Speech Recognition and enable access for this app.",
                                   comment: "Recovery suggestion for speech recognition permission error")

        case .unsupportedLocale:
            return NSLocalizedString("Try selecting a different language or check if the language pack is installed.",
                                   comment: "Recovery suggestion for unsupported locale error")

        case .recognitionStreamSetupFailed:
            return NSLocalizedString("Try restarting the app or check your device's speech recognition capabilities.",
                                   comment: "Recovery suggestion for recognition stream setup error")

        case .invalidAudioDataType, .bufferConverterCreationFailed, .conversionBufferCreationFailed, .audioConversionFailed:
            return NSLocalizedString("Try recording audio again or check your device's microphone.",
                                   comment: "Recovery suggestion for audio processing errors")

        case .modelDownloadNoInternet:
            return NSLocalizedString("Connect to the internet and try downloading the speech model again.",
                                   comment: "Recovery suggestion when offline during model download")

        case .modelDownloadFailed:
            return NSLocalizedString("Try again later or verify your network connection.",
                                   comment: "Recovery suggestion when model download fails")

        case .contextSetupFailed:
            return NSLocalizedString("Try starting transcription again or simplify the contextual strings provided.",
                                   comment: "Recovery suggestion when context setup fails")
        }
    }
}
