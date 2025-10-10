import Foundation
import Speech

public struct DeviceCapabilities: Sendable {
    public let supportsSpeechTranscriber: Bool
    public let supportsDictationTranscriber: Bool
    public let supportedLocales: [Locale]
    public let supportedDictationLocales: [Locale]
    public let installedLocales: [Locale]
    public let maxReservedLocales: Int

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
