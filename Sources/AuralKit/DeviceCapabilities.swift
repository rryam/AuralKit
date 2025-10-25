import Foundation
import Speech

/// Snapshot of the speech-recognition capabilities that are currently available on the device.
public struct DeviceCapabilities: Sendable {
    /// Indicates whether the device can host `SpeechTranscriber`.
    public let supportsSpeechTranscriber: Bool
    /// Indicates whether the device can host `DictationTranscriber`.
    public let supportsDictationTranscriber: Bool
    /// Locales that can be downloaded or used by `SpeechTranscriber`.
    public let supportedLocales: [Locale]
    /// Locales supported by `DictationTranscriber`.
    public let supportedDictationLocales: [Locale]
    /// Locales that are already installed and ready for offline use.
    public let installedLocales: [Locale]
    /// Maximum number of locale reservations permitted via `AssetInventory`.
    public let maxReservedLocales: Int

    /// Creates a new `DeviceCapabilities` snapshot.
    /// - Parameters map directly to the stored properties.
    public init(
        supportsSpeechTranscriber: Bool,
        supportsDictationTranscriber: Bool,
        supportedLocales: [Locale],
        supportedDictationLocales: [Locale],
        installedLocales: [Locale],
        maxReservedLocales: Int
    ) {
        self.supportsSpeechTranscriber = supportsSpeechTranscriber
        self.supportsDictationTranscriber = supportsDictationTranscriber
        self.supportedLocales = supportedLocales
        self.supportedDictationLocales = supportedDictationLocales
        self.installedLocales = installedLocales
        self.maxReservedLocales = maxReservedLocales
    }
}

@MainActor
extension SpeechSession {
    /// Returns a snapshot of currently supported and installed locales along with transcriber availability.
    ///
    /// The call runs asynchronously to match the Swift Speech APIs it queries and can be invoked from any actor.
    /// - Returns: A `DeviceCapabilities` struct describing availability for both speech and dictation transcribers.
    public nonisolated static func deviceCapabilities() async -> DeviceCapabilities {
        async let supportedLocalesTask = SpeechTranscriber.supportedLocales
        async let installedLocalesTask = SpeechTranscriber.installedLocales
        async let dictationLocalesTask = DictationTranscriber.supportedLocales

        let supportsSpeechTranscriber = SpeechTranscriber.isAvailable
        let dictationLocales = await dictationLocalesTask
        let supportsDictationTranscriber = !dictationLocales.isEmpty

        let supportedLocales = await supportedLocalesTask
        let installedLocales = await installedLocalesTask

        return DeviceCapabilities(
            supportsSpeechTranscriber: supportsSpeechTranscriber,
            supportsDictationTranscriber: supportsDictationTranscriber,
            supportedLocales: supportedLocales,
            supportedDictationLocales: dictationLocales,
            installedLocales: installedLocales,
            maxReservedLocales: AssetInventory.maximumReservedLocales
        )
    }
}
