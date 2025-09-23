#if os(iOS)
import AVFoundation
#endif
import Speech

// MARK: - Permissions Manager

class PermissionsManager: @unchecked Sendable {

    /// Check if all required permissions are granted
    func ensurePermissions() async throws {
        // Check microphone permission
#if os(iOS)
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AuralKitError.microphonePermissionDenied
            }
        }
#endif

        // Check speech recognition permission
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted {
                throw AuralKitError.speechRecognitionPermissionDenied
            }
        default:
            throw AuralKitError.speechRecognitionPermissionDenied
        }
    }
}
