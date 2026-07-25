import Foundation

/// `ProtectionScanner`'s two offline detection sources. VirusTotal is
/// deliberately not a case here — it's a supplementary lookup a user
/// triggers per finding (see `ProtectionViewModel.lookupVirusTotal`), never a
/// source of new findings itself, so there's no `ThreatFinding` it would
/// ever be assigned to.
public enum DetectionMethod: String, Sendable, Codable {
    case hash
    case yara
}

/// A single detected threat. Deliberately not a `ScanItem` — a malware match
/// carries detection provenance (method + matched identifier) that junk/dup
/// items have no concept of, and `Cleaner`'s trash-and-forget semantics don't
/// fit here: a flagged file goes to `QuarantineManager` (reversible, with a
/// restore path) rather than straight to Trash.
public struct ThreatFinding: Sendable, Codable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let detectionMethod: DetectionMethod
    /// The matched SHA-256 hash or YARA rule identifier — whichever
    /// `detectionMethod` produced this finding.
    public let identifier: String
    public let detectedAt: Date

    public init(
        path: String,
        size: Int64,
        detectionMethod: DetectionMethod,
        identifier: String,
        detectedAt: Date = Date()
    ) {
        self.path = path
        self.size = size
        self.detectionMethod = detectionMethod
        self.identifier = identifier
        self.detectedAt = detectedAt
    }
}
