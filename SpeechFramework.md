import Foundation
import Speech.SFErrors
import Speech.SFSpeechLanguageModel
import Speech.SFSpeechRecognitionMetadata
import Speech.SFSpeechRecognitionRequest
import Speech.SFSpeechRecognitionResult
import Speech.SFSpeechRecognitionTask
import Speech.SFSpeechRecognitionTaskHint
import Speech.SFSpeechRecognizer
import Speech.SFTranscription
import Speech.SFTranscriptionSegment
import Speech.SFVoiceAnalytics

/**
 Contextual information that may be shared among analyzers.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class AnalysisContext : Sendable {

    @objc public init()

    /**
     A dictionary of supplemental vocabulary words grouped by tag.
     
     Use the tag to easily swap out some of the strings while leaving others in place. The framework provides a predefined ``ContextualStringsTag/general`` tag.
    */
    final public var contextualStrings: [AnalysisContext.ContextualStringsTag : [String]]

    /**
     A dictionary of application-specific contextual information.
     */
    final public var userData: [AnalysisContext.UserDataTag : any Sendable]

    public struct ContextualStringsTag : RawRepresentable, Sendable, Equatable, Hashable {

        /// The raw type that can be used to represent all values of the conforming
        /// type.
        ///
        /// Every distinct value of the conforming type has a corresponding unique
        /// value of the `RawValue` type, but there may be values of the `RawValue`
        /// type that don't have a corresponding value of the conforming type.
        public typealias RawValue = String

        public init(_ rawValue: AnalysisContext.ContextualStringsTag.RawValue)

        /// Creates a new instance with the specified raw value.
        ///
        /// If there is no value of the type that corresponds with the specified raw
        /// value, this initializer returns `nil`. For example:
        ///
        ///     enum PaperSize: String {
        ///         case A4, A5, Letter, Legal
        ///     }
        ///
        ///     print(PaperSize(rawValue: "Legal"))
        ///     // Prints "Optional(PaperSize.Legal)"
        ///
        ///     print(PaperSize(rawValue: "Tabloid"))
        ///     // Prints "nil"
        ///
        /// - Parameter rawValue: The raw value to use for the new instance.
        public init(rawValue: AnalysisContext.ContextualStringsTag.RawValue)

        /// The corresponding value of the raw type.
        ///
        /// A new instance initialized with `rawValue` will be equivalent to this
        /// instance. For example:
        ///
        ///     enum PaperSize: String {
        ///         case A4, A5, Letter, Legal
        ///     }
        ///
        ///     let selectedSize = PaperSize.Letter
        ///     print(selectedSize.rawValue)
        ///     // Prints "Letter"
        ///
        ///     print(selectedSize == PaperSize(rawValue: selectedSize.rawValue)!)
        ///     // Prints "true"
        public let rawValue: AnalysisContext.ContextualStringsTag.RawValue

        /// A predefined tag for applications that have no need to distinguish between sets of contextual strings.
        public static let general: AnalysisContext.ContextualStringsTag
    }

    public struct UserDataTag : RawRepresentable, Sendable, Equatable, Hashable {

        /// The raw type that can be used to represent all values of the conforming
        /// type.
        ///
        /// Every distinct value of the conforming type has a corresponding unique
        /// value of the `RawValue` type, but there may be values of the `RawValue`
        /// type that don't have a corresponding value of the conforming type.
        public typealias RawValue = String

        public init(_ rawValue: AnalysisContext.UserDataTag.RawValue)

        /// Creates a new instance with the specified raw value.
        ///
        /// If there is no value of the type that corresponds with the specified raw
        /// value, this initializer returns `nil`. For example:
        ///
        ///     enum PaperSize: String {
        ///         case A4, A5, Letter, Legal
        ///     }
        ///
        ///     print(PaperSize(rawValue: "Legal"))
        ///     // Prints "Optional(PaperSize.Legal)"
        ///
        ///     print(PaperSize(rawValue: "Tabloid"))
        ///     // Prints "nil"
        ///
        /// - Parameter rawValue: The raw value to use for the new instance.
        public init(rawValue: AnalysisContext.UserDataTag.RawValue)

        /// The corresponding value of the raw type.
        ///
        /// A new instance initialized with `rawValue` will be equivalent to this
        /// instance. For example:
        ///
        ///     enum PaperSize: String {
        ///         case A4, A5, Letter, Legal
        ///     }
        ///
        ///     let selectedSize = PaperSize.Letter
        ///     print(selectedSize.rawValue)
        ///     // Prints "Letter"
        ///
        ///     print(selectedSize == PaperSize(rawValue: selectedSize.rawValue)!)
        ///     // Prints "true"
        public let rawValue: AnalysisContext.UserDataTag.RawValue
    }

    @objc deinit
}

/**
 Time-coded audio data.
 
 The audio data must have an `AVAudioFormat` that is supported by the analyzer's modules; the analyzer does not perform audio conversion. Call ``SpeechAnalyzer/bestAvailableAudioFormat(compatibleWith:considering:)-([SpeechModule],_)`` (or its variants) to select an appropriate format to convert to.
 
 The audio format may differ from one `AnalyzerInput` object to the next. The modules will be reconfigured if necessary (and possible) as needed.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct AnalyzerInput : @unchecked Sendable {

    /**
         Creates an audio input object.
    
         This audio buffer is assumed to start immediately after the previous buffer (or at time-code zero if there is no previous buffer).
    
         - Parameters:
            - buffer: An audio buffer.
         */
    public init(buffer: AVAudioPCMBuffer)

    /**
         Creates an audio input object for audio that may be discontiguous with previous input.
    
         The audio buffer must not overlap or precede other audio input, as determined by the `bufferStartTime` value.
         
         - Important: If the buffer is converted from other differently-formatted audio, ensure that the buffer's start time is accurate.
            
           Some conversion algorithms can use a "priming" method that may shift some audio to a later converted buffer. This shift will misalign the original and converted audio buffers; the original buffer's start time would not be usable as the `bufferStartTime` value for the converted buffer.
         
         - Tip: Convert an `AVAudioTime` instance to a `CMTime` instance with this code.
            ```swift
            CMTime(value: avAudioTime.sampleTime, timescale: CMTimeScale(avAudioTime.sampleRate))
            ```
         
         - Parameters:
            - buffer: An audio buffer.
            - bufferStartTime: The time-code of the start of the audio buffer. If `nil`, this audio buffer is assumed to start immediately after the previous buffer (or at time-code zero if there is no previous buffer). The `CMTime` can have a different timescale than the sample rate of the audio data.
         */
    public init(buffer: AVAudioPCMBuffer, bufferStartTime: CMTime?)

    /// The audio buffer containing this input.
    public let buffer: AVAudioPCMBuffer

    /// The time-code of this input.
    public let bufferStartTime: CMTime?
}

/**
 An object that describes, downloads, and installs a selection of assets.
 
 You do not create instances of this type directly; obtain them from ``AssetInventory/assetInstallationRequest(supporting:)``.
 
 The system consolidates download and installation requests; you may obtain several of these instances and call ``downloadAndInstall()`` several times without causing redundant downloads.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@objc final public class AssetInstallationRequest : NSObject, ProgressReporting, Sendable {

    final public var progress: Progress { get }

    /**
     Downloads and installs assets not already on the device.
     
     If the system is unable to immediately download assets because of a connectivity issue or other error, the system will automatically attempt to download the assets later. This method will return when the initial download and installation attempt has succeeded or failed; use ``AssetInventory/status(forModules:)`` or another installation request to monitor the success or progress of later attempts.
     
     The system consolidates download and installation requests; you may call this method several times without causing redundant downloads.
     */
    final public func downloadAndInstall() async throws

    @objc deinit
}

/**
 Manages the assets that are necessary for transcription or other analyses.
 
 Before using the ``SpeechAnalyzer`` class, you must install assets required by the modules you plan to use. These assets are machine-learning models downloaded from Apple's servers and managed by the system. Once you download, install, or use an asset, the system retains and updates it automatically, and shares it with other apps. The system makes a certain number of locale-specific asset reservations available to your app to limit storage space and network usage.
 
 Your app does not work with assets directly. Instead, your app configures module objects. The system uses the modules' configuration to determine what assets are relevant.
  
 ### Install assets
 
 Installing an asset is a four-step process:
 
 1. Create analyzer modules in the configurations that you wish to use. These modules can be discarded when no longer needed; the system installs assets using the modules' configuration, not their object identity.

 2. Assign your app's asset reservations to those locales. The class does this automatically if needed, but you can also call ``reserve(locale:)`` to do this manually. This step is only necessary for modules with locale-specific assets; that is, modules conforming to ``LocaleDependentSpeechModule``. You can skip this step for other modules.
 
 3. Start downloading the required assets for the modules' configuration. Call ``assetInstallationRequest(supporting:)`` to obtain an instance of ``AssetInstallationRequest`` and call its ``AssetInstallationRequest/downloadAndInstall()`` method.
 
 4. Wait for the download to finish. Note that the download may finish immediately; the assets may have already been downloaded if the assets were preinstalled on the system, another app already downloaded them, or a previous module configuration used the same assets.
 
 Once assets are downloaded, they persist between app launches and are shared between apps. The system may unsubscribe your app from assets that haven’t been used in a while.
 
 ### Manage assets
 
 When your app no longer needs assets for a particular locale, call ``release(reservedLocale:)`` to free up that reservation. The system will remove the assets at a later time.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class AssetInventory {

    /**
     The number of locale reservations permitted to an app.
     
     This value is the largest allowed count of ``reservedLocales``. The value may vary between devices according to storage space.
     */
    public static var maximumReservedLocales: Int { get }

    /**
     The app's current asset locale reservations.
     
     Before you can subscribe to assets supporting a module, you must reserve those assets' locales. Please note, the locales returned by this method may be variants of the locales provided to ``AssetInventory/reserve(locale:)``.
     */
    public static var reservedLocales: [Locale] { get async }

    /**
     Add an asset locale to the app's current reservations.
     
     If an asset that supports the input locale exists, adds that asset's locale to ``reservedLocales``.
     
     - Throws: An error if the number of locales would exceed ``maximumReservedLocales`` or if there is no asset that can support the locale.
     
     - Returns: `false` if the locale was already reserved.
     */
    @discardableResult
    public static func reserve(locale: Locale) async throws -> Bool

    /**
     Removes an asset locale reservation.
    
     - Returns: `false` if the locale was not reserved.
     */
    @discardableResult
    public static func release(reservedLocale: Locale) async -> Bool

    public enum Status : Comparable {

        /// The module will not work with its configuration.
        case unsupported

        /// The module can work with its configuration, but the assets will need to be downloaded.
        case supported

        /// The system is currently downloading the assets, or waiting for conditions to improve and continue downloading later.
        case downloading

        /// The necessary assets have been downloaded and installed on the device, and the module is ready for use.
        case installed

        /// Returns a Boolean value indicating whether the value of the first
        /// argument is less than that of the second argument.
        ///
        /// This function is the only requirement of the `Comparable` protocol. The
        /// remainder of the relational operator functions are implemented by the
        /// standard library for any type that conforms to `Comparable`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func < (a: AssetInventory.Status, b: AssetInventory.Status) -> Bool

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: AssetInventory.Status, b: AssetInventory.Status) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Returns the status for the list of modules.
     
     If the status differs between modules, it returns the lowest status in order from `unsupported`, `supported`, `downloading`, `installed`.
     */
    public static func status(forModules modules: [any SpeechModule]) async -> AssetInventory.Status

    /**
     Returns an installation request object, which is used to initiate the asset download and monitor its progress.
     
     If the current status is `.installed`, returns nil, indicating that nothing further needs to be done.
     
     If some of the assets require locales that aren't reserved, it automatically reserves those locales. If that would exceed ``maximumReservedLocales``, then it throws an error.
     
     - Throws: An error if the assets are not supported or no reservations are available.
     */
    public static func assetInstallationRequest(supporting modules: [any SpeechModule]) async throws -> AssetInstallationRequest?

    @objc deinit
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension AssetInventory.Status : Hashable {
}

