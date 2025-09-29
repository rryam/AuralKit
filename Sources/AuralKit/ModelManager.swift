import Foundation
import Speech

// MARK: - Model Manager

class ModelManager: @unchecked Sendable {

    private(set) var currentDownloadProgress: Progress?

    /// Ensure the speech model for the given locale is available
    func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw SpeechSessionError.unsupportedLocale(locale)
        }

        if await installed(locale: locale) {
            currentDownloadProgress = nil
            return
        } else {
            try await downloadIfNeeded(for: transcriber)
        }
    }

    /// Check if the locale is supported
    private func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    /// Check if the locale is already installed
    private func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    /// Download the model if needed
    private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            currentDownloadProgress = downloader.progress
            do {
                try await downloader.downloadAndInstall()
                currentDownloadProgress = nil
            } catch {
                currentDownloadProgress = nil
                if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
                    throw SpeechSessionError.modelDownloadNoInternet
                }

                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain,
                   nsError.code == URLError.notConnectedToInternet.rawValue {
                    throw SpeechSessionError.modelDownloadNoInternet
                }

                throw SpeechSessionError.modelDownloadFailed(nsError)
            }
        } else {
            currentDownloadProgress = nil
        }
    }

    /// Release reserved locales so other clients can access them
    func releaseLocales() async {
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }
        currentDownloadProgress = nil
    }
}
