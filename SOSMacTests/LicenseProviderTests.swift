import Foundation
import Testing
@testable import SOSMac

/// DMG-build unlock seam: the DEBUG mock provider drives the same ProAccess
/// flow as the MAS build, and the Paddle stub stays fail-closed (free, no
/// network, no hardcoded secrets) until real configuration lands.
@Suite("DMG license providers")
@MainActor
struct LicenseProviderTests {

    @Test("mock provider unlocks through the paywall purchase path")
    func mockUnlocks() async {
        let pro = ProAccess(provider: MockLicenseProvider())
        await pro.start()

        #expect(!pro.isPro)
        #expect(!pro.require(for: .uninstaller))
        #expect(pro.paywallFeature == .uninstaller)

        let lifetime = pro.plans.first { $0.kind == .lifetime }
        await pro.purchase(try #require(lifetime))

        #expect(pro.isPro)
        #expect(pro.require(for: .uninstaller))
        #expect(pro.paywallFeature == nil)
    }

    @Test("mock restore without a purchase finds nothing")
    func mockRestoreFindsNothing() async {
        let pro = ProAccess(provider: MockLicenseProvider())
        await pro.start()

        await pro.restore()
        #expect(!pro.isPro)
        #expect(pro.restoreMessage != nil)
    }

    @Test("Paddle stub with empty config stays free and fails closed")
    func paddleStubFailClosed() async {
        let provider = PaddleLicenseProvider(info: [:])
        let pro = ProAccess(provider: provider)
        await pro.start()

        #expect(!pro.isPro)
        // Plans still describe the product (paywall renders), but purchase
        // can never succeed through the stub.
        #expect(provider.plans.map(\.kind) == [.lifetime, .yearly])

        let lifetime = pro.plans.first { $0.kind == .lifetime }
        await pro.purchase(try #require(lifetime))
        #expect(!pro.isPro)
        #expect(pro.purchaseError != nil)

        await pro.restore()
        #expect(!pro.isPro)
        #expect(provider.lastError != nil)
    }

    @Test("Paddle stub reads display prices from configuration")
    func paddleStubPlansFromConfig() async {
        let provider = PaddleLicenseProvider(info: [
            "PaddleProductID": "pro_123",
            "ProLifetimePrice": "$39.99",
            "ProYearlyPrice": "$25.99",
        ])
        #expect(provider.plans.map(\.displayPrice) == ["$39.99", "$25.99"])
    }
}
