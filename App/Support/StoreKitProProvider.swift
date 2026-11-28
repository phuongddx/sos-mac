#if MAS_BUILD
import Foundation
import StoreKit

/// StoreKit 2 provider for the Mac App Store build.
///
/// Products (created on App Store Connect; mirrored in
/// `StoreKit/SOSMacPro.storekit` for local testing):
/// - `com.nextlabs.sosmac.pro.lifetime` — non-consumable, $29.99
/// - `com.nextlabs.sosmac.pro.yearly` — auto-renewable, $19.99/year,
///   subscription group "SOS Mac Pro"
///
/// Entitlement policy (fail closed): only **verified** transactions count;
/// a revoked transaction never unlocks; a subscription counts while it is
/// in `currentEntitlements` (StoreKit already excludes expired ones).
/// `Transaction.updates` is listened to for the whole session, so
/// revocation/expiry/refunds land without a relaunch.
@MainActor
final class StoreKitProProvider: ProLicenseProviding {
    static let lifetimeID = "com.nextlabs.sosmac.pro.lifetime"
    static let yearlyID = "com.nextlabs.sosmac.pro.yearly"

    private(set) var isPro = false
    private(set) var plans: [ProPlan] = []
    private(set) var lastError: String?

    private var products: [Product] = []
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            // Session-long listener: purchases made in System Settings,
            // refunds and revocations all arrive here.
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await reloadEntitlements()
        await loadProducts()
    }

    func purchase(_ plan: ProPlan) async {
        lastError = nil
        guard let product = products.first(where: { $0.id == plan.id }) else {
            lastError = "This plan isn't available in the store right now."
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await reloadEntitlements()
                } else {
                    // Fail closed: an unverified transaction never unlocks.
                    lastError = "The purchase couldn't be verified."
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch StoreKitError.notAvailableInStorefront {
            lastError = "Pro isn't available in your storefront."
        } catch is CancellationError {
            // The person closed the sheet — not an error.
            lastError = nil
        } catch {
            lastError = "The purchase couldn't be completed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await reloadEntitlements()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Internals

    private func reloadEntitlements() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.revocationDate != nil { continue }
            if transaction.productID == Self.lifetimeID || transaction.productID == Self.yearlyID {
                pro = true
            }
        }
        isPro = pro
    }

    private func loadProducts() async {
        do {
            let ids = [Self.lifetimeID, Self.yearlyID]
            let loaded = try await Product.products(for: ids)
            products = loaded
            plans = loaded.map { product in
                let kind: ProPlan.Kind = product.id == Self.lifetimeID ? .lifetime : .yearly
                return ProPlan(id: product.id, kind: kind, displayPrice: product.displayPrice)
            }
            // Fail closed on ordering: lifetime first (the recommended one),
            // then yearly; anything unexpected keeps store order.
            plans.sort { lhs, rhs in
                switch (lhs.kind, rhs.kind) {
                case (.lifetime, .yearly): true
                case (.yearly, .lifetime): false
                default: lhs.id < rhs.id
                }
            }
        } catch {
            // Offline first launch: the paywall shows no plans rather than
            // invented ones; entitlements above still load from the receipt.
            plans = []
        }
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        await transaction.finish()
        await reloadEntitlements()
    }
}
#endif
