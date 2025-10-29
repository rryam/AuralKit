import Foundation
import Speech
import OSLog

// MARK: - Model Manager

class ModelManager: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.auralkit.speech", category: "ModelManager")

    private(set) var currentDownloadProgress: Progress?

    // Track locales reserved by this ModelManager instance to avoid releasing others' reservations
    private var reservedLocales: Set<String> = []

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

        try await reserveLocaleIfNeeded(locale)
    }

    private func localeMatches(
        provider: @escaping @Sendable () async -> [Locale],
        locale: Locale
    ) async -> Bool {
        let locales = await provider()
        let target = locale.identifier(.bcp47)
        return locales.contains { $0.identifier(.bcp47) == target }
    }

    private func reserveLocaleIfNeeded(_ locale: Locale) async throws {
        let existingReservations = await AssetInventory.reservedLocales
        let target = locale.identifier(.bcp47)
        if existingReservations.contains(where: { $0.identifier(.bcp47) == target }) {
            logger.debug("Locale \(target) already reserved")
            // Don't track it - it was reserved by another session
            return
        }

        do {
            try await AssetInventory.reserve(locale: locale)
            logger.info("Reserved locale \(target)")
            reservedLocales.insert(target)
        } catch {
            logger.error("Failed to reserve locale \(target): \(error.localizedDescription, privacy: .public)")
            throw SpeechSessionError.modelReservationFailed(locale, error)
        }
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

                // Check for network connectivity errors
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
    /// Only releases locales that were reserved by this ModelManager instance
    func releaseLocales() async {
        let allReserved = await AssetInventory.reservedLocales
        // Only release locales tracked by this instance
        var releasedCount = 0
        for locale in allReserved {
            let target = locale.identifier(.bcp47)
            if reservedLocales.contains(target) {
                await AssetInventory.release(reservedLocale: locale)
                reservedLocales.remove(target)
                releasedCount += 1
            }
        }
        currentDownloadProgress = nil
        logger.debug("Released \(releasedCount) reserved locale(s)")
    }
}
