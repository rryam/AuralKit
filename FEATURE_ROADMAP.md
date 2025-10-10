# AuralKit Feature Roadmap

A comprehensive analysis of potential features and enhancements based on iOS 26+ Speech Framework capabilities.

---

## Table of Contents

1. [Core Transcription Features](#1-core-transcription-features)
2. [Custom Language Models](#2-custom-language-models)
3. [Advanced Context Management](#3-advanced-context-management)
4. [Audio File Transcription](#4-audio-file-transcription)
5. [DictationTranscriber Support](#5-dictationtranscriber-support)
6. [Advanced SpeechAnalyzer Features](#6-advanced-speechanalyzer-features)
7. [Multi-Module Analysis](#7-multi-module-analysis)
8. [Session Control & Lifecycle](#8-session-control--lifecycle)
9. [Result Enhancements](#9-result-enhancements)
10. [UI & Developer Experience](#10-ui--developer-experience)
11. [Performance & Optimization](#11-performance--optimization)
12. [Audio Pipeline Features](#12-audio-pipeline-features)
13. [Error Handling & Diagnostics](#13-error-handling--diagnostics)
14. [Testing & Quality](#14-testing--quality)

---

## Completed Features

- ~~Integrated voice activity detection with optional result streaming~~
- ~~Device capability helper exposing available transcribers and locales~~

---

## Audio File Transcription – Implementation Plan

- [x] Audit existing live transcription pipeline to identify reusable components for offline processing
  - Live path responsibilities reused: `setUpTranscriber`, `finishStream`, cleanup routines, and model management. Only `startAudioStreaming`/tap setup is microphone-specific and will be bypassed for file reads.
- [x] Design public API surface for file-based transcription (streaming and one-shot variants, progress callbacks, error cases)
  - Proposed additions: `transcribe(audioFile:progress:) async throws -> TranscriptionResult` and `streamTranscription(from:progress:) -> AsyncThrowingStream<SpeechTranscriber.Result, Error>` with optional `progress` closure.
  - Extend `SpeechSessionError` with cases for unsupported format, file access, and duration limit.
  - Consider optional `FileTranscriptionOptions` struct for locale/preset overrides and maxDuration.
- [x] Define audio file validation rules and conversion strategy via `BufferConverter`
  - Validation: existence/readability, `AVAudioFile` open succeeds, format convertible to analyzer format (PCM float 32), optional duration cap (e.g. 2 hours) to guard resources.
  - Conversion flow: reuse `BufferConverter.convertBuffer(_:to:)` after reading blocks from the source file; normalize channel count via mixer when needed.
- [x] Implement offline transcription pipeline (file reader, analyzer integration, progress, cancellation)
  - Added `streamTranscription(from:options:progressHandler:)` and `transcribe(audioFile:options:progressHandler:)` APIs with shared analyzer setup and progress reporting.
  - Introduced file feed loop that converts buffers through `BufferConverter`, reuses cleanup flows, and respects cancellation.
- [x] Add unit/integration tests with fixture audio and ensure tooling/CI updates
  - Created silence CAF fixture generator in tests and validated missing file, duration limit, and new error surfaces via `FileTranscriptionTests`.

---

## 1. Core Transcription Features

### 1.1 Fine-Grained Transcription Options

**Current State:** Default options are used.

**Opportunity:** Allow users to customize individual transcription, reporting, and attribute options:

```swift
public struct TranscriptionConfiguration {
    // Text options
    public var etiquetteReplacements: Bool = false  // Redact profanity
    public var emoji: Bool = false                  // "smiling emoji" → 🙂
    public var punctuation: Bool = true             // Auto-punctuation
    
    // Reporting options
    public var volatileResults: Bool = true         // Partial results
    public var alternatives: Bool = true            // Alternative transcriptions
    public var fastResults: Bool = false            // Lower latency, less context
    public var frequentFinalization: Bool = false   // More responsive finalization
    
    // Attribute options
    public var includeAudioTimeRange: Bool = true
    public var includeConfidenceScores: Bool = true
    
    // Content hints (DictationTranscriber)
    public var shortForm: Bool = false              // ~1 minute audio
    public var farField: Bool = false               // Distant speaker
    public var atypicalSpeech: Bool = false         // Heavy accent, lisp, etc.
}
```

## 2. Custom Language Models

### 2.1 Custom Vocabulary Training

**Current State:** Only basic contextual strings are supported.

**Opportunity:** Full custom language model support using `SFCustomLanguageModelData`:

```swift
public struct CustomLanguageModel {
    public let locale: Locale
    public let identifier: String
    public let version: String
    public let trainingData: URL  // Exported model data
}

extension SpeechSession {
    public func setCustomLanguageModel(
        _ model: CustomLanguageModel
    ) async throws
}
```

### 2.2 Language Model Training API

**Opportunity:** Provide high-level API for creating custom models:

```swift
public final class LanguageModelTrainer {
    public init(locale: Locale, identifier: String, version: String)
    
    // Add phrase counts for training
    public func addPhraseCount(_ phrase: String, count: Int)
    public func addPhraseCounts(_ phrases: [String: Int])
    
    // Add custom pronunciations (X-SAMPA phonetics)
    public struct CustomPronunciation {
        public let grapheme: String  // Written form
        public let phonemes: [String] // X-SAMPA pronunciations
    }
    
    public func addCustomPronunciation(_ pronunciation: CustomPronunciation)
    
    // Template-based generation
    public func addTemplate(
        _ template: String,  // e.g., "Move <piece> to <square>"
        count: Int,
        classes: [String: [String]]  // e.g., ["piece": ["knight", "bishop"], ...]
    )
    
    // Export for use with SpeechSession
    public func export(to url: URL) async throws
    
    // Prepare model for recognition
    public static func prepare(from url: URL) async throws -> CustomLanguageModel
}
```

**Use Cases:**
- Medical dictation apps (medical terminology)
- Legal transcription (legal jargon)
- Technical documentation (API names, frameworks)
- Gaming voice commands (game-specific vocabulary)
- Name-heavy apps (contact names, place names)

### 2.3 Domain-Specific Presets

**Opportunity:** Provide pre-built language models for common domains:

```swift
public enum LanguageModelDomain {
    case medical
    case legal
    case technical
    case gaming
    case custom(CustomLanguageModel)
}

extension SpeechSession {
    public convenience init(
        locale: Locale,
        domain: LanguageModelDomain
    )
}
```

---

## 3. Advanced Context Management

### 3.1 Structured Context API

**Current State:** Basic contextual strings dictionary.

**Opportunity:** Full `AnalysisContext` support with user data:

```swift
public struct TranscriptionContext {
    // Contextual strings by tag
    public var contextualStrings: [ContextTag: [String]] = [:]
    
    // Application-specific context
    public var userData: [UserDataTag: any Sendable] = [:]
    
    public struct ContextTag: RawRepresentable, Hashable {
        public static let general: ContextTag
        public static let personal: ContextTag
        public static let technical: ContextTag
        // Custom tags
        public init(_ rawValue: String)
    }
    
    public struct UserDataTag: RawRepresentable, Hashable {
        public init(_ rawValue: String)
    }
}

extension SpeechSession {
    public func updateContext(_ context: TranscriptionContext) async throws
}
```

### 3.2 Dynamic Context Updates

**Opportunity:** Update context mid-transcription:

```swift
extension SpeechSession {
    // Add/remove contextual strings on the fly
    public func addContextualStrings(
        _ strings: [String],
        forTag tag: TranscriptionContext.ContextTag
    ) async
    
    public func removeContextualStrings(
        forTag tag: TranscriptionContext.ContextTag
    ) async
    
    // Update user data
    public func setUserData(
        _ data: any Sendable,
        forKey key: TranscriptionContext.UserDataTag
    ) async
}
```

**Use Cases:**
- Chat app: add participant names as they join
- Navigation app: add nearby place names
- Calendar app: add upcoming event titles
- Contact app: add contact names as they're accessed

---

## 4. Audio File Transcription

### 4.1 File-Based Transcription

**Current State:** Only live microphone capture is supported.

**Opportunity:** Add audio file transcription support:

```swift
extension SpeechSession {
    // Transcribe from audio file
    public func transcribe(
        audioFile: URL,
        progressHandler: ((Progress) -> Void)? = nil
    ) async throws -> TranscriptionResult
    
    // Stream results from audio file
    public func transcribeStream(
        audioFile: URL
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error>
}

public struct TranscriptionResult {
    public let text: AttributedString
    public let alternatives: [AttributedString]
    public let duration: CMTime
    public let segments: [TimedSegment]
}

public struct TimedSegment {
    public let text: AttributedString
    public let timeRange: CMTimeRange
    public let confidence: Double
}
```

### 4.2 Batch File Processing

**Opportunity:** Process multiple audio files efficiently:

```swift
public struct FileTranscriptionRequest {
    public let fileURL: URL
    public let locale: Locale
    public let configuration: TranscriptionConfiguration
}

public struct FileTranscriptionResult {
    public let request: FileTranscriptionRequest
    public let result: Result<TranscriptionResult, Error>
}

extension SpeechSession {
    public func transcribeBatch(
        _ requests: [FileTranscriptionRequest],
        concurrency: Int = 4
    ) -> AsyncStream<FileTranscriptionResult>
}
```

### 4.3 Audio Format Support

**Opportunity:** Document and handle various audio formats:

```swift
public enum AudioFormat {
    case wav
    case mp3
    case m4a
    case caf
    case aiff
    case flac
    
    public static var supported: [AudioFormat] { get }
}

extension SpeechSession {
    public static func isSupported(audioFormat: AudioFormat) -> Bool
    public static func isSupported(audioFile: URL) async throws -> Bool
}
```

---

## 5. DictationTranscriber Support

### 5.1 Automatic Transcriber Selection

**Current State:** Only `SpeechTranscriber` is used.

**Opportunity:** Allow choosing `DictationTranscriber` for short-form dictation experiences:

```swift
public enum TranscriberType {
    case speechTranscriber    // Full contextual transcription
    case dictationTranscriber // Optimized for short-form dictation
    case automatic            // Auto-select transcriber for session goals
}

extension SpeechSession {
    public convenience init(
        locale: Locale,
        transcriberType: TranscriberType = .automatic
    )
    
    public var activeTranscriberType: TranscriberType { get }
}
```

---

## 6. Advanced SpeechAnalyzer Features

### 6.1 Analyzer Preheating

**Current State:** Lazy initialization on first use.

**Opportunity:** Preheat analyzer for minimal startup delay:

```swift
extension SpeechSession {
    public func preheat() async throws
    
    public func preheat(
        progressHandler: @escaping (Progress) -> Void
    ) async throws
}
```

**Benefits:**
- Instant transcription start
- Better user experience in time-sensitive apps
- Predictable performance

### 6.2 Volatile Range Monitoring

**Opportunity:** Expose analyzer volatile range:

```swift
public struct VolatileRange {
    public let range: CMTimeRange?
    public let startChanged: Bool
    public let endChanged: Bool
}

extension SpeechSession {
    public var volatileRangeStream: AsyncStream<VolatileRange> { get }
}
```

**Use Cases:**
- Show "processing" indicator in UI
- Track transcription progress
- Synchronize with audio playback

### 6.3 Manual Finalization Control

**Opportunity:** Allow manual control over result finalization:

```swift
extension SpeechSession {
    // Finalize results up to a specific time
    public func finalize(through time: CMTime) async throws
    
    // Cancel analysis before a specific time
    public func cancelAnalysis(before time: CMTime) async
}
```

**Use Cases:**
- Scene changes in video transcription
- Chapter markers in long-form audio
- Forced "catch-up" if analyzer lags

### 6.4 Model Retention Options

**Opportunity:** Control model caching behavior:

```swift
public enum ModelRetentionPolicy {
    case whileInUse        // Release when session ends
    case lingering         // Cache briefly for reuse
    case processLifetime   // Keep until app exits
}

extension SpeechSession {
    public convenience init(
        locale: Locale,
        modelRetention: ModelRetentionPolicy = .lingering
    )
}
```

### 6.5 Priority Control

**Opportunity:** Set processing priority:

```swift
extension SpeechSession {
    public convenience init(
        locale: Locale,
        priority: TaskPriority = .userInitiated
    )
    
    public func setPriority(_ priority: TaskPriority) async
}
```

---

## 7. Multi-Module Analysis

### 7.1 Parallel Module Support

**Current State:** Single transcriber module.

**Opportunity:** Support multiple analysis modules simultaneously:

```swift
public protocol AnalysisModule {
    associatedtype Result: SpeechModuleResult
    var results: AsyncThrowingStream<Result, Error> { get }
}

extension SpeechSession {
    public func addModule<M: AnalysisModule>(_ module: M) async throws
    public func removeModule<M: AnalysisModule>(_ module: M) async
    
    public var activeModules: [any AnalysisModule] { get }
}
```

**Use Cases:**
- Transcription + VAD simultaneously
- Multiple locales at once
- Transcription + custom analysis

### 7.2 Module Result Coordination

**Opportunity:** Coordinate results from multiple modules:

```swift
public struct MultiModuleResult {
    public let transcription: SpeechTranscriber.Result?
    public let voiceActivity: SpeechDetector.Result?
    public let customResults: [String: any SpeechModuleResult]
    public let timeRange: CMTimeRange
}

extension SpeechSession {
    public func startMultiModuleAnalysis() 
        -> AsyncThrowingStream<MultiModuleResult, Error>
}
```

---

## 8. Session Control & Lifecycle

### 8.1 Session State Management

**Current State:** Boolean `isTranscribing` flag.

**Opportunity:** Rich state machine:

```swift
public enum SessionState {
    case idle
    case preparing
    case active
    case paused
    case finishing
    case error(Error)
}

extension SpeechSession {
    public var state: SessionState { get }
    public var stateStream: AsyncStream<SessionState> { get }
}
```

### 8.2 Graceful Shutdown

**Opportunity:** Control finalization on stop:

```swift
extension SpeechSession {
    public enum StopBehavior {
        case immediate                    // Cancel pending work
        case finalizePending              // Process remaining audio
        case finalizePending(timeout: TimeInterval)
    }
    
    public func stopTranscribing(
        behavior: StopBehavior = .finalizePending
    ) async
}
```

### 8.3 Session Reuse & Reset

**Opportunity:** Efficiently reuse sessions:

```swift
extension SpeechSession {
    public func reset() async
    
    public func switchLocale(_ newLocale: Locale) async throws
    
    public func reconfigure(
        _ configuration: TranscriptionConfiguration
    ) async throws
}
```

---

## 9. Result Enhancements

### 9.1 Result Alternatives UI

**Current State:** Alternatives are available but not exposed in UI.

**Opportunity:** SwiftUI components for showing alternatives:

```swift
public struct AlternativesPickerView: View {
    @Binding public var selectedText: AttributedString
    public let alternatives: [AttributedString]
}

public struct TranscriptionEditorView: View {
    @Binding public var transcription: AttributedString
    public let result: SpeechTranscriber.Result
}
```

### 9.2 Confidence-Based Styling

**Opportunity:** Automatically style text based on confidence:

```swift
public struct ConfidenceStyler {
    public static func apply(
        to text: AttributedString,
        lowConfidenceColor: Color = .red,
        mediumConfidenceColor: Color = .orange,
        highConfidenceColor: Color = .green
    ) -> AttributedString
}
```

### 9.3 Time-Synced Playback

**Current State:** Demo app has basic playback highlighting.

**Opportunity:** Reusable component for audio-synced transcription:

```swift
public struct TimeSyncedTranscriptionView: View {
    public let transcription: AttributedString
    public let audioPlayer: AVAudioPlayer
    @State public var currentTime: CMTime
}
```

### 9.4 Result Export Formats

**Opportunity:** Export transcriptions in various formats:

```swift
public enum ExportFormat {
    case plainText
    case markdown
    case html
    case srt         // Subtitle format
    case vtt         // WebVTT
    case json        // Structured JSON
}

extension TranscriptionResult {
    public func export(as format: ExportFormat) -> Data
}
```

---

## 10. UI & Developer Experience

### 10.1 SwiftUI Components Library

**Opportunity:** Pre-built UI components:

```swift
// Microphone button with state
public struct TranscriptionButton: View {
    @Binding public var isTranscribing: Bool
    public let action: () -> Void
}

// Live transcription view
public struct LiveTranscriptionView: View {
    public let finalizedText: AttributedString
    public let volatileText: AttributedString
}

// Locale picker
public struct LocalePickerView: View {
    @Binding public var selectedLocale: Locale
    public let supportedLocales: [Locale]
}

// Model download progress
public struct ModelDownloadView: View {
    public let progress: Progress?
}

// Audio input monitor
public struct AudioInputMonitorView: View {
    public let inputInfo: AudioInputInfo?
}

// Waveform visualization
public struct AudioWaveformView: View {
    public let audioLevel: Float
}
```

### 10.2 Accessibility Features

**Opportunity:** Built-in accessibility:

```swift
extension SpeechSession {
    public struct AccessibilityOptions {
        public var announceTranscriptionStart: Bool = true
        public var announceTranscriptionEnd: Bool = true
        public var provideLiveUpdates: Bool = true
    }
    
    public var accessibilityOptions: AccessibilityOptions
}
```

### 10.3 Developer Debugging

**Opportunity:** Debugging and diagnostics tools:

```swift
public struct SessionDiagnostics {
    public let audioFormat: AVAudioFormat
    public let bufferCount: Int
    public let droppedBuffers: Int
    public let averageLatency: TimeInterval
    public let modelLoadTime: TimeInterval
    public let memoryUsage: Int
}

extension SpeechSession {
    public var diagnostics: SessionDiagnostics { get }
    
    public func enableDebugLogging(_ enabled: Bool)
}
```

---

## 11. Performance & Optimization

### 11.1 Buffer Management

**Opportunity:** Configurable buffer sizes and strategies:

```swift
public struct BufferConfiguration {
    public var bufferSize: AVAudioFrameCount = 4096
    public var bufferCount: Int = 3
    public var droppedBufferStrategy: DroppedBufferStrategy = .dropOldest
    
    public enum DroppedBufferStrategy {
        case dropOldest
        case dropNewest
        case pause
        case error
    }
}

extension SpeechSession {
    public var bufferConfiguration: BufferConfiguration
}
```

### 11.2 Memory Management

**Opportunity:** Memory usage controls:

```swift
extension SpeechSession {
    public struct MemoryOptions {
        public var maxBufferMemory: Int = 10_000_000 // 10MB
        public var releaseBuffersWhenPaused: Bool = true
        public var compactOnLowMemory: Bool = true
    }
    
    public var memoryOptions: MemoryOptions
}
```

### 11.3 Network Usage Control

**Opportunity:** Control model downloads:

```swift
public struct NetworkOptions {
    public var allowCellularDownloads: Bool = false
    public var maxDownloadSize: Int = 500_000_000 // 500MB
    public var downloadTimeout: TimeInterval = 300
}

extension SpeechSession {
    public static var networkOptions: NetworkOptions
}
```

---

## 12. Audio Pipeline Features

### 12.1 Audio Preprocessing

**Opportunity:** Optional audio enhancement:

```swift
public struct AudioPreprocessing {
    public var noiseReduction: Bool = false
    public var echoCancellation: Bool = false
    public var automaticGainControl: Bool = false
    public var voiceEnhancement: Bool = false
}

extension SpeechSession {
    public var audioPreprocessing: AudioPreprocessing
}
```

### 12.2 Multi-Channel Support

**Opportunity:** Handle stereo and multi-channel audio:

```swift
public enum ChannelConfiguration {
    case mono                    // Mix all channels
    case stereo                  // Keep stereo
    case specific([Int])         // Select specific channels
}

extension SpeechSession {
    public var channelConfiguration: ChannelConfiguration
}
```

### 12.3 Audio Routing

**Current State:** Basic audio input monitoring.

**Opportunity:** Enhanced audio routing control:

```swift
extension SpeechSession {
    public func selectAudioInput(_ input: AudioInputInfo) async throws
    
    public func availableAudioInputs() async -> [AudioInputInfo]
    
    public var preferredAudioInput: AudioInputInfo? { get async }
}
```

---

## 13. Error Handling & Diagnostics

### 13.1 Rich Error Information

**Opportunity:** More detailed error types:

```swift
public enum DetailedSpeechError: Error {
    case permissionDenied(PermissionType)
    case unsupportedLocale(Locale, suggestions: [Locale])
    case modelDownloadFailed(reason: DownloadFailureReason)
    case audioConfigurationFailed(underlying: Error)
    case insufficientResources(required: Int, available: Int)
    case incompatibleAudioFormat(expected: AVAudioFormat, actual: AVAudioFormat)
    case moduleConflict(modules: [String])
    case timeout(operation: String, duration: TimeInterval)
    
    public var recoverysuggestion: String { get }
    public var isRecoverable: Bool { get }
}
```

### 13.2 Error Recovery

**Opportunity:** Automatic error recovery:

```swift
public struct ErrorRecoveryOptions {
    public var autoRetryOnNetworkError: Bool = true
    public var maxRetries: Int = 3
    public var retryDelay: TimeInterval = 1.0
    public var fallbackToOfflineMode: Bool = true
}

extension SpeechSession {
    public var errorRecoveryOptions: ErrorRecoveryOptions
}
```

### 13.3 Health Monitoring

**Opportunity:** Session health checks:

```swift
public struct SessionHealth {
    public let isHealthy: Bool
    public let issues: [HealthIssue]
    public let recommendations: [String]
}

public enum HealthIssue {
    case highLatency(current: TimeInterval, expected: TimeInterval)
    case lowConfidenceScores(average: Double)
    case frequentBufferDrops(rate: Double)
    case memoryPressure
    case thermalState(ProcessInfo.ThermalState)
}

extension SpeechSession {
    public func checkHealth() async -> SessionHealth
}
```

---

## 14. Testing & Quality

### 14.1 Mock Session for Testing

**Opportunity:** Testing utilities:

```swift
public final class MockSpeechSession: SpeechSession {
    public var mockResults: [SpeechTranscriber.Result] = []
    public var mockDelay: TimeInterval = 0.1
    public var mockErrors: [Error] = []
    
    public override func startTranscribing() 
        -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        // Return mock stream
    }
}
```

### 14.2 Transcription Quality Metrics

**Opportunity:** Quality measurement:

```swift
public struct QualityMetrics {
    public let averageConfidence: Double
    public let lowConfidenceRatio: Double
    public let alternativesUtilization: Double
    public let volatileToFinalRatio: Double
    public let averageSegmentLength: TimeInterval
}

extension TranscriptionResult {
    public var qualityMetrics: QualityMetrics { get }
}
```

### 14.3 Performance Benchmarking

**Opportunity:** Built-in benchmarking:

```swift
public struct PerformanceBenchmark {
    public let startLatency: TimeInterval
    public let averageLatency: TimeInterval
    public let maxLatency: TimeInterval
    public let throughput: Double // words per second
    public let cpuUsage: Double
    public let memoryUsage: Int
}

extension SpeechSession {
    public func runBenchmark(duration: TimeInterval) async -> PerformanceBenchmark
}
```

---

## Priority Recommendations

### High Priority (Immediate Value)

1. **Audio File Transcription** - Huge use case expansion
2. **Voice Activity Detection** - Power savings and better UX
3. **SwiftUI Components Library** - Accelerate developer adoption

### Medium Priority (Enhanced Functionality)

6. **Custom Language Models** - Game-changer for specialized apps
7. **Advanced Context Management** - Better accuracy
8. **DictationTranscriber Support** - Dedicated dictation flows
9. **Result Export Formats** - Essential for many use cases
10. **Analyzer Preheating** - Performance enhancement

### Low Priority (Advanced Features)

11. **Multi-Module Analysis** - Niche use case
12. **Manual Finalization Control** - Advanced users only
13. **Audio Preprocessing** - Framework-level concern
14. **Performance Benchmarking** - Development tool

---

## Implementation Phases

### Phase 1: Foundation (v2.0)
- Audio file transcription
- Enhanced error handling
- Basic SwiftUI components

### Phase 2: Intelligence (v2.5)
- Voice Activity Detection
- Custom language models
- Advanced context management
- Result alternatives UI
- Export formats

### Phase 3: Advanced (v3.0)
- Multi-module analysis
- DictationTranscriber enhancements
- Analyzer preheating
- Advanced audio pipeline
- Performance optimization

### Phase 4: Polish (v3.5)
- Complete UI component library
- Comprehensive testing tools
- Developer debugging utilities
- Documentation and examples
- Migration guides

---

## Conclusion

The iOS 26 Speech framework offers a wealth of capabilities beyond basic transcription. AuralKit has an opportunity to become **the** definitive Swift wrapper for speech-to-text by:

1. **Simplifying complexity** - Make advanced features accessible
2. **Providing sensible defaults** - Work great out of the box
3. **Enabling customization** - Expert control when needed
4. **Delivering great DX** - SwiftUI components, testing tools, clear docs
5. **Dictation versatility** - Offer short-form flows alongside deep transcription

The roadmap above provides a clear path from the current v1.0 (excellent foundation) to a comprehensive v3.0+ that covers virtually every speech-to-text use case an iOS/macOS developer might encounter.

---

**Next Steps:**
1. Review and prioritize features based on user feedback
2. Create detailed API designs for Phase 1 features
3. Prototype SwiftUI components
4. Gather community input on API ergonomics
5. Begin implementation with comprehensive tests

This positions AuralKit as not just a simple wrapper, but a thoughtfully designed, production-ready speech framework that makes Apple's powerful capabilities accessible to all developers.