/** A protocol supporting the custom language model training data result builder. */
@available(macOS 14, iOS 17, visionOS 1.1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public protocol DataInsertable {

    func insert(data: SFCustomLanguageModelData)
}

/**
 A speech-to-text transcription module that's similar to system dictation features and compatible with older devices.
 
 This transcriber uses the same speech-to-text machine learning models as system dictation features do, or as ``SFSpeechRecognizer`` does when it is configured for on-device operation. This transcriber does not support languages or locales that `SFSpeechRecognizer` only supports via network access.
 
 Several transcriber instances can share the same backing engine instances and models, so long as the transcribers are configured similarly in certain respects.
 
 ### Improve accuracy
 
 You can bias recognition towards certain words, supply custom vocabulary, or adjust the transcriber's algorithm to improve the transcriber's accuracy.
 
 To bias recognition towards certain words, create an ``AnalysisContext`` object and add those words to its ``AnalysisContext/contextualStrings`` property. Create a ``SpeechAnalyzer`` instance with that context object or set the analyzer's ``SpeechAnalyzer/context`` property.
 
 To supply custom vocabulary, create an ``SFSpeechLanguageModel`` object and configure the transcriber with a corresponding ``ContentHint/customizedLanguage(modelConfiguration:)`` option.
 
 To adjust the transcriber's algorithm, configure the transcriber with relevant ``ContentHint`` parameter. For example, you may use ``ContentHint/farField`` hint to improve accuracy of distant speech.
*/
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class DictationTranscriber : LocaleDependentSpeechModule {

    /**
     Creates a transcriber according to a preset.
     
     - Parameters:
        - locale: A locale indicating a spoken and written language or script.
        - preset: A structure that contains some transcriber options.
     */
    public convenience init(locale: Locale, preset: DictationTranscriber.Preset)

    /**
         Creates a transcriber.
    
         - Parameters:
            - locale: A locale indicating a spoken and written language or script.
            - contentHints: A selection of expected characteristics of the spoken audio.
            - transcriptionOptions: A selection of options relating to the text of the transcription.
            - reportingOptions: A selection of options relating to the transcriber's result delivery.
            - attributeOptions: A selection of options relating to the attributes of the transcription.
         */
    public convenience init(locale: Locale, contentHints: Set<DictationTranscriber.ContentHint>, transcriptionOptions: Set<DictationTranscriber.TranscriptionOption>, reportingOptions: Set<DictationTranscriber.ReportingOption>, attributeOptions: Set<DictationTranscriber.ResultAttributeOption>)

    /**
         Predefined transcriber configurations.
         
         You can configure a transcriber with a preset, or modify the values of a preset's properties and configure a transcriber with the modified values. You can also create your own presets by extending this type.
    
         It is not necessary to use a preset at all; you can also use the transcriber's designated initializer to completely customize its configuration.
         
         This example configures a transcriber according to the `shortDictation` preset, but adds emoji recognition:
    
         ```swift
         let preset = DictationTranscriber.Preset.shortDictation
         let transcriber = DictationTranscriber(
             locale: Locale.current,
             contentHints: preset.contentHints,
             transcriptionOptions: preset.transcriptionOptions.union([.emoji])
             reportingOptions: preset.reportingOptions
             attributeOptions: preset.attributeOptions
         )
         ```
    
         This table lists the presets and their configurations:
         
         Preset | [shortForm](doc:ContentHint/shortForm) | [volatileResults](doc:ReportingOption/volatileResults) | [frequentFinalization](doc:ReportingOption/frequentFinalization) | [audioTimeRange](doc:ResultAttributeOption/audioTimeRange) | [punctuation](doc:TranscriptionOption/punctuation)
         --- | --- | --- | --- | --- | ---
         `phrase` | **Yes** | No | No | No | No
         `shortDictation` | **Yes** | No | No | No | **Yes**
         `progressiveShortDictation` | **Yes** | **Yes** | **Yes** | No | **Yes**
         `longDictation` | No | No | No | No | **Yes**
         `progressiveLongDictation` | No | **Yes** |  No | No | **Yes**
         `timeIndexedLongDictation` | No | No | No | **Yes** | **Yes**
         */
    public struct Preset : Sendable, Equatable, Hashable {

        /// Configuration for a short phrase without punctuation.
        public static let phrase: DictationTranscriber.Preset

        /// Configuration for about a minute of audio.
        public static let shortDictation: DictationTranscriber.Preset

        /// Configuration for immediate transcription of about a minute of live audio.
        public static let progressiveShortDictation: DictationTranscriber.Preset

        /// Configuration for more than a minute of audio.
        public static let longDictation: DictationTranscriber.Preset

        /// Configuration for immediate transcription of lengthy audio.
        public static let progressiveLongDictation: DictationTranscriber.Preset

        /// Configure for lengthy audio, cross-referencing words to time-codes.
        public static let timeIndexedLongDictation: DictationTranscriber.Preset

        /**
         Creates a preset.
         
         - Parameters:
            - contentHints: A selection of expected characteristics of the spoken audio.
            - transcriptionOptions: A selection of options relating to the text of the transcription.
            - reportingOptions: A selection of options relating to the transcriber's result delivery.
            - attributeOptions: A selection of options relating to the attributes of the transcription.
         */
        public init(contentHints: Set<DictationTranscriber.ContentHint>, transcriptionOptions: Set<DictationTranscriber.TranscriptionOption>, reportingOptions: Set<DictationTranscriber.ReportingOption>, attributeOptions: Set<DictationTranscriber.ResultAttributeOption>)

        /// Expected characteristics of the spoken audio appropriate for this preset.
        public var contentHints: Set<DictationTranscriber.ContentHint>

        /// Options relating to the text of the transcription appropriate for this preset.
        public var transcriptionOptions: Set<DictationTranscriber.TranscriptionOption>

        /// Options relating to the transcriber's result delivery appropriate for this preset.
        public var reportingOptions: Set<DictationTranscriber.ReportingOption>

        /// Options relating to the attributes of the transcription appropriate for this preset.
        public var attributeOptions: Set<DictationTranscriber.ResultAttributeOption>

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: DictationTranscriber.Preset, b: DictationTranscriber.Preset) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Expected characteristics of the spoken audio content and its delivery.
     
     These hints optimize transcription, but do not preclude spoken audio with different characteristics.
     */
    public struct ContentHint : Sendable, Equatable, Hashable {

        /**
         A processing hint indicating that the audio is only expected to be a minute or so long.
         */
        public static let shortForm: DictationTranscriber.ContentHint

        /**
         A processing hint indicating that the audio should be processed as if it were from a speaker far from the microphone.
         */
        public static let farField: DictationTranscriber.ContentHint

        /**
         A processing hint indicating that the audio is from a speaker with a heavy accent, lisp, or other confounding factor.
         */
        public static let atypicalSpeech: DictationTranscriber.ContentHint

        /**
         A hint specifying a custom language model applicable to the expected spoken audio content.
         */
        public static func customizedLanguage(modelConfiguration: SFSpeechLanguageModel.Configuration) -> DictationTranscriber.ContentHint

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: DictationTranscriber.ContentHint, b: DictationTranscriber.ContentHint) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Options relating to the text of the transcription.
     */
    public enum TranscriptionOption : CaseIterable, Sendable, Equatable, Hashable {

        /**
         Automatically punctuates the transcription.
         
         If omitted, only spoken punctuation is transcribed, as by the spoken phrase "hello comma there".
         */
        case punctuation

        /**
         Transcribes named emoji as emoji.
         
         If included, the spoken phrase "smiling emoji" would be transcribed as "🙂".
         */
        case emoji

        /**
         Replaces certain words and phrases with a redacted form.
         
         If included, a phrase recognized as an expletive would be transcribed with asterisks.
         */
        case etiquetteReplacements

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: DictationTranscriber.TranscriptionOption, b: DictationTranscriber.TranscriptionOption) -> Bool

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [DictationTranscriber.TranscriptionOption]

        /// A collection of all values of this type.
        nonisolated public static var allCases: [DictationTranscriber.TranscriptionOption] { get }

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Options relating to the transcriber's result delivery.
     */
    public enum ReportingOption : CaseIterable, Sendable, Equatable, Hashable {

        /**
         Provides tentative results for an audio range in addition to the finalized result.
         
         The transcriber will deliver several results for an audio range as it refines the transcription.
         */
        case volatileResults

        /**
         Includes alternative transcriptions in addition to the most likely transcription.
         */
        case alternativeTranscriptions

        /**
         Biases the transcriber towards responsiveness, resulting in more frequent but also less accurate finalized results.
         */
        case frequentFinalization

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: DictationTranscriber.ReportingOption, b: DictationTranscriber.ReportingOption) -> Bool

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [DictationTranscriber.ReportingOption]

        /// A collection of all values of this type.
        nonisolated public static var allCases: [DictationTranscriber.ReportingOption] { get }

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Options relating to the attributes of the transcription.
     */
    public enum ResultAttributeOption : CaseIterable, Sendable, Equatable, Hashable {

        /**
         Includes time-code attributes in a transcription's attributed string.
         
         These are ``Foundation/AttributeScopes/SpeechAttributes/TimeRangeAttribute`` attributes.
         */
        case audioTimeRange

        /**
         Includes confidence attributes in a transcription's attributed string.
         
         These are ``Foundation/AttributeScopes/SpeechAttributes/ConfidenceAttribute`` attributes.
         */
        case transcriptionConfidence

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: DictationTranscriber.ResultAttributeOption, b: DictationTranscriber.ResultAttributeOption) -> Bool

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [DictationTranscriber.ResultAttributeOption]

        /// A collection of all values of this type.
        nonisolated public static var allCases: [DictationTranscriber.ResultAttributeOption] { get }

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     The locales that the transcriber can transcribe into, including locales that may not be installed but are downloadable.
     */
    public static var supportedLocales: [Locale] { get async }

    /**
     A locale from the module's supported locales equivalent to the given locale.
     
     Use this method to determine which of this module's supported locales is equivalent to an arbitrary locale such as `Locale.current`.
     
     If there is no exact equivalent, this method will return a near-equivalent: a supported (and by preference already-installed) locale that shares the same `Locale.LanguageCode` value but has a different `Locale.Region` value. This may result in an unexpected transcription, such as between "color" and "colour".
     
     - Tip: If you use this method, your application should ideally still provide a way for the user to correct the locale by selecting from the supported locales list.
     
     - Parameter locale: An arbitrary locale.
     - Returns: A locale in the supported locales list, or `nil` if there is no equivalent locale in that list.
     */
    public static func supportedLocale(equivalentTo locale: Locale) async -> Locale?

    /**
     The locales that the transcriber can transcribe into, considering only locales that are installed on the device.
     */
    public static var installedLocales: [Locale] { get async }

    /**
     The set of asset locales specified by the module's configuration.
     */
    final public var selectedLocales: [Locale] { get }

    /**
         The audio formats that this module is able to analyze, given its configuration.
         
         If the audio format doesn't matter, then there will be one format listed with a sample rate of `kAudioStreamAnyRate` and other values 0.
         
         If assets are necessary yet not installed on device, then the list will be empty.
    
         This property may be accessed before the module is added to the analyzer.
         */
    final public var availableCompatibleAudioFormats: [AVAudioFormat] { get async }

    /**
     An asynchronous sequence containing this module's analysis results. Results are added to the sequence as they are created.
     
     Each module has its own result sequence and data structure.
     
     If there is an error in the overall analysis, all modules will throw the error from their individual result sequence.
     */
    final public var results: some Sendable & AsyncSequence<DictationTranscriber.Result, any Error> { get }

    /**
     A phrase or passage of transcribed speech. The phrases are sent in order.
     
     If the transcriber is configured to send volatile results, each phrase is sent one or more times as the interpretation gets better and better until it is finalized.
     */
    public struct Result : SpeechModuleResult, Sendable, CustomStringConvertible, Equatable, Hashable {

        /**
         The audio input range that this result applies to.
         */
        public let range: CMTimeRange

        /**
         The audio input time up to which results from this module have been finalized (after this result). The module's results are final up to but not including this time.
         
         This value is mostly equivalent to the start of ``SpeechAnalyzer/volatileRange`` after the time at which this result was published. The module publishing this result will publish no futher results with a ``range`` that encompasses a time predating this time. The module may publish results for a range that includes this time.
         
         The client can draw the following conclusions from this value and `range` (or refer to the <doc:/documentation/Speech/SpeechModuleResult/isFinal> property):
         * If `resultsFinalizationTime >= range.end` then this result is final. Additionally, all previously-provided results with a `range` predating `resultsFinalizationTime` are also final.
         * If `resultsFinalizationTime < range.end` (or `resultsFinalizationTime <= range.start`) then this result is volatile and may or may not be replaced by a result provided later.
         
         A module is not required to provide new, final results for audio ranges that it finalizes through if the previously-volatile result was unchanged by finalization. If needed, however, a client can create two modules—one that provides both volatile and final results, and a second that only provides final results—and process results from the latter differently.
         
         This value is not _exactly_ equivalent to the start of the volatile range. The ``SpeechAnalyzer/volatileRange`` property combines all modules' volatile ranges together; this property only refers to the finalization status of results from the module delivering this result.
         */
        public let resultsFinalizationTime: CMTime

        /**
                 The most likely interpretation of the audio in this range.
        
                 An empty string indicates that the audio contains no recognizable speech and, for results in the volatile range, that previous results for this range are revoked.
                 
                 This value is the first (most likely) element of ``alternatives``.
                 */
        public var text: AttributedString { get }

        /**
         All the alternative interpretations of the audio in this range. The interpretations are in descending order of likelihood.
         
         The array will not be empty, but may contain an empty string, indicating an alternative where the audio has no transcription.
         
         To receive alternatives, set the ``DictationTranscriber/ReportingOption/alternativeTranscriptions`` option.
         */
        public let alternatives: [AttributedString]

        /// A textual representation of this instance.
        ///
        /// Calling this property directly is discouraged. Instead, convert an
        /// instance of any type to a string by using the `String(describing:)`
        /// initializer. This initializer works with any type, and uses the custom
        /// `description` property for types that conform to
        /// `CustomStringConvertible`:
        ///
        ///     struct Point: CustomStringConvertible {
        ///         let x: Int, y: Int
        ///
        ///         var description: String {
        ///             return "(\(x), \(y))"
        ///         }
        ///     }
        ///
        ///     let p = Point(x: 21, y: 30)
        ///     let s = String(describing: p)
        ///     print(s)
        ///     // Prints "(21, 30)"
        ///
        /// The conversion of `p` to a string in the assignment to `s` uses the
        /// `Point` type's `description` property.
        public var description: String { get }

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: DictationTranscriber.Result, b: DictationTranscriber.Result) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public typealias Results = some Sendable & AsyncSequence<DictationTranscriber.Result, any Error>

    @objc deinit
}

/**
 A module that requires locale-specific assets.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public protocol LocaleDependentSpeechModule : SpeechModule {

    /**
     The set of all possible asset locales that the module supports.
     */
    static var supportedLocales: [Locale] { get async }

    /**
     A locale from the module's supported locales equivalent to the given locale.
     
     Use this method to determine which of this module's supported locales is equivalent to an arbitrary locale such as `Locale.current`. Use this method instead of `supportedLocales.contains(_:)`; two locales may be equivalent but not equal, and `contains(_:)` uses equality rather than equivalence.
     
     - Parameter locale: An arbitrary locale.
     - Returns: A locale in the supported locales list, or `nil` if there is no equivalent locale in that list.
     */
    static func supportedLocale(equivalentTo locale: Locale) async -> Locale?

    /**
     The set of asset locales specified by the module's configuration.
     */
    var selectedLocales: [Locale] { get }
}

