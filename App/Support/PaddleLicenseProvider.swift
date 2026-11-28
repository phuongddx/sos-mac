#if !MAS_BUILD
import Foundation

/// DMG-build provider: the license seam is Paddle-shaped but fully stubbed —
/// configuration comes from Info.plist keys (empty by default), no secret is
/// ever hardcoded, and no network call is made. The real Paddle SDK wiring
/// and its 3-Mac activation limit live outside this repo; this type only
/// reserves the integration point so the DMG build can be exercised end to
/// end before the account/product exist.
///
/// Info.plist keys (set via xcconfig → INFOPLIST_KEY_* when configured):
/// - `PaddleProductID`  — the Paddle product id for Pro
/// - `PaddleVendorID`   — Paddle vendor id
/// - `ProLifetimePrice` / `ProYearlyPrice` — display strings for the paywall
@MainActor
final class PaddleLicenseProvider: ProLicenseProviding {
    private(set) var isPro = false
    private(set) var plans: [ProPlan] = []
    private(set) var lastError: String?

    private let info: [String: String]

    init(info: [String: String] = PaddleLicenseProvider.bundleConfig) {
        self.info = info
        plans = Self.plans(from: info)
    }

    func refresh() async {
        // Stub: with no real Paddle SDK there is nothing to validate; a
        // configured-but-unsupported build stays free (fail closed).
        isPro = false
    }

    func purchase(_ plan: ProPlan) async {
        lastError = "Paddle checkout isn't wired up yet — this DMG build is a pre-release stub."
    }

    func restore() async {
        lastError = "Paddle license validation isn't wired up yet — this DMG build is a pre-release stub."
    }

    // MARK: - Config

    private static var bundleConfig: [String: String] {
        let keys = ["PaddleProductID", "PaddleVendorID", "ProLifetimePrice", "ProYearlyPrice"]
        var config: [String: String] = [:]
        for key in keys {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
                config[key] = value
            }
        }
        return config
    }

    private static func plans(from config: [String: String]) -> [ProPlan] {
        [
            ProPlan(id: "pro.lifetime", kind: .lifetime,
                    displayPrice: config["ProLifetimePrice"] ?? "$29.99"),
            ProPlan(id: "pro.yearly", kind: .yearly,
                    displayPrice: config["ProYearlyPrice"] ?? "$19.99"),
        ]
    }
}

#if DEBUG
/// DEBUG-only fake for the DMG build: purchase/restore flip `isPro` exactly
/// like a real license would, so the unlock flow (paywall → gate opens) is
/// testable without Paddle. Never compiled into Release.
@MainActor
final class MockLicenseProvider: ProLicenseProviding {
    private(set) var isPro = false
    private(set) var plans: [ProPlan] = [
        ProPlan(id: "pro.lifetime", kind: .lifetime, displayPrice: "$29.99"),
        ProPlan(id: "pro.yearly", kind: .yearly, displayPrice: "$19.99"),
    ]
    private(set) var lastError: String?

    func refresh() async {}

    func purchase(_ plan: ProPlan) async {
        isPro = true
    }

    func restore() async {
        // Restoring finds nothing unless something was "purchased" first —
        // the same honest shape as the real store.
    }
}
#endif
#endif
