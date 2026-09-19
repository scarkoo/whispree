import AppKit
import ApplicationServices
import AVFoundation
import Foundation

/// Minimal permission manager for the local-only fork.
/// Only microphone and Accessibility are required.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    enum Status: Equatable {
        case notDetermined, granted, denied, unavailable
    }

    @Published private(set) var microphone: Status = .notDetermined
    @Published private(set) var accessibility: Status = .notDetermined

    private var refreshTimer: Timer?

    private init() {
        refreshAll()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAll() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAll() }
        }
    }

    func refreshAll() {
        microphone = Self.currentMicrophoneStatus()
        accessibility = AXIsProcessTrusted() ? .granted : .denied
    }

    func refreshSystemPermissionsOnly() {
        refreshAll()
    }

    func requestMicrophone() async -> Status {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
        microphone = granted ? .granted : .denied
        return microphone
    }

    @discardableResult
    func requestAccessibility() -> Status {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibility = trusted ? .granted : .denied
        return accessibility
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func currentMicrophoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .unavailable
        }
    }
}
