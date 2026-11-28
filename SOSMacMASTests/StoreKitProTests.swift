import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import SOSMacMAS

/// StoreKit 2 evidence against the local `StoreKit/SOSMacPro.storekit`
/// configuration (attached to the SOSMacMAS scheme). These tests run in the
/// MAS app host (module `SOSMacMAS`, `MAS_BUILD`), so the real
/// `StoreKitProProvider` is what loads the products.
///
/// Scope (and one documented limitation):
/// - Products load from the local store with the exact ids, kinds and
///   prices the App Store Connect products will carry — proof the MAS build
///   runs against the `.storekit` configuration without touching ASC.
/// - The gate presents the paywall when free (`ProAccess.require`).
///
/// What cannot be proven here: `session.buyProduct` purchases ARE visible in
/// `Transaction.all` (and delivered through `Transaction.updates`) in this
/// app-host environment, but `Transaction.currentEntitlements` — the API the
/// provider reads in production — returns an empty sequence for them on this
/// SDK (macOS 27 / Xcode 26.2 StoreKitTest). A transaction bought through
/// `Product.purchase()` headlessly also returns `.userCancelled`. So the
/// full purchase → entitlement unlock path is covered by
/// `SOSMacTests/ProAccessTests.swift` with a fake provider (all four cases:
/// free gated, lifetime unlocks, yearly unlocks, yearly-expired re-gates),
/// and the entitlement-reading code itself is deliberately thin
/// (`reloadEntitlements` below). When StoreKitTest's currentEntitlements
/// works for app-host sessions, extend these tests with the real purchase
/// path.
@Suite("StoreKit Pro provider (local .storekit)")
@MainActor
struct StoreKitProTests {

    @Test("products load from the local store with the exact ASC shape")
    func productsLoadFromLocalStore() async throws {
        let session = try SKTestSession(configurationFileNamed: "SOSMacPro")
        session.disableDialogs = true
        session.clearTransactions()

        let pro = ProAccess(provider: StoreKitProProvider())
        await pro.start()

        #expect(pro.plans.count == 2)
        // Lifetime is the recommended plan and always sorts first.
        #expect(pro.plans.map(\.kind) == [.lifetime, .yearly])
        #expect(pro.plans.map(\.id) == [
            "com.nextlabs.sosmac.pro.lifetime",
            "com.nextlabs.sosmac.pro.yearly",
        ])
        // Prices come from the store (displayPrice), never hardcoded.
        #expect(pro.plans[0].displayPrice.contains("29.99"))
        #expect(pro.plans[1].displayPrice.contains("19.99"))

        session.clearTransactions()
    }

    @Test("free user sees the paywall, not a silent failure")
    func freeUserSeesPaywall() async throws {
        let session = try SKTestSession(configurationFileNamed: "SOSMacPro")
        session.disableDialogs = true
        session.clearTransactions()

        let pro = ProAccess(provider: StoreKitProProvider())
        await pro.start()

        #expect(!pro.isPro)
        #expect(!pro.require(for: .junkCleaner))
        #expect(pro.paywallFeature == .junkCleaner)
        pro.dismissPaywall()
        #expect(pro.paywallFeature == nil)

        session.clearTransactions()
    }

    @Test("a session purchase appears in Transaction.all (store is live)")
    func sessionPurchaseIsVisibleToStoreKit() async throws {
        let session = try SKTestSession(configurationFileNamed: "SOSMacPro")
        session.disableDialogs = true
        session.clearTransactions()

        let transaction = try await session.buyProduct(identifier: "com.nextlabs.sosmac.pro.lifetime")
        #expect(transaction.productID == "com.nextlabs.sosmac.pro.lifetime")
        #expect(transaction.revocationDate == nil)

        var seen = 0
        for await result in Transaction.all {
            if case .verified(let t) = result, t.productID == "com.nextlabs.sosmac.pro.lifetime" {
                seen += 1
            }
        }
        #expect(seen == 1)

        session.clearTransactions()
    }
}
