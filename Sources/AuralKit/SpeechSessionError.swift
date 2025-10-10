import Foundation

/// Errors that can occur during speech transcription operations.
public enum SpeechSessionError: LocalizedError {
    /// Microphone permission was denied or not granted.
    case microphonePermissionDenied

    /// Speech recognition permission was denied or not granted.
    case speechRecognitionPermissionDenied

    /// The specified locale is not supported by `SpeechAnalyzer`.
    case unsupportedLocale(Locale)

    /// Failed to set up the speech recognition stream.
    case recognitionStreamSetupFailed

    /// Invalid audio data type provided.
    case invalidAudioDataType

    /// Failed to create audio buffer converter.
    case bufferConverterCreationFailed

    /// Failed to create audio conversion buffer.
    case conversionBufferCreationFailed

    /// Audio buffer conversion failed.
    case audioConversionFailed(NSError?)

    /// Audio file is missing or cannot be accessed.
    case audioFileNotFound(URL)

    /// Audio file format is not supported for transcription.
    case audioFileUnsupportedFormat(String)

    /// Audio file exceeds the configured duration limit.
    case audioFileTooLong(maximum: TimeInterval, actual: TimeInterval)

    /// Failed while reading audio file samples.
    case audioFileReadFailed(Error?)

    /// Model download failed due to lack of connectivity.
    case modelDownloadNoInternet

    /// Model download failed for other reasons.
    case modelDownloadFailed(NSError?)

    /// Failed to set up analysis context with contextual strings.
    case contextSetupFailed(Error)
}
