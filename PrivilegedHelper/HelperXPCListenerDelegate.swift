import Foundation
import Security
import CleanCore

/// Accepts (or rejects) every incoming XPC connection. This is the entire
/// security boundary of a root-privileged daemon — a bug here means any
/// process on the machine can drive root-level file deletion and daemon
/// management, so it fails closed on every uncertain path (missing code
/// object, API error, requirement mismatch).
final class HelperXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.callerMatchesExpectedClient(connection: newConnection) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = HelperOperations()
        newConnection.resume()
        return true
    }

    /// Validates the connecting process's code signature by identifier —
    /// never "something connected to my Mach service" alone. Known gap,
    /// disclosed: this checks bundle identifier only, not a Team ID anchor
    /// (`anchor apple generic and certificate leaf[subject.OU] = "TEAMID"`),
    /// because this build has no real Apple Developer Team configured yet
    /// (see Phase 0/6/7's identical disclosed gap). Identifier-only checks
    /// are weaker than a full trust-chain requirement — an ad-hoc-signed
    /// impostor with the same bundle identifier could pass this check. Once
    /// a real Developer Team exists (Phase 9), this requirement string MUST
    /// be tightened to also pin the team identifier.
    private static func callerMatchesExpectedClient(connection: NSXPCConnection) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return false
        }

        var requirement: SecRequirement?
        let requirementString = "identifier \"\(PrivilegedHelperConstants.expectedClientBundleIdentifier)\"" as CFString
        guard SecRequirementCreateWithString(requirementString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
