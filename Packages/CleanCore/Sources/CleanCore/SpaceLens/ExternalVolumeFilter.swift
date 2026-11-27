import Foundation

/// Which mounted volumes Space Lens offers as scan sources (review F, D8).
///
/// The old rule kept only `volumeIsRemovable == true`, which silently dropped non-removable
/// external SSDs — they report `isRemovable == false, isInternal == false`. The classifier is
/// a pure function over injected flag sets so the rule is unit-testable without mounting
/// hardware: a volume is offered only when it is local **and** either removable or not
/// internal. A missing flag excludes the volume — fail closed, never a guess.
public enum ExternalVolumeFilter {

    /// The volume flags `URLResourceValues` reports: `volumeIsLocalKey`,
    /// `volumeIsRemovableKey`, `volumeIsInternalKey`. `nil` is a flag the system did not
    /// report for that volume.
    public struct Flags: Sendable, Equatable {
        public let isLocal: Bool?
        public let isRemovable: Bool?
        public let isInternal: Bool?

        public init(isLocal: Bool?, isRemovable: Bool?, isInternal: Bool?) {
            self.isLocal = isLocal
            self.isRemovable = isRemovable
            self.isInternal = isInternal
        }
    }

    /// `true` only for a local volume that is removable or not internal: the boot volume
    /// (internal, not removable) and network volumes (not local) stay out, while a
    /// non-removable external SSD gets in. Any missing flag excludes the volume.
    public static func includes(_ flags: Flags) -> Bool {
        guard let isLocal = flags.isLocal,
              let isRemovable = flags.isRemovable,
              let isInternal = flags.isInternal else { return false }
        return isLocal && (isRemovable || !isInternal)
    }
}
