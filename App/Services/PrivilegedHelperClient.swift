import Foundation
import ServiceManagement
import CleanCore

public enum PrivilegedHelperError: Error, Sendable, LocalizedError {
    case notRegistered
    case requiresApproval
    case connectionFailed(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notRegistered:
            return "The privileged helper isn't installed yet."
        case .requiresApproval:
            return "The privileged helper needs approval in System Settings > General > Login Items."
        case .connectionFailed(let reason):
            return "Couldn't connect to the privileged helper: \(reason)"
        case .operationFailed(let reason):
            return reason
        }
    }
}

/// App-side wrapper for the `com.nextlabs.sosmac.privilegedhelper` daemon —
/// registration/status via `SMAppService.daemon(plistName:)` (never the
/// deprecated `SMJobBless`) plus an async wrapper around the XPC connection.
///
/// Registering a `LaunchDaemon` requires the user to authorize a
/// system-level process; `SMAppService` surfaces that as `.status ==
/// .requiresApproval` rather than silently failing, and callers must handle
/// it explicitly (point the user at System Settings > Login Items) instead
/// of treating it as an error.
@MainActor
@Observable
public final class PrivilegedHelperClient {
    private let service = SMAppService.daemon(plistName: PrivilegedHelperConstants.daemonPlistName)
    public private(set) var status: SMAppService.Status = .notRegistered

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        status = service.status
    }

    /// Registers the daemon. On success, `status` may still be
    /// `.requiresApproval` — that's expected, not a failure: the user must
    /// approve it in System Settings > General > Login Items before any
    /// operation below will actually succeed.
    public func register() throws {
        try service.register()
        refreshStatus()
    }

    public func unregister() throws {
        try service.unregister()
        refreshStatus()
    }

    public func trashSystemPath(_ path: String) async throws {
        try await withConnection { proxy, complete in
            proxy.trashSystemPath(path) { success, error in
                complete(Self.result(success: success, error: error))
            }
        }
    }

    public func purgeMemory() async throws {
        try await withConnection { proxy, complete in
            proxy.purgeMemory { success, error in
                complete(Self.result(success: success, error: error))
            }
        }
    }

    public func flushDNSCache() async throws {
        try await withConnection { proxy, complete in
            proxy.flushDNSCache { success, error in
                complete(Self.result(success: success, error: error))
            }
        }
    }

    public func manageSystemDaemon(plistPath: String, action: HelperOperationValidator.DaemonAction) async throws {
        try await withConnection { proxy, complete in
            proxy.manageSystemDaemon(plistPath: plistPath, action: action.rawValue) { success, error in
                complete(Self.result(success: success, error: error))
            }
        }
    }

    /// `Shell.run` supervises every subprocess call with a timeout so a call
    /// site never blocks unsupervised; the XPC round-trip here needs the
    /// same guarantee — the helper could theoretically wedge on a stuck
    /// syscall and never invoke its reply closure, which would otherwise
    /// hang the caller's `await` forever with no way to cancel from the UI.
    ///
    /// Three independent paths can produce a result here (the real reply,
    /// the connection's error handler, and the timeout), so completion runs
    /// through a `ResumeOnce` actor — whichever fires first wins, the rest
    /// are silently dropped, guaranteeing the continuation resumes exactly
    /// once regardless of which path wins the race.
    private func withConnection(
        _ body: @escaping (HelperXPCProtocol, @escaping @Sendable (Result<Void, Error>) -> Void) -> Void,
        timeout: TimeInterval = 30
    ) async throws {
        guard status == .enabled else {
            throw status == .requiresApproval ? PrivilegedHelperError.requiresApproval : PrivilegedHelperError.notRegistered
        }

        let connection = NSXPCConnection(machServiceName: PrivilegedHelperConstants.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let resumeGuard = ResumeOnce()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await resumeGuard.resume(continuation, with: .failure(PrivilegedHelperError.connectionFailed("Timed out waiting for the privileged helper.")))
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                timeoutTask.cancel()
                Task { await resumeGuard.resume(continuation, with: .failure(PrivilegedHelperError.connectionFailed(error.localizedDescription))) }
            } as? HelperXPCProtocol
            guard let proxy else {
                timeoutTask.cancel()
                Task { await resumeGuard.resume(continuation, with: .failure(PrivilegedHelperError.connectionFailed("Could not form a remote object proxy."))) }
                return
            }

            body(proxy) { result in
                timeoutTask.cancel()
                Task { await resumeGuard.resume(continuation, with: result) }
            }
        }
    }

    private static nonisolated func result(success: Bool, error: String?) -> Result<Void, Error> {
        success ? .success(()) : .failure(PrivilegedHelperError.operationFailed(error ?? "Unknown error"))
    }
}

/// Guarantees a `CheckedContinuation` is resumed exactly once even when
/// multiple independent completion paths (reply, connection error, timeout)
/// race to complete it — a plain `if`/`else` isn't enough once a third,
/// time-based path is added alongside the two XPC-driven ones.
private actor ResumeOnce {
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(with: result)
    }
}
