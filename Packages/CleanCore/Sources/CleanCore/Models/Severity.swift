public enum Severity: String, Sendable, Codable, CaseIterable, Comparable {
    case safe
    case caution
    case risky

    private var rank: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .risky: return 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}
