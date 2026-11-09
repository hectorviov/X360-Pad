// Installs (activates) the embedded driver extension, com.hectorviov.x360pad.driver. macOS asks the user to allow it once, in System Settings >
// General > Login Items & Extensions > Driver Extensions; the app must be in /Applications.
import Foundation
import SystemExtensions

@MainActor
final class DriverInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    static let identifier = "com.hectorviov.x360pad.driver"

    enum State: Equatable {
        case unknown, installing, needsApproval, installed, failed(String)
    }
    @Published private(set) var state: State = .unknown

    var inApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    private var onProperties: ((Bool) -> Void)?

    /// Asks macOS whether the driver is installed and enabled; calls back on the main queue.
    func refresh(_ done: @escaping (Bool) -> Void) {
        onProperties = done
        let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let enabled = properties.contains { $0.isEnabled && !$0.isUninstalling }
        let waiting = properties.contains { $0.isAwaitingUserApproval }
        log.info("driver: \(properties.count, privacy: .public) installed version(s), enabled \(enabled, privacy: .public)")
        MainActor.assumeIsolated {
            state = enabled ? .installed : waiting ? .needsApproval : .unknown
            onProperties?(enabled); onProperties = nil
        }
    }

    func install() {
        state = .installing
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        log.info("driver: activation requested")
    }

    func uninstall() {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        log.info("driver: deactivation requested")
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("driver: replacing \(existing.bundleShortVersion, privacy: .public) (\(existing.bundleVersion, privacy: .public)) with \(ext.bundleShortVersion, privacy: .public) (\(ext.bundleVersion, privacy: .public))")
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.info("driver: waiting for the user's approval in System Settings")
        MainActor.assumeIsolated { state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log.info("driver: request finished (\(result.rawValue, privacy: .public))")
        MainActor.assumeIsolated { state = result == .completed ? .installed : .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message = error.localizedDescription
        log.error("driver: request failed: \(message, privacy: .public)")
        MainActor.assumeIsolated { state = .failed(message) }
    }
}
