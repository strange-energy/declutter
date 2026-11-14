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

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        accessState = Self.mapStatus(status)
    }

    public func requestAccessIfNeeded() async -> AccessState {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            let mapped = Self.mapStatus(granted)
            self.accessState = mapped
            return mapped
        } else {
            let mapped = Self.mapStatus(current)
            self.accessState = mapped
            return mapped
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