/**
 An object that generates and exports custom language model training data.
 */
@available(macOS 14, iOS 17, visionOS 1.1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public class SFCustomLanguageModelData : Hashable, Codable {

    /** A phrase used to bias the language model, along with a weight influencing the relative strength of the bias. */
    public struct PhraseCount : Hashable, Sendable, CustomStringConvertible, Codable, DataInsertable {

        public let phrase: String

        public let count: Int

        public init(phrase: String, count: Int)

        /// A textual representation of this instance.
        ///
        /// Calling this property directly is discouraged. Instead, convert an
        /// instance of any type to a string by using the `String(describing:)`
        /// initializer. This initializer works with any type, and uses the custom
        /// `description` property for types that conform to
        /// `CustomStringConvertible`:
        ///
        ///     struct Point: CustomStringConvertible {
        ///         let x: Int, y: Int
        ///
        ///         var description: String {
        ///             return "(\(x), \(y))"
        ///         }
        ///     }
        ///
        ///     let p = Point(x: 21, y: 30)
        ///     let s = String(describing: p)
        ///     print(s)
        ///     // Prints "(21, 30)"
        ///
        /// The conversion of `p` to a string in the assignment to `s` uses the
        /// `Point` type's `description` property.
        public var description: String { get }

        public func insert(data: SFCustomLanguageModelData)

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SFCustomLanguageModelData.PhraseCount, b: SFCustomLanguageModelData.PhraseCount) -> Bool

        /// Encodes this value into the given encoder.
        ///
        /// If the value fails to encode anything, `encoder` will encode an empty
        /// keyed container in its place.
        ///
        /// This function throws an error if any values are invalid for the given
        /// encoder's format.
        ///
        /// - Parameter encoder: The encoder to write data to.
        public func encode(to encoder: any Encoder) throws

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }

        /// Creates a new instance by decoding from the given decoder.
        ///
        /// This initializer throws an error if reading from the decoder fails, or
        /// if the data read is corrupted or otherwise invalid.
        ///
        /// - Parameter decoder: The decoder to read data from.
        public init(from decoder: any Decoder) throws
    }

    /**
     * A term to be introduced into the speech recognition model's vocabulary.
     *
     * Attempts to add terms that are already in the model's vocabulary will be ignored.
     * Pronunciations that use X-SAMPA symbols that are not supported will be ignored;
     * see ``SFCustomLanguageModelData/supportedPhonemes(locale:)`` for the set of supported symbols.
     */
    public struct CustomPronunciation : Hashable, Sendable, CustomStringConvertible, Codable, DataInsertable {

        /// The written representation of the term, the way it is expected to appear in transcriptions.
        public let grapheme: String

        /// Zero or more phonetic representations of the term, given as X-SAMPA strings.
        public let phonemes: [String]

        public init(grapheme: String, phonemes: [String])

        /// A textual representation of this instance.
        ///
        /// Calling this property directly is discouraged. Instead, convert an
        /// instance of any type to a string by using the `String(describing:)`
        /// initializer. This initializer works with any type, and uses the custom
        /// `description` property for types that conform to
        /// `CustomStringConvertible`:
        ///
        ///     struct Point: CustomStringConvertible {
        ///         let x: Int, y: Int
        ///
        ///         var description: String {
        ///             return "(\(x), \(y))"
        ///         }
        ///     }
        ///
        ///     let p = Point(x: 21, y: 30)
        ///     let s = String(describing: p)
        ///     print(s)
        ///     // Prints "(21, 30)"
        ///
        /// The conversion of `p` to a string in the assignment to `s` uses the
        /// `Point` type's `description` property.
        public var description: String { get }

        public func insert(data: SFCustomLanguageModelData)

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SFCustomLanguageModelData.CustomPronunciation, b: SFCustomLanguageModelData.CustomPronunciation) -> Bool

        /// Encodes this value into the given encoder.
        ///
        /// If the value fails to encode anything, `encoder` will encode an empty
        /// keyed container in its place.
        ///
        /// This function throws an error if any values are invalid for the given
        /// encoder's format.
        ///
        /// - Parameter encoder: The encoder to write data to.
        public func encode(to encoder: any Encoder) throws

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }

        /// Creates a new instance by decoding from the given decoder.
        ///
        /// This initializer throws an error if reading from the decoder fails, or
        /// if the data read is corrupted or otherwise invalid.
        ///
        /// - Parameter decoder: The decoder to read data from.
        public init(from decoder: any Decoder) throws
    }

    /// A custom parameter attribute that constructs custom language model data from closures.
    ///
    /// The `SFCustomLanguageModelData` class provides two methods for accumulating data: manually
    /// constructing `PhraseCount` and `CustomPronunciation` objects and providing them using the `insert`
    /// methods defined below, or by using the result builder DSL upon initialization. This type supports the latter.
    @resultBuilder public struct DataInsertableBuilder {

        /// Combines statement blocks into a single product.
        public static func buildBlock(_ components: any DataInsertable...) -> any DataInsertable

        /// Enables support for `if-else` and `switch` constructs.
        public static func buildEither(first: any DataInsertable) -> any DataInsertable

        /// Enables support for `if-else` and `switch` constructs.
        public static func buildEither(second: any DataInsertable) -> any DataInsertable

        /// Enables support for `if` statements that do not have an `else` clause.
        public static func buildOptional(_ component: (any DataInsertable)?) -> any DataInsertable

        /// Enables support for `for..in` loops.
        public static func buildArray(_ components: [any DataInsertable]) -> any DataInsertable
    }

    /// Abstract base class defining the interface for classes that generate `PhraseCount` via an iterator.
    public class PhraseCountGenerator : Hashable, Codable, AsyncSequence, DataInsertable {

        /// The type of asynchronous iterator that produces elements of this
        /// asynchronous sequence.
        public typealias AsyncIterator = SFCustomLanguageModelData.PhraseCountGenerator.Iterator

        /// The type of element produced by this asynchronous sequence.
        public typealias Element = SFCustomLanguageModelData.PhraseCount

        /// Creates the asynchronous iterator that produces elements of this
        /// asynchronous sequence.
        ///
        /// - Returns: An instance of the `AsyncIterator` type used to produce
        /// elements of the asynchronous sequence.
        public func makeAsyncIterator() -> SFCustomLanguageModelData.PhraseCountGenerator.Iterator

        public init()

        public class Iterator : AsyncIteratorProtocol {

            public typealias Element = SFCustomLanguageModelData.PhraseCount

            /// Asynchronously advances to the next element and returns it, or ends the
            /// sequence if there is no next element.
            ///
            /// - Returns: The next element, if it exists, or `nil` to signal the end of
            ///   the sequence.
            public func next() async throws -> SFCustomLanguageModelData.PhraseCount?

            @objc deinit
        }

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (lhs: SFCustomLanguageModelData.PhraseCountGenerator, rhs: SFCustomLanguageModelData.PhraseCountGenerator) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        public func insert(data: SFCustomLanguageModelData)

        @objc deinit

        /// Encodes this value into the given encoder.
        ///
        /// If the value fails to encode anything, `encoder` will encode an empty
        /// keyed container in its place.
        ///
        /// This function throws an error if any values are invalid for the given
        /// encoder's format.
        ///
        /// - Parameter encoder: The encoder to write data to.
        public func encode(to encoder: any Encoder) throws

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }

        /// Creates a new instance by decoding from the given decoder.
        ///
        /// This initializer throws an error if reading from the decoder fails, or
        /// if the data read is corrupted or otherwise invalid.
        ///
        /// - Parameter decoder: The decoder to read data from.
        required public init(from decoder: any Decoder) throws
    }

    /// A `PhraseCountGenerator` that produces `PhraseCount` values based on templates.
    public class TemplatePhraseCountGenerator : SFCustomLanguageModelData.PhraseCountGenerator {

        public struct Template : Hashable, Codable, TemplateInsertable {

            public let body: String

            public let count: Int

            public init(_ body: String, count: Int)

            public func insert(generator: SFCustomLanguageModelData.TemplatePhraseCountGenerator)

            /// Returns a Boolean value indicating whether two values are equal.
            ///
            /// Equality is the inverse of inequality. For any values `a` and `b`,
            /// `a == b` implies that `a != b` is `false`.
            ///
            /// - Parameters:
            ///   - lhs: A value to compare.
            ///   - rhs: Another value to compare.
            public static func == (a: SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template, b: SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template) -> Bool

            /// Encodes this value into the given encoder.
            ///
            /// If the value fails to encode anything, `encoder` will encode an empty
            /// keyed container in its place.
            ///
            /// This function throws an error if any values are invalid for the given
            /// encoder's format.
            ///
            /// - Parameter encoder: The encoder to write data to.
            public func encode(to encoder: any Encoder) throws

            /// Hashes the essential components of this value by feeding them into the
            /// given hasher.
            ///
            /// Implement this method to conform to the `Hashable` protocol. The
            /// components used for hashing must be the same as the components compared
            /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
            /// with each of these components.
            ///
            /// - Important: In your implementation of `hash(into:)`,
            ///   don't call `finalize()` on the `hasher` instance provided,
            ///   or replace it with a different instance.
            ///   Doing so may become a compile-time error in the future.
            ///
            /// - Parameter hasher: The hasher to use when combining the components
            ///   of this instance.
            public func hash(into hasher: inout Hasher)

            /// The hash value.
            ///
            /// Hash values are not guaranteed to be equal across different executions of
            /// your program. Do not save hash values to use during a future execution.
            ///
            /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
            ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
            ///   The compiler provides an implementation for `hashValue` for you.
            public var hashValue: Int { get }

            /// Creates a new instance by decoding from the given decoder.
            ///
            /// This initializer throws an error if reading from the decoder fails, or
            /// if the data read is corrupted or otherwise invalid.
            ///
            /// - Parameter decoder: The decoder to read data from.
            public init(from decoder: any Decoder) throws
        }

        public class Iterator : SFCustomLanguageModelData.PhraseCountGenerator.Iterator {

            public typealias Element = SFCustomLanguageModelData.PhraseCount

            public init(templates: [SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template], templateClasses: [String : [String]])

            override public func next() async throws -> SFCustomLanguageModelData.PhraseCount?

            @objc deinit
        }

        /// Add a template to be used to generate data samples.
        ///
        /// - Parameters:
        ///     - template: A string, possibly containing references to classes enclosed in angle brackets.
        ///     - count: the total number of data samples that will be generated by expanding the template string.
        public func insert(template: String, count: Int)

        /// Define a class of tokens to be used in template strings.
        ///
        /// - Parameters:
        ///     - className: A string which will appear in template strings inside of angle brackets.
        ///     - values: The set of values which may be substituted into the template strings.
        public func define(className: String, values: [String])

        override public func makeAsyncIterator() -> SFCustomLanguageModelData.PhraseCountGenerator.Iterator

        public static func == (lhs: SFCustomLanguageModelData.TemplatePhraseCountGenerator, rhs: SFCustomLanguageModelData.TemplatePhraseCountGenerator) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        override public func hash(into hasher: inout Hasher)

        override public init()

        required public init(from decoder: any Decoder) throws

        @objc deinit
    }

    /** A class supporting the custom language model training data result builder. You are not intended to use this directly. */
    public struct CompoundTemplate : TemplateInsertable {

        public init(_ components: [any TemplateInsertable])

        public func insert(generator: SFCustomLanguageModelData.TemplatePhraseCountGenerator)
    }

    /// A custom parameter attribute that constructs custom language model data from closures.
    ///
    /// Phrase counts can be generated manually by providing an exact phrase and weight (e.g. "Play the Albin counter gambit") or
    /// from templates (e.g. "Move my \<piece> to \<square>"). Templates themselves can be constructed manually, or using
    /// the result builder DSL. This type supports the latter.
    @resultBuilder public struct TemplateInsertableBuilder {

        /// Combines statement blocks into a single product.
        public static func buildBlock(_ components: any TemplateInsertable...) -> any TemplateInsertable

        /// Enables support for `if-else` and `switch` constructs.
        public static func buildEither(first: any TemplateInsertable) -> any TemplateInsertable

        /// Enables support for `if-else` and `switch` constructs.
        public static func buildEither(second: any TemplateInsertable) -> any TemplateInsertable

        /// Enables support for `if` statements that do not have an `else` clause.
        public static func buildOptional(_ component: (any TemplateInsertable)?) -> any TemplateInsertable

        /// Enables support for `for..in` loops.
        public static func buildArray(_ components: [any TemplateInsertable]) -> any TemplateInsertable
    }

    /// A type that can be used to construct custom language model data by specifying a set of template classes and using the
    /// result builder DSL to specify templates.
    public struct PhraseCountsFromTemplates : DataInsertable {

        public init(classes: [String : [String]], @SFCustomLanguageModelData.TemplateInsertableBuilder builder: () -> any TemplateInsertable)

        public func insert(data: SFCustomLanguageModelData)
    }

    final public let locale: Locale

    final public let identifier: String

    final public let version: String

    /// List the supported subset of X-SAMPA pronunciations supported by this locale for the Speech framework.
    ///
    /// SFCustomLanguageModelData accepts custom pronunciations whose phonetic representations are spelled out
    /// using an alphabet of pronunciations called the Extended Speech Assessment Methods Public Alphabet, or
    /// X-SAMPA. X-SAMPA consists of ASCII characters that, individually or in combination, represents sounds
    /// made by people when speaking, and is preferred in this context over the International Phonetic Alphabet
    /// (IPA) for ease of typing. Each locale supports only a subset of all possible sounds represented by
    /// X-SAMPA symbols, and this method exists to allow developers to query for the set of sounds that can be
    /// used for a given locale's custom pronunciations facility.
    ///
    /// - Parameters:
    ///     - locale: the region and language whose supported pronunciations are being queried
    public static func supportedPhonemes(locale: Locale) -> [String]

    /// Constructs an empty data container.
    ///
    /// The `SFCustomLanguageModelData` class accumulates language model training
    /// and custom vocabulary data, both associated with a specified locale. This initializer
    /// creates an object that initially holds no data.
    ///
    /// - Parameters:
    ///     - locale: the region and language of the training data (must match with the locale used to construct the `SFSpeechRecognizer` later)
    ///     - identifier: used to uniquely identify the resulting language model on the device where it will be processed
    ///     - version: used to distinguish different versions of the language model on the device where it will be processed
    public init(locale: Locale, identifier: String, version: String)

    /// Constructs a data container using a builder
    ///
    /// The `SFCustomLanguageModelData` class accumulates language model training
    /// and custom vocabulary data, both associated with a specified locale. This initializer
    /// creates an object that is initially populated using the provided builder.
    ///
    /// - Parameters:
    ///     - locale: the region and language of the training data (must match with the locale used to construct the `SFSpeechRecognizer` later)
    ///     - identifier: used to uniquely identify the resulting language model on the device where it will be processed
    ///     - version: used to distinguish different versions of the language model on the device where it will be processed
    ///     - builder: a DataInsertableBuilder object that yields DataInsertable objects
    public convenience init(locale: Locale, identifier: String, version: String, @SFCustomLanguageModelData.DataInsertableBuilder builder: () -> any DataInsertable)

    /// Add a sample to the body of training data.
    ///
    /// This class accumulates text data that will later be used to train a language model, which can
    /// be provided to an `SFSpeechRecognizer` to improve performance on certain phrases.
    ///
    /// - Parameters:
    ///     - phraseCount: A sample of text on which to train your custom language model
    public func insert(phraseCount: SFCustomLanguageModelData.PhraseCount)

    /// Add a stream of samples to the body of training data.
    ///
    /// This class accumulates text data that will later be used to train a language model, which can
    /// be provided to an `SFSpeechRecognizer` to improve performance on certain phrases.
    ///
    /// - Parameters:
    ///     - phraseCountGenerator: A generator of phrase counts
    public func insert(phraseCountGenerator: SFCustomLanguageModelData.PhraseCountGenerator)

    /// Add a custom term to the vocabulary.
    ///
    /// This class accumulates vocabulary data (in the form of tokens paired with X-SAMPA representations
    /// of the spoken forms of those tokens) which will later be processed and then provided to an `SFSpeechRecognizer`,
    /// to enable it to recognize words that are typically out-of-vocabulary.
    ///
    /// - Parameters:
    ///     - term: A token, paired with an X-SAMPA representation of the token's pronunciation
    public func insert(term: SFCustomLanguageModelData.CustomPronunciation)

    /// Export the accumulated data to a file.
    ///
    /// The file produced by this method can be provided to `SFSpeechLanguageModel.prepareCustomLanguageModel`
    /// to produce language model and vocabulary files that are then ready to be used in conjunction with the `SFSpeechRecognizer`.
    ///
    /// - Parameters:
    ///     - path: a URL where the exported data will be saved.
    ///
    /// - Throws: Errors related to creating directories and files, and deleting files
    public func export(to path: URL) async throws

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (lhs: SFCustomLanguageModelData, rhs: SFCustomLanguageModelData) -> Bool

    /// Hashes the essential components of this value by feeding them into the
    /// given hasher.
    ///
    /// Implement this method to conform to the `Hashable` protocol. The
    /// components used for hashing must be the same as the components compared
    /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
    /// with each of these components.
    ///
    /// - Important: In your implementation of `hash(into:)`,
    ///   don't call `finalize()` on the `hasher` instance provided,
    ///   or replace it with a different instance.
    ///   Doing so may become a compile-time error in the future.
    ///
    /// - Parameter hasher: The hasher to use when combining the components
    ///   of this instance.
    public func hash(into hasher: inout Hasher)

    @objc deinit

    /// Encodes this value into the given encoder.
    ///
    /// If the value fails to encode anything, `encoder` will encode an empty
    /// keyed container in its place.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: any Encoder) throws

    /// The hash value.
    ///
    /// Hash values are not guaranteed to be equal across different executions of
    /// your program. Do not save hash values to use during a future execution.
    ///
    /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
    ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
    ///   The compiler provides an implementation for `hashValue` for you.
    public var hashValue: Int { get }

    /// Creates a new instance by decoding from the given decoder.
    ///
    /// This initializer throws an error if reading from the decoder fails, or
    /// if the data read is corrupted or otherwise invalid.
    ///
    /// - Parameter decoder: The decoder to read data from.
    required public init(from decoder: any Decoder) throws
}

