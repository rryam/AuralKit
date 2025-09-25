import AVFoundation
import Speech

// MARK: - Permissions Manager

class PermissionsManager: @unchecked Sendable {

    /// Check if all required permissions are granted
    func ensurePermissions() async throws {
        // Check microphone permission (iOS & macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AuralKitError.microphonePermissionDenied
            }
        default:
            throw AuralKitError.microphonePermissionDenied
        }

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
