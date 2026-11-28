import Foundation
import Observation

/// One purchasable Pro plan as the paywall shows it. The localized price
/// string always comes from the provider (StoreKit's `Product.displayPrice`
/// in the MAS build, license config in the DMG build) — never hardcoded in
/// the app, so prices can't drift from what the store charges.
struct ProPlan: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Buy once, keep forever (non-consumable in StoreKit).
        case lifetime
        /// Auto-renewable subscription.
        case yearly
    }

    /// The store product / license id (`com.nextlabs.sosmac.pro.lifetime`…).
    let id: String
    let kind: Kind
    /// Localized, currency-formatted display price ("$29.99").
    let displayPrice: String
}

/// The feature a paywall request came from — shown in the sheet's copy so the
/// person knows exactly what unlocking enables.
enum ProFeature: String, Identifiable, Sendable, CaseIterable {
    case junkCleaner = "Junk & Cache"
    case smartCare = "Smart Care"
    case duplicateFinder = "Duplicate Finder"
    case spaceLens = "Space Lens"
    case uninstaller = "Uninstaller"
    case protection = "Protection"

    var id: String { rawValue }
}

/// The seam between the app and whichever unlock mechanism a build ships:
/// StoreKit 2 in the Mac App Store build, a license provider in the DMG
/// build. `isPro` is the single gate every destructive action checks; scans
/// and results are always free and never consult the provider.
@MainActor
protocol ProLicenseProviding: AnyObject {
    /// Whether the person currently holds an active Pro entitlement.
    var isPro: Bool { get }
    /// The plans the paywall offers (localized prices included).
    var plans: [ProPlan] { get }
    /// A human-readable failure of the last purchase/restore, if any.
    var lastError: String? { get }

    /// Re-reads entitlements (launch, foreground, Transaction.updates).
    func refresh() async
    /// Starts the purchase (or license activation) flow for `plan`.
    func purchase(_ plan: ProPlan) async
    /// Restores past purchases (AppStore.sync / license re-check).
    func restore() async
}

/// The app-wide Pro entitlement. Free tier: every scan and every results
/// screen. Pro: the actions that actually delete — clean junk, trash
/// duplicates, empty the Space Lens cleanup list, uninstall apps,
/// quarantine threats.
@MainActor
@Observable
final class ProAccess {
    private(set) var isPro: Bool
    private(set) var plans: [ProPlan] = []
    /// Set while the paywall sheet is up; `nil` otherwise.
    private(set) var paywallFeature: ProFeature?
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?
    private(set) var restoreMessage: String?

    private let provider: any ProLicenseProviding

    /// Test seam: the default provider is the build's real one; tests inject
    /// a fake and drive `isPro` through it.
    init(provider: (any ProLicenseProviding)? = nil) {
        #if MAS_BUILD
        self.provider = provider ?? StoreKitProProvider()
        #else
        #if DEBUG
        self.provider = provider ?? MockLicenseProvider()
        #else
        self.provider = provider ?? PaddleLicenseProvider()
        #endif
        #endif
        isPro = self.provider.isPro
    }

    // MARK: - Lifecycle

    /// Launch + foreground: reload entitlements and prices.
    func start() async {
        await provider.refresh()
        syncFromProvider()
    }

    private func syncFromProvider() {
        isPro = provider.isPro
        plans = provider.plans
        purchaseError = provider.lastError
    }

    // MARK: - The gate

    /// The single call every destructive action makes: returns true (and
    /// nothing else) when the person is Pro; otherwise presents the paywall
    /// and returns false. Scans and results never call this — they are free.
    @discardableResult
    func require(for feature: ProFeature) -> Bool {
        if isPro { return true }
        paywallFeature = feature
        return false
    }

    func dismissPaywall() {
        paywallFeature = nil
        purchaseError = nil
        restoreMessage = nil
    }

    // MARK: - Paywall actions

    func purchase(_ plan: ProPlan) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        restoreMessage = nil
        await provider.purchase(plan)
        syncFromProvider()
        isPurchasing = false
        // A successful purchase closes the sheet; a failure keeps it open
        // with the error banner.
        if isPro { paywallFeature = nil }
    }

    func restore() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        restoreMessage = nil
        await provider.restore()
        syncFromProvider()
        isPurchasing = false
        if isPro {
            paywallFeature = nil
        } else if purchaseError == nil {
            restoreMessage = "No previous purchases were found for this Apple Account."
        }
    }
}
