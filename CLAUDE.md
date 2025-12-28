# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the Swift package
swift build

# Build the Xcode project (demo app)
xcodebuild -project Aural.xcodeproj -scheme Aural -configuration Debug build

# Clean and rebuild Xcode project
xcodebuild clean -project Aural.xcodeproj -scheme Aural -configuration Debug build
```

## Linting

```bash
swiftlint lint
```

## Testing

```bash
# Run all tests
swift test

# Run a specific test file
swift test --filter FileTranscriptionTests

# Run tests with verbose output
swift test -v
```

## Project Structure

**AuralKit** is a Swift wrapper for iOS 26+/macOS 26+ `SpeechTranscriber` and `SpeechAnalyzer` APIs.

### Core Architecture

- **SpeechSession** (`SpeechSession.swift`) - Main `actor` entry point; coordinates permission checks, audio engine lifecycle, and async streams
- **Extensions** split concerns:
  - `SpeechSession+Pipeline.swift` - Permissions, audio session activation, stream wiring, teardown
  - `SpeechSession+Transcriber.swift` - Analyzer graph building, optional module installation (SpeechDetector), audio buffer feeding
  - `SpeechSession+Audio.swift` - Audio engine setup, tap installation, buffer conversion
  - `SpeechSession+CustomVocabulary.swift` - Custom vocabulary configuration
  - `SpeechSession+File.swift` - File-based transcription
  - `SpeechSession+VoiceActivation.swift` - VAD configuration

### Supporting Types

- **ModelManager** - Ensures locale models present, tracks download progress, releases reserved locales
- **BufferConverter** - Converts tap buffers to `AVAudioPCMBuffer` for analyzer compatibility
- **DeviceCapabilities** - Queries available transcriber modules and supported locales
- **AudioInputInfo** - Audio route change notifications
- **SpeechSessionError** - Comprehensive error types with localization

### Demo App

The `Aural/` directory contains a SwiftUI demo app showcasing live transcription, language selection, and history tracking.

## Key Patterns

- `SpeechSession` is an `actor` - all methods are isolated and thread-safe
- Transcriptions return `AttributedString` with `audioTimeRange` in runs for timing metadata
- Voice activation (VAD) is opt-in via `SpeechDetector` module on supported platforms
- Locale models auto-download with progress available via `modelDownloadProgress`
