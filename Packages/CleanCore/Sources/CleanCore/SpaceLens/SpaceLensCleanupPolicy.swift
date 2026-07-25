import Foundation

public enum SpaceLensCleanupEligibility: Sendable, Equatable {
    case eligible
    case ineligible(reason: String)
}

/// Centralizes the conservative rules for Space Lens cleanup candidates.
/// The UI must use this policy before adding an item to its review cart;
/// actual removal remains exclusively `Cleaner.clean(_:)` / Trash-routed.
public struct SpaceLensCleanupPolicy: Sendable {
    public init() {}

    public func eligibility(for item: ScanItem, scanRootPath: String) -> SpaceLensCleanupEligibility {
        let root = standardizedPath(scanRootPath)
        let path = standardizedPath(item.path)

        guard path != root else {
            return .ineligible(reason: "The scanned location itself can’t be removed.")
        }
        guard isDescendant(path, of: root) else {
            return .ineligible(reason: "This item is outside the scanned location.")
        }
        guard !protectedRoots.contains(where: { path == $0 || isDescendant(path, of: $0) }) else {
            return .ineligible(reason: "This is a protected system location.")
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            return .ineligible(reason: "You don’t have permission to move this item to Trash.")
        }
        return .eligible
    }

    /// Removes selected descendants of another selected directory so a cart
    /// represents each removable subtree once and never double-counts bytes.
    public func normalizedSelection(from items: [ScanItem], scanRootPath: String) -> [ScanItem] {
        let root = standardizedPath(scanRootPath)
        let eligibleItems = items.filter { item in
            let path = standardizedPath(item.path)
            return path != root && isDescendant(path, of: root)
        }
        let ordered = eligibleItems.sorted {
            let lhs = standardizedPath($0.path)
            let rhs = standardizedPath($1.path)
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            return lhsDepth == rhsDepth ? lhs < rhs : lhsDepth < rhsDepth
        }

        var roots: [ScanItem] = []
        for item in ordered {
            let path = standardizedPath(item.path)
            guard !roots.contains(where: { isDescendant(path, of: standardizedPath($0.path)) }) else { continue }
            roots.append(item)
        }
        return roots
    }

    private var protectedRoots: [String] {
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
        return (["/System", "/private", "/usr", "/bin", "/sbin"] + [trash].compactMap { $0 })
            .map(standardizedPath)
    }

    private func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func isDescendant(_ path: String, of root: String) -> Bool {
        root == "/" ? path.hasPrefix("/") && path != "/" : path.hasPrefix(root + "/")
    }
}
