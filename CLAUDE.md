# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AuralKit** is a Swift package that wraps iOS 26's `SpeechTranscriber` and `SpeechAnalyzer` APIs for speech-to-text transcription. The public API is a single class called `SpeechSession` (not AuralKit - the package name is AuralKit, but the main class is SpeechSession).

### Key Design Principles

1. **Package name vs API name**: The package is called "AuralKit" but the main public interface is `SpeechSession`. Never rename the package or directories to "SpeechSession".

2. **AttributedString everywhere**: The API uses `AttributedString` (not `String`) to preserve `.audioTimeRange` timing metadata from the Speech framework. Only convert to `String` when necessary (e.g., for ShareLink).

3. **Apple's reference implementation**: The core transcription code (buffer conversion, analyzer setup, result handling) follows Apple's SpeechExample exactly. When making changes to transcription logic, verify against Apple's patterns.

4. **Session-based API**: Similar to `URLSession`, users create a `SpeechSession` and call `startTranscribing()` / `stopTranscribing()`.

5. **Simplicity first**: The API is designed to be usable in ~30 lines of SwiftUI code without any manager class. The demo's `TranscriptionManager` is completely optional.

## Build Commands

### Basic commands
```bash
# Build the package
swift build

# Run tests (currently 2 tests)
swift test

# Open in Xcode (no .xcodeproj file - it's a Swift Package)
open Package.swift

# Build the Aural demo app
xcodebuild -scheme Aural -configuration Debug -destination "platform=macOS" build
```

### Running the demo app
After `open Package.swift`:
1. Select "Aural" scheme from Xcode's scheme picker
2. Click Run to build and launch
3. Toggle between "Simple" (MinimalTranscriptionView) and "Advanced" modes

## Architecture

### Public API Layer (Sources/AuralKit/)

**SpeechSession.swift** - The ONLY public API class
- `init(locale: Locale = .current)` - Create a session
- `startTranscribing() -> AsyncThrowingStream<TranscriptionResult, Error>` - Start streaming results
- `stopTranscribing() async` - Stop transcription
- `modelDownloadProgress: Progress?` - Monitor model downloads

**TranscriptionResult struct** - What the stream yields
- `text: AttributedString` - The transcribed text with timing metadata
- `isFinal: Bool` - Whether this is a final result or partial (volatile)

**SpeechSessionError.swift** - All error cases with localized descriptions

### Internal Implementation Layers

**SpeechTranscriberManager.swift** - Manages `SpeechTranscriber` and `SpeechAnalyzer` lifecycle
- Creates `SpeechTranscriber` with `[.volatileResults]` and `[.audioTimeRange]` options
- Sets up `SpeechAnalyzer` with `AsyncStream<AnalyzerInput>` input sequence
- Yields audio buffers to the analyzer via `inputBuilder.yield(input)`

**AudioStreamer.swift** - Handles `AVAudioEngine` and microphone capture
- Installs tap on `audioEngine.inputNode` with 4096 buffer size
- Passes buffers to `SpeechTranscriberManager.processAudioBuffer()` synchronously

**BufferConverter.swift** - Converts audio buffers to analyzer format
- Critical: Uses `converter.primeMethod = .none` to avoid timestamp drift
- This is copied byte-for-byte from Apple's example

**ModelManager.swift** - Handles automatic model downloads
- Uses `requestLocaleSupport()` to trigger downloads
- Exposes `Progress` for UI feedback

**PermissionsManager.swift** - Requests microphone and speech recognition permissions

**AudioSessionManager.swift** - Configures `AVAudioSession` for recording

### Demo App (Aural/)

**MinimalTranscriptionView.swift** - The ~100 line example proving the API is simple
- Shows direct `SpeechSession` usage without any manager
- Handles both final and partial results
- This is the reference for "how easy the API is"

**TranscriptionManager.swift** - OPTIONAL advanced features (language selection, history)
- Uses `@Observable` macro for SwiftUI integration
- Stores `AttributedString` (not `String`) for `finalizedText` and `volatileText`
- Appends final results: `finalizedText += result.text`
- Styles partial results: `volatileText.foregroundColor = .purple.opacity(0.4)`

**ContentView.swift** - Entry point with toggle between "Simple" and "Advanced" modes

**TranscriptionView.swift** - Advanced demo with tabs, language selector, history

## Critical Implementation Details

### Result Handling Pattern (DO NOT BREAK THIS)

```swift
for try await result in session.startTranscribing() {
    if result.isFinal {
        finalizedText += result.text  // Append, don't replace
        partialText = ""
    } else {
        partialText = result.text  // Replace volatile text
    }
}
```

**Why this matters**:
- The Speech framework sets `result.isFinal` to indicate final vs volatile results
- Final results must be APPENDED to preserve full transcript
- Volatile results should REPLACE previous partial text (not append)
- Never check `foregroundColor` or other attributes to detect result type - use `isFinal`

### Buffer Conversion (DO NOT MODIFY WITHOUT APPLE'S GUIDANCE)

The `BufferConverter` class is copied from Apple's SpeechExample and must remain identical:
- `converter.primeMethod = .none` - Critical for timestamp accuracy
- Sample rate conversion to analyzer's preferred format
- Any changes here break transcription timing

### Model Downloads

When a locale hasn't been installed, AuralKit automatically downloads it:
- Progress is exposed via `session.modelDownloadProgress`
- Downloads happen in `ModelManager.ensureModel()`
- Uses `requestLocaleSupport()` followed by `requestLocaleStartup()`

## Common Pitfalls

1. **Don't rename the package to SpeechSession** - Only the class is named `SpeechSession`, the package stays `AuralKit`

2. **Don't convert to String prematurely** - Keep `AttributedString` throughout the pipeline to preserve timing metadata

3. **Don't check foregroundColor to detect result types** - Use `result.isFinal` flag from the Speech framework

4. **Don't replace final results** - Always append: `finalizedText += result.text`

5. **Don't make the API more complex** - The goal is that users can use it in ~30 lines without a manager class

## Testing

Tests are minimal since this wraps Apple's Speech framework:
- `testSpeechSessionInitialization()` - Verifies session creates successfully
- `testLocaleConfiguration()` - Verifies locale is respected

Real testing requires:
- Physical device (not simulator)
- Microphone access
- Speech recognition permissions
- Speaking into the device

## Requirements

- iOS 26.0+ / macOS 26.0+
- Swift 6.2+
- Xcode 26.0+
- Microphone and speech recognition permissions in Info.plist