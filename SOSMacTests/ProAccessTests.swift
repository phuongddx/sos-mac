import Foundation
import Testing
@testable import SOSMac

/// The freemium gate through a fake provider: free users are gated on every
/// destructive action, both plans unlock, and an expired yearly plan gates
/// again after the next entitlement refresh. Scans/results are never gated
/// (the gate only wraps the confirmation actions in the views).
@MainActor
private final class FakeLicenseProvider: ProLicenseProviding {
    var isPro = false
    var plans: [ProPlan] = [
        ProPlan(id: "com.nextlabs.sosmac.pro.lifetime", kind: .lifetime, displayPrice: "$29.99"),
        ProPlan(id: "com.nextlabs.sosmac.pro.yearly", kind: .yearly, displayPrice: "$19.99"),
    ]
    var lastError: String?
    var purchasedPlanIDs: [String] = []
    var restoreCallCount = 0
    /// Simulates the yearly subscription lapsing between refreshes.
    var lapseOnNextRefresh = false

    func refresh() async {
        if lapseOnNextRefresh {
            isPro = false
            lapseOnNextRefresh = false
        }
    }

    func purchase(_ plan: ProPlan) async {
        purchasedPlanIDs.append(plan.id)
        isPro = true
    }

    func restore() async {
        restoreCallCount += 1
    }
}

@Suite("ProAccess freemium gate")
@MainActor
struct ProAccessTests {

    @Test("free user is gated and the paywall opens")
    func freeUserIsGated() async throws {
        let provider = FakeLicenseProvider()
        let pro = ProAccess(provider: provider)
        await pro.start()

        #expect(!pro.isPro)
        #expect(!pro.require(for: .junkCleaner))
        #expect(pro.paywallFeature == .junkCleaner)
        #expect(provider.purchasedPlanIDs.isEmpty)

        // Scans/results never consult the gate — nothing to assert there
        // beyond the require() contract itself.
        pro.dismissPaywall()
        #expect(pro.paywallFeature == nil)
    }

    @Test("lifetime purchase unlocks and closes the paywall")
    func lifetimeUnlocks() async throws {
        let provider = FakeLicenseProvider()
        let pro = ProAccess(provider: provider)
        await pro.start()

        #expect(!pro.require(for: .duplicateFinder))
        let lifetime = pro.plans.first { $0.kind == .lifetime }
        await pro.purchase(try #require(lifetime))

        #expect(pro.isPro)
        #expect(provider.purchasedPlanIDs == ["com.nextlabs.sosmac.pro.lifetime"])
        #expect(pro.paywallFeature == nil)
        #expect(pro.require(for: .duplicateFinder))
    }

    @Test("active yearly subscription unlocks")
    func yearlyActiveUnlocks() async throws {
        let provider = FakeLicenseProvider()
        let pro = ProAccess(provider: provider)
        await pro.start()

        #expect(!pro.require(for: .smartCare))
        let yearly = pro.plans.first { $0.kind == .yearly }
        await pro.purchase(try #require(yearly))

        #expect(pro.isPro)
        #expect(provider.purchasedPlanIDs == ["com.nextlabs.sosmac.pro.yearly"])
        #expect(pro.require(for: .smartCare))
    }

    @Test("expired yearly gates again after refresh")
    func yearlyExpiredReGates() async throws {
        let provider = FakeLicenseProvider()
        let pro = ProAccess(provider: provider)
        await pro.start()

        let yearly = pro.plans.first { $0.kind == .yearly }
        await pro.purchase(try #require(yearly))
        #expect(pro.isPro)

        // The subscription lapses; the next refresh (launch, foreground or
        // Transaction.updates) must re-close the gate.
        provider.lapseOnNextRefresh = true
        await pro.start()

        #expect(!pro.isPro)
        #expect(!pro.require(for: .smartCare))
        #expect(pro.paywallFeature == .smartCare)
    }

    @Test("restore with no purchases reports nothing found and stays gated")
    func restoreNothingFound() async throws {
        let provider = FakeLicenseProvider()
        let pro = ProAccess(provider: provider)
        await pro.start()

        pro.require(for: .uninstaller)
        await pro.restore()

        #expect(provider.restoreCallCount == 1)
        #expect(!pro.isPro)
        #expect(pro.paywallFeature == .uninstaller)
        #expect(pro.restoreMessage != nil)
    }

    @Test("paywall exposes provider plans with localized prices")
    func plansComeFromProvider() async throws {
        let provider = FakeLicenseProvider()
        let pro = ProAccess(provider: provider)
        await pro.start()

        #expect(pro.plans.map(\.kind) == [.lifetime, .yearly])
        #expect(pro.plans.map(\.displayPrice) == ["$29.99", "$19.99"])
    }
}
