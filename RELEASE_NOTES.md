# Release Notes

## 1.4.0 – 2025-10-11

### Added
- File transcription support via `streamTranscription` and `transcribe`, including validation helpers and optional progress reporting.
- Voice activation controls that wire `SpeechDetector` into the analyzer, along with `speechDetectorResultsStream` and `isSpeechDetected` state.
- Session lifecycle observability: status stream, pause/resume APIs, and transcriber preset selection in the demo app.
- Configurable logging with `SpeechSession.LogLevel`, a global toggle, and privacy-aware `OSLog` integration.
- Device capability helper exposing supported/installed locales and dictation availability across platforms.

### Improved
- Unified permission checks, hardened audio/file streaming cleanup, and introduced explicit streaming mode tracking inside `SpeechSession`.
- Expanded documentation covering observability, voice activation, and file transcription workflows.

### Fixed
- Resolved premature completion and analyzer race conditions when swapping pipeline modes or ingesting files.
- Stabilized file transcription state when presets change or ingestion is cancelled mid-stream.

### Tooling & Tests
- Migrated the test suite to Swift Testing and added coverage for logging, voice activation, and file transcription behaviors.

## 1.3.0 – 2025-10-10

- Refactored `SpeechSession` into main-actor isolated components (`Audio`, `Pipeline`, `Transcriber`) for safer concurrency and clearer structure.
- Added initial async transcription stream API and baseline smoke tests.
