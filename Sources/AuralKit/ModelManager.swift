import Foundation
import Speech
import OSLog

// MARK: - Model Manager

class ModelManager: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.auralkit.speech", category: "ModelManager")

    private(set) var currentDownloadProgress: Progress?

    /// Ensure the speech model for the given locale is available
    func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw SpeechSessionError.unsupportedLocale(locale)
        }

        if await installed(locale: locale) {
            logger.notice("Locale \(locale.identifier(.bcp47)) already installed")
            currentDownloadProgress = nil
            return
        } else {
            logger.info("Ensuring model download for locale \(locale.identifier(.bcp47))")
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
        try await downloadAssetsIfNeeded(for: [module])
    }

    func ensureAssets(for modules: [any SpeechModule]) async throws {
        guard !modules.isEmpty else { return }
        try await downloadAssetsIfNeeded(for: modules)
    }

    private func downloadAssetsIfNeeded(for modules: [any SpeechModule]) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            currentDownloadProgress = downloader.progress
            logger.info("Starting asset download for \(modules.count) module(s)")
            do {
                try await downloader.downloadAndInstall()
                currentDownloadProgress = nil
                logger.notice("Asset download completed successfully")
            } catch {
                currentDownloadProgress = nil
                logger.error("Asset download failed: \(error.localizedDescription, privacy: .public)")
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
            logger.debug("No asset download required for modules")
        }
    }

    /// Release reserved locales so other clients can access them
    func releaseLocales() async {
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }
        currentDownloadProgress = nil
        logger.debug("Released reserved locales")
    }
}
