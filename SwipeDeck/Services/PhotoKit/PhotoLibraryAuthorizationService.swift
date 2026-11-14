import Foundation
import Photos
import UIKit

/// Manages PhotoKit `.readWrite` authorization status and deep-linking to iOS Settings if denied.
@MainActor
@Observable
public final class PhotoLibraryAuthorizationService {
    public enum AccessState: Equatable, Sendable {
        case notDetermined
        case authorized
        case limited
        case denied
    }

    public private(set) var accessState: AccessState = .notDetermined
    public private(set) var isRequestingPermission = false

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        accessState = Self.mapStatus(status)
    }

    /// Requests Photo Library authorization on explicit user action (or checks existing status),
    /// using the callback-based API dispatched back to `@MainActor` to avoid Swift concurrency suspension races.
    public func requestAccess() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else {
            accessState = Self.mapStatus(current)
            return
        }
        guard !isRequestingPermission else { return }
        isRequestingPermission = true

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            Task { @MainActor in
                self.isRequestingPermission = false
                self.accessState = Self.mapStatus(status)
            }
        }
    }

    public func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func mapStatus(_ status: PHAuthorizationStatus) -> AccessState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
