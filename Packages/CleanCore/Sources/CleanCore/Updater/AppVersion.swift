import Foundation

/// A dotted app version ("1.10.2", build "1250") with component-wise ordering — the one
/// place the Updater decides whether a feed's version is newer than the installed one.
///
/// Rules (review F, D3):
/// - The string is split on ".". Two all-digit components compare numerically (so "1.10" >
///   "1.9", and a long build number never overflows); a missing trailing component counts as
///   0 when the other side's is numeric ("1.0" == "1.0.0", "2" > "1.9.9").
/// - Anything else (a "b1" or "rc" suffix, an empty component) compares lexicographically.
///   This is a documented **approximation**: "1.0b1" sorts after "1.0" instead of before it.
///   Only a strictly greater result ever claims an update, so a surprising order can at worst
///   miss one, never invent a downgrade as an update.
/// - Marketing versions and build numbers are separate namespaces; callers never compare
///   one against the other (see `AppcastRelease.verdict`).
public struct AppVersion: Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String
    private let components: [String]

    public init(_ rawValue: String) {
        self.rawValue = rawValue
        self.components = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
    }

    public var description: String { rawValue }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == .orderedSame
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> ComparisonResult {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : nil
            let right = index < rhs.components.count ? rhs.components[index] : nil
            let result = compareComponent(left, right)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    private static func compareComponent(_ left: String?, _ right: String?) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?):
            if let l = digits(left), let r = digits(right) { return compareDigits(l, r) }
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case let (left?, nil):
            // Missing counts as 0 against a numeric component, as "" against anything else.
            if let l = digits(left) { return compareDigits(l, "0") }
            return left.isEmpty ? .orderedSame : .orderedDescending
        case let (nil, right?):
            if let r = digits(right) { return compareDigits("0", r) }
            return right.isEmpty ? .orderedSame : .orderedAscending
        case (nil, nil):
            return .orderedSame
        }
    }

    /// The component without leading zeros when it is all ASCII digits, else `nil`.
    private static func digits(_ component: String) -> String? {
        guard !component.isEmpty, component.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let trimmed = component.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private static func compareDigits(_ left: String, _ right: String) -> ComparisonResult {
        if left.count != right.count { return left.count < right.count ? .orderedAscending : .orderedDescending }
        return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    }
}
