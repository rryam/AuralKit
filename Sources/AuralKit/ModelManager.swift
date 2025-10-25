import Foundation
import Speech
import OSLog

// MARK: - Model Manager

class ModelManager: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.auralkit.speech", category: "ModelManager")

    private(set) var currentDownloadProgress: Progress?

    /// Ensure the speech model for the given locale is available
    func ensureModel(module: any LocaleDependentSpeechModule, locale: Locale) async throws {
        if let speechModule = module as? SpeechTranscriber {
            try await ensureLocaleAssets(
                module: speechModule,
                locale: locale,
                supportedLocales: { await SpeechTranscriber.supportedLocales },
                installedLocales: { await SpeechTranscriber.installedLocales }
            )
            return
        }

        if let dictationModule = module as? DictationTranscriber {
            try await ensureLocaleAssets(
                module: dictationModule,
                locale: locale,
                supportedLocales: { await DictationTranscriber.supportedLocales },
                installedLocales: { await DictationTranscriber.installedLocales }
            )
            return
        }

        try await downloadAssetsIfNeeded(for: [module])
    }

    private func ensureLocaleAssets<Module: LocaleDependentSpeechModule>(
        module: Module,
        locale: Locale,
        supportedLocales: @escaping @Sendable () async -> [Locale],
        installedLocales: @escaping @Sendable () async -> [Locale]
    ) async throws {
        guard await localeMatches(provider: supportedLocales, locale: locale) else {
            throw SpeechSessionError.unsupportedLocale(locale)
        }

        if await localeMatches(provider: installedLocales, locale: locale) {
            logger.notice("Locale \(locale.identifier(.bcp47)) already installed")
            currentDownloadProgress = nil
        } else {
            logger.info("Ensuring model download for locale \(locale.identifier(.bcp47))")
            try await downloadAssetsIfNeeded(for: [module])
        }
    }

    private func localeMatches(
        provider: @escaping @Sendable () async -> [Locale],
        locale: Locale
    ) async -> Bool {
        let locales = await provider()
        let target = locale.identifier(.bcp47)
        return locales.contains { $0.identifier(.bcp47) == target }
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