/**
 Analyzes spoken audio content in various ways and manages the analysis session.
 
 The Speech framework provides several modules that can be added to an analyzer to provide specific types of analysis and transcription. Many use cases only need a ``SpeechTranscriber`` module, which performs speech-to-text transcriptions.

 The `SpeechAnalyzer` class is responsible for:
 - Holding associated modules
 - Accepting audio speech input
 - Controlling the overall analysis

 Each module is responsible for:
 - Providing guidance on acceptable input
 - Providing its analysis or transcription output

 Analysis is asynchronous. Input, output, and session control are decoupled and typically occur over several different tasks created by you or by the session. In particular, where an Objective-C API might use a delegate to provide results to you, the Swift API's modules provides their results via an `AsyncSequence`. Similarly, you provide speech input to this API via an `AsyncSequence` you create and populate.
 
 The analyzer can only analyze one input sequence at a time.
 
 ### Perform analysis

 To perform analysis on audio files and streams, follow these general steps:

 1. Create and configure the necessary modules.
 2. Ensure the relevant assets are installed or already present. See ``AssetInventory``.
 3. Create an input sequence you can use to provide the spoken audio.
 4. Create and configure the analyzer with the modules and input sequence.
 5. Supply audio.
 6. Start analysis.
 7. Act on results.
 8. Finish analysis when desired.

 This example shows how you could perform an analysis that transcribes audio using the `SpeechTranscriber` module:

 ```swift
 import Speech

 // Step 1: Modules
 guard let locale = SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
     /* Note unsupported language */
 }
 let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)

 // Step 2: Assets
 if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
     try await installationRequest.downloadAndInstall()
 }
 
 // Step 3: Input sequence
 let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)

 // Step 4: Analyzer
 let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
 let analyzer = SpeechAnalyzer(modules: [transcriber])

 // Step 5: Supply audio
 Task {
     while /* audio remains */ {
         /* Get some audio */
         /* Convert to audioFormat */
         let pcmBuffer = /* an AVAudioPCMBuffer containing some converted audio */
         let input = AnalyzerInput(buffer: pcmBuffer)
         inputBuilder.yield(input)
     }
     inputBuilder.finish()
 }

 // Step 7: Act on results
 Task {
     do {
         for try await result in transcriber.results {
             let bestTranscription = result.text // an AttributedString
             let plainTextBestTranscription = String(bestTranscription.characters) // a String
             print(plainTextBestTranscription)
         }
     } catch {
         /* Handle error */
     }
 }

 // Step 6: Perform analysis
 let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)

 // Step 8: Finish analysis
 if let lastSampleTime {
     try await analyzer.finalizeAndFinish(through: lastSampleTime)
 } else {
     try analyzer.cancelAndFinishNow()
 }
 ```

 ### Analyze audio files
 
 To analyze one or more audio files represented by an `AVAudioFile` object, call methods such as ``analyzeSequence(from:)`` or ``start(inputAudioFile:finishAfterFile:)``, or create the analyzer with one of the initializers that has a file parameter. These methods automatically convert the file to a supported audio format and process the file in its entirety.
 
 To end the analysis session after one file, pass `true` for the `finishAfterFile` parameter or call one of the `finish` methods.
 
 Otherwise, by default, the analyzer won't terminate its result streams and will wait for additional audio files or buffers. The analysis session doesn't reset the audio timeline after each file; the next audio is assumed to come immediately after the completed file.
 
 ### Analyze audio buffers
 
 To analyze audio buffers directly, convert them to a supported audio format, either on the fly or in advance. You can use ``bestAvailableAudioFormat(compatibleWith:)-([SpeechModule])`` or individual modules' ``SpeechModule/availableCompatibleAudioFormats`` methods to select a format to convert to.
 
 Create an ``AnalyzerInput`` object for each audio buffer and add the object to an input sequence you create. Supply that input sequence to ``analyzeSequence(_:)``, ``start(inputSequence:)``, or a similar parameter of the analyzer's initializer.
 
 To skip past part of an audio stream, omit the buffers you want to skip from the input sequence. When you resume analysis with a later buffer, you can ensure the time-code of each module’s result accounts for the skipped audio. To do this, pass the later buffer’s time-code within the audio stream as the `bufferStartTime` parameter of the later `AnalyzerInput` object.
 
 ### Analyze autonomously
 
 You can and usually should perform analysis using the ``analyzeSequence(_:)`` or ``analyzeSequence(from:)`` methods; those methods work well with Swift structured concurrency techniques. However, you may prefer that the analyzer proceed independently and perform its analysis autonomously as audio input becomes available in a task managed by the analyzer itself.
 
 To use this capability, create the analyzer with one of the initializers that has an input sequence or file parameter, or call ``start(inputSequence:)`` or ``start(inputAudioFile:finishAfterFile:)``. To end the analysis when the input ends, call ``finalizeAndFinishThroughEndOfInput()``. To end the analysis of that input and start analysis of different input, call one of the `start` methods again.
 
 ### Control processing and timing of results
 
 Modules deliver results periodically, but you can manually synchronize their processing and delivery to outside cues.
 
 To deliver a result for a particular time-code, call ``finalize(through:)``. To cancel processing of results that are no longer of interest, call ``cancelAnalysis(before:)``.

 ### Improve responsiveness
 
 By default, the analyzer and modules load the system resources that they require lazily, and unload those resources when they're deallocated.
 
 To proactively load system resources and "preheat" the analyzer, call ``prepareToAnalyze(in:)`` after setting its modules. This may improve how quickly the modules return their first results.
 
 To delay or prevent unloading an analyzer's resources — caching them for later use by a different analyzer instance — you can select a ``SpeechAnalyzer/Options/ModelRetention`` option and create the analyzer with an appropriate ``SpeechAnalyzer/Options`` object.
 
 To set the priority of analysis work, create the analyzer with a ``SpeechAnalyzer/Options`` object given a `priority` value.
 
 Specific modules may also offer options that improve responsiveness.
 
 ### Finish analysis
 
 To end an analysis session, you must use one of the analyzer's `finish` methods or parameters, or deallocate the analyzer.
 
 When the analysis session transitions to the _finished_ state:
 - The analyzer won't take additional input from the input sequence
 - Most methods won't do anything; in particular, the analyzer won't accept different input sequences or modules
 - Module result streams terminate and modules won't publish additional results, though the app can continue to iterate over already-published results
 
 > Note: While you can terminate the input sequence you created with a method such as `AsyncStream.Continuation.finish()`, finishing the input sequence does _not_ cause the analysis session to become finished, and you can continue the session with a different input sequence.
 
 ### Respond to errors
 
 When the analyzer or its modules' result streams throw an error, the analysis session becomes finished as described above, and the same error (or a `CancellationError`) is thrown from all waiting methods and result streams.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public actor SpeechAnalyzer : Sendable {

    /**
         Creates an analyzer.
    
         - Parameters:
            - modules: An initial list of modules to add to the analyzer. The list can be empty; modules can be added or removed later.
            - options: A structure specifying analysis options.
         */
    public convenience init(modules: [any SpeechModule], options: SpeechAnalyzer.Options? = nil)

    /**
         Creates an analyzer and begins analysis.
    
         - Parameters:
            - inputSequence: An asynchronous sequence of audio inputs to analyze. Analysis will begin when the first audio input is added to the sequence.
            - modules: An initial list of modules that will analyze the audio.
            - options: A structure specifying analysis options.
            - analysisContext: An object containing contextual information to improve or inform the analysis.
            - volatileRangeChangedHandler: A closure called to report the analysis' progress. The closure takes the following parameters:
                - term range: The current volatile range.
                - term changedStart: If `true`, the volatile range contains an updated start time. This indicates that prior results have been finalized.
                - term changedEnd: If `true`, the volatile range contains an update end time. This indicates that analysis of that time has started.
        */
    public convenience init<InputSequence>(inputSequence: InputSequence, modules: [any SpeechModule], options: SpeechAnalyzer.Options? = nil, analysisContext: AnalysisContext = .init(), volatileRangeChangedHandler: sending ((_ range: CMTimeRange, _ changedStart: Bool, _ changedEnd: Bool) -> Void)? = nil) where InputSequence : Sendable, InputSequence : AsyncSequence, InputSequence.Element == AnalyzerInput

    /**
     Prepares the analyzer to begin work with minimal startup delay.
     
     The analyzer normally performs some configuration lazily as the first audio input becomes available. This method performs that work immediately to reduce or eliminate delays in analyzing the first audio input.
     
     - Parameter audioFormat: An audio format describing the expected input. The analyzer will load assets appropriate for the given format. If `nil` or if the input is not in this format, the analyzer will reconfigure itself when it processes the actual audio.
     */
    final public func prepareToAnalyze(in audioFormat: AVAudioFormat?) async throws

    /**
         Prepares the analyzer to begin work with minimal startup delay, reporting the progress of that preparation.
    
         - Parameters:
            - audioFormat: An audio format describing the expected input. The analyzer will load assets appropriate for the given format. If `nil` or if the input is not in this format, the analyzer will reconfigure itself when it processes the actual audio.
            - progressReadyHandler: A closure that this method calls when progress reporting becomes available. The closure takes the following parameter:
                - term progress: A `Progress` object that reports the progress of the preparation work.
         */
    final public func prepareToAnalyze(in audioFormat: AVAudioFormat?, withProgressReadyHandler progressReadyHandler: sending ((Progress) -> Void)?) async throws

    @objc deinit

    /**
     The modules performing analysis on the audio input.
     */
    final public var modules: [any SpeechModule] { get }

    /**
     Adds or removes modules.
     
     Modules can be added or removed to the analyzer mid-stream. A newly-added module will immediately begin analysis on new audio input, but it will not have access to already-analyzed audio. However, you may keep a copy of previously-analyzed audio and provide it to a separate analyzer.
     
     Modules cannot be reused from a different analyzer.
     
     - Parameter newModules: A list of modules to include in the analyzer. These modules replace the previous modules, but you may preserve previous modules by including them in the list.
     */
    final public func setModules(_ newModules: [any SpeechModule]) async throws

    /**
     Starts analysis of an input sequence and returns immediately.
     
     This method stops the autonomous analysis of the previous input sequence. To ensure the previous sequence's input is fully consumed, call ``finalize(through:)`` first.
     
     The previous input sequence may be rendered inoperable depending on its implementation.
     
     - Parameter inputSequence: A new input sequence.
     */
    final public func start<InputSequence>(inputSequence: InputSequence) async throws where InputSequence : Sendable, InputSequence : AsyncSequence, InputSequence.Element == AnalyzerInput

    /**
     Analyzes an input sequence, returning when the sequence is consumed.
     
     When this method returns, the input sequence will have been consumed, but the last of the audio may still be undergoing analysis. To wait for the analysis to complete, call another method such as ``finalize(through:)`` and await its return.
     
     - Parameter inputSequence: An input sequence to analyze.
     - Returns: The time-code of the last audio sample of the input, or `nil` if the input sequence was empty. You may use this value for the parameter of ``finalizeAndFinish(through:)`` (or other methods).
     */
    final public func analyzeSequence<InputSequence>(_ inputSequence: InputSequence) async throws -> CMTime? where InputSequence : Sendable, InputSequence : AsyncSequence, InputSequence.Element == AnalyzerInput

    /**
     Finalizes the modules' analyses.
     
     At the return of this method, input up to and including the given time will have been analyzed. Modules will have published the finalized results to their stream, but the application may not have consumed them from the stream yet. ``volatileRange`` will post-date the given time.
     
     If the given time has already been finalized (it pre-dates the volatile range), then this method does nothing.
     
     - Parameter through:
        Finalizes up to and including the given time-code. If the analyzer hasn't already taken that audio from the input sequence, the method waits until analysis proceeds to that audio before finalizing.
     
        If `nil`, finalizes up to and including the last audio the analyzer _has_ taken from the input sequence, and if the analyzer has not taken any audio from the input sequence, this method does nothing.
     
     - Throws: Various errors including `CancellationError` if analysis is finished early before the given input time
     */
    final public func finalize(through: CMTime?) async throws

    /**
         Finishes analysis after an audio input sequence has been fully consumed and its results are finalized.
    
         This method waits until the input sequence has terminated, then finalizes like ``finalize(through:)`` and finishes analysis like ``finish(after:)``.
         
         If the input sequence is replaced using one of the `start` methods, this method continues waiting for the replacement input sequence to terminate.
         
         - Throws: `CancellationError` if analysis is finished early before the end of input
         */
    final public func finalizeAndFinishThroughEndOfInput() async throws

    /**
         Finishes analysis after finalizing results for a given time-code.
         
         This method finalizes like ``finalize(through:)`` and finishes analysis like ``finish(after:)``.
         
         - Parameter through: A time-code of the last audio sample that you want to analyze.
    
         - Throws: Various errors including `CancellationError` if analysis is finished early before the given input time.
         */
    final public func finalizeAndFinish(through: CMTime) async throws

    /**
         Finishes analysis once input for a given time is consumed.
         
         In most cases, you can call ``finalizeAndFinish(through:)`` or ``cancelAndFinishNow()`` instead. Those methods also finish analysis.
         
         At the return of this method, the modules' result streams will have ended and the modules will not accept further input from the input sequence. The analyzer will not be able to resume analysis with a different input sequence and will not accept module changes; most methods will do nothing.
         
         Analysis of input up to and including the given time may or may not have been completed. Modules will not publish _additional_ results to their streams, but the application can read any results the modules have _already_ published. To ensure analysis is completed or skipped before finishing, call ``finalize(through:)`` or ``cancelAnalysis(before:)``.
         
         You do not need to call this method before releasing this analyzer or its modules.
              
         - Parameter after: An audio time marking the end of the analysis session.
    
         - Throws: `CancellationError` if analysis is finished early before the given input time.
         */
    final public func finish(after: CMTime) async throws

    /**
     Stops analyzing audio predating the given time.
     
     This method is useful in live-audio cases where you are no longer interested in results predating a certain time. For example, when you are captioning video and the scene changes, you do not need pending captions from the previous scene.
     
     This method can also be used to force "catch-up" if the analyzer is taking too long. By calling ``finalize(through:)``, you indicate that you will _wait_ for pending results. By calling `cancelAnalysis(before:)`, you indicate that you _cannot wait_ any longer for certain pending results.
     
     Analysis will continue normally at and after the given time.
     
     If you know in advance that you do not need results for a given range of audio, it is preferable to simply not provide that audio as input.
     
     This is a best-effort cancellation. The implementation may still publish results from before the given time.
     
     - Parameter before: An audio time that marks audio that remains of interest.
     */
    final public func cancelAnalysis(before: CMTime)

    /**
     Finishes analysis immediately.
     
     This method cancels all pending work and then finishes analysis. It works similarly to calling ``cancelAnalysis(before:)`` and then ``finish(after:)``, but unlike `finish(after:)`, this method is able to finish analysis prior to any input. The post-conditions for this method are identical to `finish(after:)`.
     
     You do not need to call this method before releasing this analyzer or its modules.
     */
    final public func cancelAndFinishNow() async

    /**
     The range of results that can change.
     
     This property conveys the "finalized" idea. Results within the volatile range may be replaced by updated results, but results that lie outside the volatile range will not be replaced. The application can safely consolidate results that lay outside the range.
     
     The volatile range includes pending analyses—audio that has been sent out but where no results have come back yet. If there aren't any pending results and the modules aren't supplying volatile results—if all the previously-sent results are final—the volatile range is empty.
     
     - `volatileRange.start` is the start of the non-final results and the start of the input that is subject to ongoing analysis
     - `volatileRange.end` is the extent of the input that is subject to ongoing analysis after being dequeued from the input sequence
     
     A module is not required to provide new, final results for audio ranges that were previously volatile but otherwise unchanged by finalization. However, you can create two modules—one that provides both volatile and final results, and a second that only provides final results—and process results from the latter differently.
     
     The volatile range is `nil` if no input has been received.
     */
    final public var volatileRange: CMTimeRange? { get }

    /**
     A closure that the analyzer calls when the volatile range changes.
     
     You can use this handler to manage audio input resources and monitor progress.
     
     You can also use this handler to respond to result finalization, but the better tool for that job is the ``SpeechModuleResult/resultsFinalizationTime`` property of a module's results. When the analyzer calls this handler, the application may not have consumed the result from the stream yet; this handler may be called with a new volatile range while there are still results prior to the new volatile range waiting to be consumed.
     
     This closure replaces any handler you specified when creating the analyzer.
     
     - Parameter handler: A closure called to report the analysis' progress. The closure takes the following parameters:
         - term range: The current volatile range.
         - term changedStart: If `true`, the volatile range contains an updated start time. This indicates that prior results have been finalized.
         - term changedEnd: If `true`, the volatile range contains an update end time. This indicates that analysis of that time has started.
     */
    final public func setVolatileRangeChangedHandler(_ handler: sending ((_ range: CMTimeRange, _ changedStart: Bool, _ changedEnd: Bool) -> Void)?)

    /**
     An object containing contextual information.
     */
    final public var context: AnalysisContext { get async }

    /**
     Sets contextual information to improve or inform the analysis.
     
     Other analyzer instances may use the same context object.
     
     - Parameter newContext: A context object. This object will replace the current object.
     */
    final public func setContext(_ newContext: AnalysisContext) async throws

    /**
     Retrieves the best-quality audio format that the specified modules can work with, from assets installed on the device.
     
     Use this method to set up an audio pipeline or pre-convert audio to a usable format. In order to keep `CMTime` values sample-accurate, the analyzer does not transparently upsample, downsample, or convert audio input.
     
     - Parameter modules: A list of modules that will be analyzing the audio.
     - Returns: `nil` if the specified modules require you to install additional assets.
     */
    public static func bestAvailableAudioFormat(compatibleWith modules: [any SpeechModule]) async -> AVAudioFormat?

    /**
         Retrieves the best-quality audio format that the specified modules can work with, taking into account the natural format of the audio and assets installed on the device.
         
         Use this method to set up an audio pipeline or pre-convert audio to a usable format. In order to keep `CMTime` values sample-accurate, the analyzer does not transparently upsample, downsample, or convert audio input.
    
         - Parameter modules: A list of modules that will be analyzing the audio.
         - Parameter naturalFormat: An audio format that you prefer to work with, or `nil` if you have no preference.
         - Returns: `nil` if the specified modules require you to install additional assets.
         */
    public static func bestAvailableAudioFormat(compatibleWith modules: [any SpeechModule], considering naturalFormat: AVAudioFormat?) async -> AVAudioFormat?

    /// Retrieve the executor for this actor as an optimized, unowned
    /// reference.
    ///
    /// This property must always evaluate to the same executor for a
    /// given actor instance, and holding on to the actor must keep the
    /// executor alive.
    ///
    /// This property will be implicitly accessed when work needs to be
    /// scheduled onto this actor.  These accesses may be merged,
    /// eliminated, and rearranged with other work, and they may even
    /// be introduced when not strictly required.  Visible side effects
    /// are therefore strongly discouraged within this property.
    ///
    /// - SeeAlso: ``SerialExecutor``
    /// - SeeAlso: ``TaskExecutor``
    @available(iOS 26.0, macOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    nonisolated final public var unownedExecutor: UnownedSerialExecutor { get }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SpeechAnalyzer {

    /**
     Creates an analyzer and begins analysis on an audio file.
     
     - Parameters:
        - inputAudioFile: An audio file opened for reading.
        - modules: An initial list of modules that will analyze the audio.
        - options: A structure specifying analysis options.
        - analysisContext: An object containing contextual information to improve or inform the analysis.
        - finishAfterFile: If `true`, the analysis will automatically finish after the audio file has been fully processed. Equivalent to calling ``finalizeAndFinishThroughEndOfInput()``.
        - volatileRangeChangedHandler: A closure called to report the analysis' progress. The closure takes the following parameters:
            - term range: The current volatile range.
            - term changedStart: If `true`, the volatile range contains an updated start time. This indicates that prior results have been finalized.
            - term changedEnd: If `true`, the volatile range contains an update end time. This indicates that analysis of that time has started.
    */
    public convenience init(inputAudioFile: AVAudioFile, modules: [any SpeechModule], options: SpeechAnalyzer.Options? = nil, analysisContext: AnalysisContext = .init(), finishAfterFile: Bool = false, volatileRangeChangedHandler: sending ((_ range: CMTimeRange, _ changedStart: Bool, _ changedEnd: Bool) -> Void)? = nil) async throws

    /**
         Starts analysis of an input sequence created from an audio file and returns immediately.
    
         This method stops the autonomous analysis of the previous input sequence. To ensure the previous sequence's input is fully consumed, call ``finalize(through:)`` first.
    
         - Parameters:
            - audioFile: An AVAudioFile opened for reading.
            - finishAfterFile: If `true`, the analysis will automatically finish after the audio file has been fully processed. Equivalent to calling ``finalizeAndFinishThroughEndOfInput()``.
         */
    final public func start(inputAudioFile audioFile: AVAudioFile, finishAfterFile: Bool = false) async throws

    /**
     Analyzes an input sequence created from an audio file, returning when the file has been read.
     
     When this method returns, the input sequence will have been consumed, but the last of the audio may still be undergoing analysis. To wait for the analysis to complete, call another method such as ``finalize(through:)`` and await its return.
     
     - Parameter audioFile: An AVAudioFile opened for reading.
     - Returns: The time-code of the last audio sample of the input, or `nil` if the file was empty. You may use this value for the parameter of ``finalizeAndFinish(through:)`` (or other methods).
     */
    final public func analyzeSequence(from audioFile: AVAudioFile) async throws -> CMTime?
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SpeechAnalyzer {

    /**
     Analysis processing options.
     */
    public struct Options : Sendable, Equatable {

        /**
         The priority of analysis processing work.
         
         This property determines the priority of most, but not all, processing work. You should also call the methods of `SpeechAnalyzer` and other classes from a `Task` or thread with the desired priority.
         */
        public let priority: TaskPriority

        /**
         The analyzer's model caching strategy.
         */
        public let modelRetention: SpeechAnalyzer.Options.ModelRetention

        /**
         A model caching strategy.
         */
        public enum ModelRetention : CaseIterable, Sendable, Equatable, Hashable {

            /// Releases the models when the analyzer is deallocated.
            case whileInUse

            /// Keeps the models in memory for a time so that they can be reused by another compatible analyzer session.
            case lingering

            /// Keeps the models in memory until this process exits.
            case processLifetime

            /// Returns a Boolean value indicating whether two values are equal.
            ///
            /// Equality is the inverse of inequality. For any values `a` and `b`,
            /// `a == b` implies that `a != b` is `false`.
            ///
            /// - Parameters:
            ///   - lhs: A value to compare.
            ///   - rhs: Another value to compare.
            public static func == (a: SpeechAnalyzer.Options.ModelRetention, b: SpeechAnalyzer.Options.ModelRetention) -> Bool

            /// A type that can represent a collection of all values of this type.
            @available(iOS 26.0, macOS 26.0, *)
            @available(tvOS, unavailable)
            @available(watchOS, unavailable)
            public typealias AllCases = [SpeechAnalyzer.Options.ModelRetention]

            /// A collection of all values of this type.
            nonisolated public static var allCases: [SpeechAnalyzer.Options.ModelRetention] { get }

            /// Hashes the essential components of this value by feeding them into the
            /// given hasher.
            ///
            /// Implement this method to conform to the `Hashable` protocol. The
            /// components used for hashing must be the same as the components compared
            /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
            /// with each of these components.
            ///
            /// - Important: In your implementation of `hash(into:)`,
            ///   don't call `finalize()` on the `hasher` instance provided,
            ///   or replace it with a different instance.
            ///   Doing so may become a compile-time error in the future.
            ///
            /// - Parameter hasher: The hasher to use when combining the components
            ///   of this instance.
            public func hash(into hasher: inout Hasher)

            /// The hash value.
            ///
            /// Hash values are not guaranteed to be equal across different executions of
            /// your program. Do not save hash values to use during a future execution.
            ///
            /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
            ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
            ///   The compiler provides an implementation for `hashValue` for you.
            public var hashValue: Int { get }
        }

        /**
         Creates a structure containing analysis processing options.
         - Parameters:
            - priority: A priority to apply to processing work.
            - modelRetention: A model caching strategy.
         */
        public init(priority: TaskPriority, modelRetention: SpeechAnalyzer.Options.ModelRetention)

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechAnalyzer.Options, b: SpeechAnalyzer.Options) -> Bool
    }
}

/**
 A module that performs a voice activity detection (VAD) analysis.

 This module asks "is there speech?" and provides you with the ability to gate transcription by the presence of voices, saving power otherwise used by attempting to transcribe what is likely to be silence.

 To enable voice activated transcription, initialize a ``SpeechDetector`` module. Like any other module, it can be set when first initializing SpeechAnalyzer:

 ```
 let transcriber = SpeechTranscriber(..)
 let speechDetector = SpeechDetector()
 let analyzer = SpeechAnalyzer(.., modules: [speechDetector, transcriber])
 ```

 or later on with ``SpeechAnalyzer/setModules(_:)-9xd6w``:

 ```
 let analyzer = SpeechAnalyzer(..)
 let transcriber = SpeechTranscriber(..)
 let speechDetector = SpeechDetector()
 try await analyzer.setModules([transcriber, speechDetector])
 ```

 > Important: This module only functions in conjunction with a ``SpeechTranscriber`` or ``DictationTranscriber`` module.

 > Note: For certain use cases, such as those with a lot of silence, it might be tempting to always enable voice activated transcription. But if the model drops audio that does contain speech, there could be a tradeoff between the power being saved by always having VAD enabled and potentially lower accuracy transcriptions. You can set the aggressiveness of the VAD model with ``SpeechDetector/SensitivityLevel``. While ``SpeechDetector/SensitivityLevel/medium`` is recommended for most use cases, the value of these tradeoffs will be context-specific.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class SpeechDetector {

    /**
     Creates a speech detector.
     - Parameters:
        - detectionOptions: Instance of ``SpeechDetector/DetectionOptions`` that allows clients to customize the behavior of ``SpeechDetector`` beyond its default settings.
        - reportResults: Enables the ``SpeechDetector/results`` sequence to report the VAD model's results (and any relevant errors) back to clients. The default behavior is that ``SpeechDetector`` does not report results or errors back to the client and merely enables VAD as a power optimization.
     */
    public init(detectionOptions: SpeechDetector.DetectionOptions, reportResults: Bool)

    /**
     Creates a speech detector with default settings.
     
     The default settings enable the VAD model with a value of ``SpeechDetector/SensitivityLevel/medium`` and do not report the VAD model's moment-to-moment results in its result sequence.
     */
    public convenience init()

    /**
     Determines how "aggressive" the voice activity detection (VAD) model will be.
     
     ``low`` will allow for a more "forgiving" VAD model, whereas selecting ``high`` will make the model more aggressive. ``medium`` is the recommended level for most use cases.
     */
    public enum SensitivityLevel : Int, CaseIterable, Sendable, Equatable, Hashable {

        case low

        case medium

        case high

        /// Creates a new instance with the specified raw value.
        ///
        /// If there is no value of the type that corresponds with the specified raw
        /// value, this initializer returns `nil`. For example:
        ///
        ///     enum PaperSize: String {
        ///         case A4, A5, Letter, Legal
        ///     }
        ///
        ///     print(PaperSize(rawValue: "Legal"))
        ///     // Prints "Optional(PaperSize.Legal)"
        ///
        ///     print(PaperSize(rawValue: "Tabloid"))
        ///     // Prints "nil"
        ///
        /// - Parameter rawValue: The raw value to use for the new instance.
        public init?(rawValue: Int)

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [SpeechDetector.SensitivityLevel]

        /// The raw type that can be used to represent all values of the conforming
        /// type.
        ///
        /// Every distinct value of the conforming type has a corresponding unique
        /// value of the `RawValue` type, but there may be values of the `RawValue`
        /// type that don't have a corresponding value of the conforming type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias RawValue = Int

        /// A collection of all values of this type.
        nonisolated public static var allCases: [SpeechDetector.SensitivityLevel] { get }

        /// The corresponding value of the raw type.
        ///
        /// A new instance initialized with `rawValue` will be equivalent to this
        /// instance. For example:
        ///
        ///     enum PaperSize: String {
        ///         case A4, A5, Letter, Legal
        ///     }
        ///
        ///     let selectedSize = PaperSize.Letter
        ///     print(selectedSize.rawValue)
        ///     // Prints "Letter"
        ///
        ///     print(selectedSize == PaperSize(rawValue: selectedSize.rawValue)!)
        ///     // Prints "true"
        public var rawValue: Int { get }
    }

    /**
     Allows clients to customize an instance of a speech detector.
     
     - Parameters:
        - sensitivityLevel: One of ``SpeechDetector/SensitivityLevel``. This value is used to determine how "aggressive" the voice activity detection (VAD) model will be.
     */
    public struct DetectionOptions : Sendable, Equatable, Hashable {

        public let sensitivityLevel: SpeechDetector.SensitivityLevel

        public init(sensitivityLevel: SpeechDetector.SensitivityLevel)

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechDetector.DetectionOptions, b: SpeechDetector.DetectionOptions) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    final public var results: some Sendable & AsyncSequence<SpeechDetector.Result, any Error> { get }

    /**
     A result from the speech detector. Please note, these must be enabled via ``SpeechDetector/init(detectionOptions:reportResults:)`` and currently only support error handling from the VAD model.
     */
    public struct Result : SpeechModuleResult, Sendable, CustomStringConvertible {

        /**
         The audio input range that this result applies to.
         */
        public let range: CMTimeRange

        /**
         The audio input time up to which results from this module have been finalized (after this result). The module's results are final up to but not including this time.
         
         This value is mostly equivalent to the start of ``SpeechAnalyzer/volatileRange`` after the time at which this result was published. The module publishing this result will publish no futher results with a ``range`` that encompasses a time predating this time. The module may publish results for a range that includes this time.
         
         The client can draw the following conclusions from this value and `range` (or refer to the <doc:/documentation/Speech/SpeechModuleResult/isFinal> property):
         * If `resultsFinalizationTime >= range.end` then this result is final. Additionally, all previously-provided results with a `range` predating `resultsFinalizationTime` are also final.
         * If `resultsFinalizationTime < range.end` (or `resultsFinalizationTime <= range.start`) then this result is volatile and may or may not be replaced by a result provided later.
         
         A module is not required to provide new, final results for audio ranges that it finalizes through if the previously-volatile result was unchanged by finalization. If needed, however, a client can create two modules—one that provides both volatile and final results, and a second that only provides final results—and process results from the latter differently.
         
         This value is not _exactly_ equivalent to the start of the volatile range. The ``SpeechAnalyzer/volatileRange`` property combines all modules' volatile ranges together; this property only refers to the finalization status of results from the module delivering this result.
         */
        public let resultsFinalizationTime: CMTime

        public let speechDetected: Bool

        /// A textual representation of this instance.
        ///
        /// Calling this property directly is discouraged. Instead, convert an
        /// instance of any type to a string by using the `String(describing:)`
        /// initializer. This initializer works with any type, and uses the custom
        /// `description` property for types that conform to
        /// `CustomStringConvertible`:
        ///
        ///     struct Point: CustomStringConvertible {
        ///         let x: Int, y: Int
        ///
        ///         var description: String {
        ///             return "(\(x), \(y))"
        ///         }
        ///     }
        ///
        ///     let p = Point(x: 21, y: 30)
        ///     let s = String(describing: p)
        ///     print(s)
        ///     // Prints "(21, 30)"
        ///
        /// The conversion of `p` to a string in the assignment to `s` uses the
        /// `Point` type's `description` property.
        public var description: String { get }
    }

    final public var availableCompatibleAudioFormats: [AVAudioFormat] { get }

    @available(iOS 26.0, macOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public typealias Results = some Sendable & AsyncSequence<SpeechDetector.Result, any Error>

    @objc deinit
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SpeechDetector.SensitivityLevel : RawRepresentable {
}

/**
 Namespace for methods related to model management.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public enum SpeechModels {

    /**
     Releases all models held by cached recognizer instances. The method does not return until all models are released.
     */
    public static func endRetention() async
}

/**
 Protocol that all analyzer modules conform to.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public protocol SpeechModule : AnyObject, Sendable {

    /**
     An asynchronous sequence containing this module's analysis results. Results are added to the sequence as they are created.
     
     Each module has its own result sequence and data structure.
     
     If there is an error in the overall analysis, all modules will throw the error from their individual result sequence.
     */
    var results: Self.Results { get }

    associatedtype Results : Sendable, AsyncSequence where Self.Results.Failure == any Error

    associatedtype Result : SpeechModuleResult, Sendable where Self.Result == Self.Results.Element

    /**
         The audio formats that this module is able to analyze, given its configuration.
         
         If the audio format doesn't matter, then there will be one format listed with a sample rate of `kAudioStreamAnyRate` and other values 0.
         
         If assets are necessary yet not installed on device, then the list will be empty.
    
         This property may be accessed before the module is added to the analyzer.
         */
    var availableCompatibleAudioFormats: [AVAudioFormat] { get async }
}

/**
 Protocol that all module results conform to.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public protocol SpeechModuleResult {

    /**
     The audio input range that this result applies to.
     */
    var range: CMTimeRange { get }

    /**
     The audio input time up to which results from this module have been finalized (after this result). The module's results are final up to but not including this time.
     
     This value is mostly equivalent to the start of ``SpeechAnalyzer/volatileRange`` after the time at which this result was published. The module publishing this result will publish no futher results with a ``range`` that encompasses a time predating this time. The module may publish results for a range that includes this time.
     
     The client can draw the following conclusions from this value and `range` (or refer to the <doc:/documentation/Speech/SpeechModuleResult/isFinal> property):
     * If `resultsFinalizationTime >= range.end` then this result is final. Additionally, all previously-provided results with a `range` predating `resultsFinalizationTime` are also final.
     * If `resultsFinalizationTime < range.end` (or `resultsFinalizationTime <= range.start`) then this result is volatile and may or may not be replaced by a result provided later.
     
     A module is not required to provide new, final results for audio ranges that it finalizes through if the previously-volatile result was unchanged by finalization. If needed, however, a client can create two modules—one that provides both volatile and final results, and a second that only provides final results—and process results from the latter differently.
     
     This value is not _exactly_ equivalent to the start of the volatile range. The ``SpeechAnalyzer/volatileRange`` property combines all modules' volatile ranges together; this property only refers to the finalization status of results from the module delivering this result.
     */
    var resultsFinalizationTime: CMTime { get }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SpeechModuleResult {

    /**
     Whether this result is final at the time it is produced.
     
     * If `true`, then this result is final. There will be no later result over its range.
     * If `false`, then this result is volatile. There may or may not be a later result over this result's range. In particular, there is no guarantee that this result will be reissued with this property set to `true`.
     
     Equivalent to `resultsFinalizationTime >= range.end`.
     */
    public var isFinal: Bool { get }
}

/**
 A speech-to-text transcription module that's appropriate for normal conversation and general purposes.
 
 Several transcriber instances can share the same backing engine instances and models, so long as the transcribers are configured similarly in certain respects.
 
 ### Check device support
 
 Use the ``isAvailable`` or ``supportedLocales`` properties to see if the current device supports the speech-to-text models used by `SpeechTranscriber`. If it does not, consider disabling the feature or using ``DictationTranscriber`` instead.
 */
@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final public class SpeechTranscriber : LocaleDependentSpeechModule {

    /**
     Creates a general-purpose transcriber according to a preset.
     
     - Parameters:
        - locale: A locale indicating a spoken and written language or script.
        - preset: A structure that contains some transcriber options.
     */
    public convenience init(locale: Locale, preset: SpeechTranscriber.Preset)

    /**
         Creates a general-purpose transcriber.
    
         - Parameters:
            - locale: A locale indicating a spoken and written language or script.
            - transcriptionOptions: A selection of options relating to the text of the transcription.
            - reportingOptions: A selection of options relating to the transcriber's result delivery.
            - attributeOptions: A selection of options relating to the attributes of the transcription.
         */
    public convenience init(locale: Locale, transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>, reportingOptions: Set<SpeechTranscriber.ReportingOption>, attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>)

    /**
         Predefined transcriber configurations.
         
         You can configure a transcriber with a preset, or modify the values of a preset's properties and configure a transcriber with the modified values. You can also create your own presets by extending this type.
         
         It is not necessary to use a preset at all; you can also use the transcriber's designated initializer to completely customize its configuration.
    
         This example configures a transcriber according to the `timeIndexedTranscriptionWithAlternatives` preset, but adds etiquette filtering and removes alternative transcriptions:
         
         ```swift
         let preset = SpeechTranscriber.Preset.timeIndexedTranscriptionWithAlternatives
         let transcriber = SpeechTranscriber(
             locale: Locale.current,
             transcriptionOptions: preset.transcriptionOptions.union([.etiquetteReplacements])
             reportingOptions: preset.reportingOptions.subtracting([.alternativeTranscriptions])
             attributeOptions: preset.attributeOptions
         )
         ```
         
         This table lists the presets and their configurations:
         
         Preset | [volatileResults](doc:ReportingOption/volatileResults) | [fastResults](doc:ReportingOption/fastResults) | [alternativeTranscriptions](doc:ReportingOption/alternativeTranscriptions) | [audioTimeRange](doc:ResultAttributeOption/audioTimeRange)
         --- | --- | --- | --- | ---
         `transcription` | No | No | No | No
         `transcriptionWithAlternatives` | No | No | **Yes** | No
         `timeIndexedTranscriptionWithAlternatives` | No | No | **Yes** | **Yes**
         `progressiveTranscription` | **Yes** | **Yes** | No | No
         `timeIndexedProgressiveTranscription` | **Yes** | **Yes** | No | **Yes**
         */
    public struct Preset : Sendable, Equatable, Hashable {

        /// Configuration for basic, accurate transcription.
        public static let transcription: SpeechTranscriber.Preset

        /// Configuration for transcription with editing suggestions.
        public static let transcriptionWithAlternatives: SpeechTranscriber.Preset

        /// Configuration for transcription with editing suggestions, cross-referenced to source audio.
        public static let timeIndexedTranscriptionWithAlternatives: SpeechTranscriber.Preset

        /// Configuration for immediate transcription of live audio.
        public static let progressiveTranscription: SpeechTranscriber.Preset

        /// Configuration for immediate transcription of live audio, cross-referenced to stream time-codes.
        public static let timeIndexedProgressiveTranscription: SpeechTranscriber.Preset

        /**
         Creates a preset.
         
         - Parameters:
            - transcriptionOptions: A selection of options relating to the text of the transcription.
            - reportingOptions: A selection of options relating to the transcriber's result delivery.
            - attributeOptions: A selection of options relating to the attributes of the transcription.
         */
        public init(transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>, reportingOptions: Set<SpeechTranscriber.ReportingOption>, attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>)

        /// Options relating to the text of the transcription appropriate for this preset.
        public var transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>

        /// Options relating to the transcriber's result delivery appropriate for this preset.
        public var reportingOptions: Set<SpeechTranscriber.ReportingOption>

        /// Options relating to the attributes of the transcription appropriate for this preset.
        public var attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechTranscriber.Preset, b: SpeechTranscriber.Preset) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Options relating to the text of the transcription.
     */
    public enum TranscriptionOption : CaseIterable, Sendable, Equatable, Hashable {

        /**
         Replaces certain words and phrases with a redacted form.
         
         If included, a phrase recognized as an expletive would be transcribed with asterisks.
         */
        case etiquetteReplacements

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechTranscriber.TranscriptionOption, b: SpeechTranscriber.TranscriptionOption) -> Bool

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [SpeechTranscriber.TranscriptionOption]

        /// A collection of all values of this type.
        nonisolated public static var allCases: [SpeechTranscriber.TranscriptionOption] { get }

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Options relating to the transcriber's result delivery.
     */
    public enum ReportingOption : CaseIterable, Sendable, Equatable, Hashable {

        /**
         Provides tentative results for an audio range in addition to the finalized result.
         
         The transcriber will deliver several results for an audio range as it refines the transcription.
         */
        case volatileResults

        /**
         Includes alternative transcriptions in addition to the most likely transcription.
         */
        case alternativeTranscriptions

        /**
         Biases the transcriber towards responsiveness, yielding faster but also less accurate results.
         
         If included, the transcriber reduces per-result latency by examining less previous context, using a smaller "window" or "chunk size" than its default.
         */
        case fastResults

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechTranscriber.ReportingOption, b: SpeechTranscriber.ReportingOption) -> Bool

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [SpeechTranscriber.ReportingOption]

        /// A collection of all values of this type.
        nonisolated public static var allCases: [SpeechTranscriber.ReportingOption] { get }

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     Options relating to the attributes of the transcription.
     */
    public enum ResultAttributeOption : CaseIterable, Sendable, Equatable, Hashable {

        /**
         Includes time-code attributes in a transcription's attributed string.
         
         These are ``Foundation/AttributeScopes/SpeechAttributes/TimeRangeAttribute`` attributes.
         */
        case audioTimeRange

        /**
         Includes confidence attributes in a transcription's attributed string.
         
         These are ``Foundation/AttributeScopes/SpeechAttributes/ConfidenceAttribute`` attributes.
         */
        case transcriptionConfidence

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechTranscriber.ResultAttributeOption, b: SpeechTranscriber.ResultAttributeOption) -> Bool

        /// A type that can represent a collection of all values of this type.
        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias AllCases = [SpeechTranscriber.ResultAttributeOption]

        /// A collection of all values of this type.
        nonisolated public static var allCases: [SpeechTranscriber.ResultAttributeOption] { get }

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    /**
     A Boolean value that indicates whether this module is available given the device's hardware and capabilities.
     */
    public static var isAvailable: Bool { get }

    /**
     The locales that the transcriber can transcribe into, including locales that may not be installed but are downloadable.
     
     This array is empty if the device does not support the transcriber.
     */
    public static var supportedLocales: [Locale] { get async }

    /**
     A locale from the module's supported locales equivalent to the given locale.
     
     Use this method to determine which of this module's supported locales is equivalent to an arbitrary locale such as `Locale.current`.
     
     If there is no exact equivalent, this method will return a near-equivalent: a supported (and by preference already-installed) locale that shares the same `Locale.LanguageCode` value but has a different `Locale.Region` value. This may result in an unexpected transcription, such as between "color" and "colour".
     
     - Tip: If you use this method, your application should ideally still provide a way for the user to correct the locale by selecting from the supported locales list.
     
     - Parameter locale: An arbitrary locale.
     - Returns: A locale in the supported locales list, or `nil` if there is no equivalent locale in that list.
     */
    public static func supportedLocale(equivalentTo locale: Locale) async -> Locale?

    /**
     The locales that the transcriber can transcribe into, considering only locales that are installed on the device.
     */
    public static var installedLocales: [Locale] { get async }

    /**
     The set of asset locales specified by the module's configuration.
     */
    final public var selectedLocales: [Locale] { get }

    /**
         The audio formats that this module is able to analyze, given its configuration.
         
         If the audio format doesn't matter, then there will be one format listed with a sample rate of `kAudioStreamAnyRate` and other values 0.
         
         If assets are necessary yet not installed on device, then the list will be empty.
    
         This property may be accessed before the module is added to the analyzer.
         */
    final public var availableCompatibleAudioFormats: [AVAudioFormat] { get async }

    /**
     An asynchronous sequence containing this module's analysis results. Results are added to the sequence as they are created.
     
     Each module has its own result sequence and data structure.
     
     If there is an error in the overall analysis, all modules will throw the error from their individual result sequence.
     */
    final public var results: some Sendable & AsyncSequence<SpeechTranscriber.Result, any Error> { get }

    /**
     A phrase or passage of transcribed speech. The phrases are sent in order.
     
     If the transcriber is configured to send volatile results, each phrase is sent one or more times as the interpretation gets better and better until it is finalized.
     */
    public struct Result : SpeechModuleResult, Sendable, CustomStringConvertible, Equatable, Hashable {

        /**
         The audio input range that this result applies to.
         */
        public let range: CMTimeRange

        /**
         The audio input time up to which results from this module have been finalized (after this result). The module's results are final up to but not including this time.
         
         This value is mostly equivalent to the start of ``SpeechAnalyzer/volatileRange`` after the time at which this result was published. The module publishing this result will publish no futher results with a ``range`` that encompasses a time predating this time. The module may publish results for a range that includes this time.
         
         The client can draw the following conclusions from this value and `range` (or refer to the <doc:/documentation/Speech/SpeechModuleResult/isFinal> property):
         * If `resultsFinalizationTime >= range.end` then this result is final. Additionally, all previously-provided results with a `range` predating `resultsFinalizationTime` are also final.
         * If `resultsFinalizationTime < range.end` (or `resultsFinalizationTime <= range.start`) then this result is volatile and may or may not be replaced by a result provided later.
         
         A module is not required to provide new, final results for audio ranges that it finalizes through if the previously-volatile result was unchanged by finalization. If needed, however, a client can create two modules—one that provides both volatile and final results, and a second that only provides final results—and process results from the latter differently.
         
         This value is not _exactly_ equivalent to the start of the volatile range. The ``SpeechAnalyzer/volatileRange`` property combines all modules' volatile ranges together; this property only refers to the finalization status of results from the module delivering this result.
         */
        public let resultsFinalizationTime: CMTime

        /**
                 The most likely interpretation of the audio in this range.
        
                 An empty string indicates that the audio contains no recognizable speech and, for results in the volatile range, that previous results for this range are revoked.
                 
                 This value is the first (most likely) element of ``alternatives``.
                 */
        public var text: AttributedString { get }

        /**
         All the alternative interpretations of the audio in this range. The interpretations are in descending order of likelihood.
         
         The array will not be empty, but may contain an empty string, indicating an alternative where the audio has no transcription.
         
         To receive alternatives, set the ``SpeechTranscriber/ReportingOption/alternativeTranscriptions`` option.
         */
        public let alternatives: [AttributedString]

        /// A textual representation of this instance.
        ///
        /// Calling this property directly is discouraged. Instead, convert an
        /// instance of any type to a string by using the `String(describing:)`
        /// initializer. This initializer works with any type, and uses the custom
        /// `description` property for types that conform to
        /// `CustomStringConvertible`:
        ///
        ///     struct Point: CustomStringConvertible {
        ///         let x: Int, y: Int
        ///
        ///         var description: String {
        ///             return "(\(x), \(y))"
        ///         }
        ///     }
        ///
        ///     let p = Point(x: 21, y: 30)
        ///     let s = String(describing: p)
        ///     print(s)
        ///     // Prints "(21, 30)"
        ///
        /// The conversion of `p` to a string in the assignment to `s` uses the
        /// `Point` type's `description` property.
        public var description: String { get }

        /// Returns a Boolean value indicating whether two values are equal.
        ///
        /// Equality is the inverse of inequality. For any values `a` and `b`,
        /// `a == b` implies that `a != b` is `false`.
        ///
        /// - Parameters:
        ///   - lhs: A value to compare.
        ///   - rhs: Another value to compare.
        public static func == (a: SpeechTranscriber.Result, b: SpeechTranscriber.Result) -> Bool

        /// Hashes the essential components of this value by feeding them into the
        /// given hasher.
        ///
        /// Implement this method to conform to the `Hashable` protocol. The
        /// components used for hashing must be the same as the components compared
        /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
        /// with each of these components.
        ///
        /// - Important: In your implementation of `hash(into:)`,
        ///   don't call `finalize()` on the `hasher` instance provided,
        ///   or replace it with a different instance.
        ///   Doing so may become a compile-time error in the future.
        ///
        /// - Parameter hasher: The hasher to use when combining the components
        ///   of this instance.
        public func hash(into hasher: inout Hasher)

        /// The hash value.
        ///
        /// Hash values are not guaranteed to be equal across different executions of
        /// your program. Do not save hash values to use during a future execution.
        ///
        /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
        ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
        ///   The compiler provides an implementation for `hashValue` for you.
        public var hashValue: Int { get }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public typealias Results = some Sendable & AsyncSequence<SpeechTranscriber.Result, any Error>

    @objc deinit
}

/** A protocol supporting the custom language model training data result builder. */
@available(macOS 14, iOS 17, visionOS 1.1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public protocol TemplateInsertable {

    func insert(generator: SFCustomLanguageModelData.TemplatePhraseCountGenerator)
}

extension AttributeScopes {

    @available(macOS 26.0, iOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public struct SpeechAttributes : AttributeScope {

        public let transcriptionConfidence: AttributeScopes.SpeechAttributes.ConfidenceAttribute

        public let audioTimeRange: AttributeScopes.SpeechAttributes.TimeRangeAttribute

        /// A confidence level (0–1) of the associated transcription text.
        public struct ConfidenceAttribute : CodableAttributedStringKey {

            public static let name: String

            public typealias Value = Double
        }

        /**
         The time range in the source audio corresponding to the associated transcription text.
         
         > Tip: Use ``Foundation/AttributedString/rangeOfAudioTimeRangeAttributes(intersecting:)`` to locate text corresponding to a source audio time range.
         */
        public struct TimeRangeAttribute : CodableAttributedStringKey {

            public static let name: String

            public typealias Value = CMTimeRange

            public static func encode(_ value: AttributeScopes.SpeechAttributes.TimeRangeAttribute.Value, to encoder: any Encoder) throws

            public static func decode(from decoder: any Decoder) throws -> AttributeScopes.SpeechAttributes.TimeRangeAttribute.Value
        }

        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias DecodingConfiguration = AttributeScopeCodableConfiguration

        @available(iOS 26.0, macOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public typealias EncodingConfiguration = AttributeScopeCodableConfiguration
    }
}

extension AttributeDynamicLookup {

    @available(macOS 26.0, iOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public subscript<T>(dynamicMember keyPath: KeyPath<AttributeScopes.SpeechAttributes, T>) -> T where T : AttributedStringKey { get }
}

extension AttributedString {

    /**
     Returns the range of indices of the receiver that are part of given time range.
     
     The method compares the given time range against the ``AttributeScopes/SpeechAttributes/TimeRangeAttribute`` attributes of the receiver.
     
     You can use this method to help update an attributed string that tracks the volatile or finalized results of a ``SpeechTranscriber`` or ``DictationTranscriber`` module.
     */
    @available(macOS 26.0, iOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public func rangeOfAudioTimeRangeAttributes(intersecting timeRange: CMTimeRange) -> Range<AttributedString.Index>?
}

@available(macOS 14.0, iOS 17.0, *)
extension SFAcousticFeature {

    /**
     An array of feature values, one value per audio frame, corresponding to a transcript segment of recorded audio.
     */
    public var acousticFeatureValuePerFrame: [Double] { get }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SFSpeechError.Code {

    /// The audio input time-code overlaps or precedes prior audio input.
    public static var audioDisordered: SFSpeechError.Code { get }

    /// The audio input is in unexpected format.
    public static var unexpectedAudioFormat: SFSpeechError.Code { get }

    /// The selected locale/options does not have an appropriate model available or downloadable.
    public static var noModel: SFSpeechError.Code { get }

    /// The asset locale has not been allocated, but module requires it.
    public static var assetLocaleNotAllocated: SFSpeechError.Code { get }

    /// The application has allocated too many locales.
    public static var tooManyAssetLocalesAllocated: SFSpeechError.Code { get }

    /// The selected modules do not have an audio format in common.
    public static var incompatibleAudioFormats: SFSpeechError.Code { get }

    /// The module's result task failed.
    public static var moduleOutputFailed: SFSpeechError.Code { get }

    /// The asset locale being requested is not supported by SpeechFramework.
    public static var cannotAllocateUnsupportedLocale: SFSpeechError.Code { get }

    /// There are not sufficient resources available on-device to process the incoming transcription request.
    public static var insufficientResources: SFSpeechError.Code { get }
}
