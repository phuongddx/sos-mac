# Freemium Pro paywall

Model: **free scanning, Pro cleaning.** Every scan, every results screen and
every review list is free in both builds; the actions that actually delete —
clean junk, trash duplicates, empty the Space Lens cleanup list, uninstall
apps, quarantine threats — require Pro.

## Products

| Plan | Product id | Type | Price |
|---|---|---|---|
| Pro Lifetime | `com.nextlabs.sosmac.pro.lifetime` | non-consumable | $29.99 (one purchase) |
| Pro Yearly | `com.nextlabs.sosmac.pro.yearly` | auto-renewable, group **SOS Mac Pro** | $19.99/year |

Prices in the MAS build always come from `Product.displayPrice` — never
hardcoded. `StoreKit/SOSMacPro.storekit` mirrors both products for local
testing and is attached to the `SOSMacMAS` scheme.

## MAS build (StoreKit 2)

`App/Support/StoreKitProProvider.swift`:
- `Transaction.updates` listener for the whole session (refunds, revocations,
  renewals land without a relaunch).
- `Transaction.currentEntitlements` read at launch/refresh — **verified
  transactions only**, revoked transactions never unlock, expired
  subscriptions are excluded by StoreKit.
- `purchase` → `Product.purchase()` → `transaction.finish()`; unverified
  results fail closed.
- **Restore Purchases** → `AppStore.sync()` then a fresh entitlement read.
- No license-key field anywhere in the MAS build (guideline 3.1.1).

## DMG build (license seam)

`App/Support/PaddleLicenseProvider.swift` — a stub with the real Paddle
shape: configuration comes from Info.plist keys (`PaddleProductID`,
`PaddleVendorID`, `ProLifetimePrice`, `ProYearlyPrice`), empty by default; no
secret is hardcoded and no network call is made. The 3-Mac activation limit
lives on the Paddle side when the account/product exist. A DEBUG-only
`MockLicenseProvider` lets the DMG unlock flow be exercised end-to-end.

## Paywall UI

`App/Support/PaywallView.swift` — a sheet presented from `RootView` whenever
`ProAccess.require(for:)` gates an action. Design-system components and
Theme tokens only; two plan cards (lifetime highlighted), localized price
from the provider, Restore Purchases, and Terms/Privacy links (placeholder
URLs overridable via the `ProTermsURL` / `ProPrivacyURL` Info.plist keys —
required for the auto-renewable plan, guideline 3.1.2).

## Tests

- `SOSMacTests/ProAccessTests.swift` — free gated, lifetime unlock, yearly
  active unlock, yearly expired re-gates, restore-without-purchase, plans
  from provider (fake provider; runs in both builds).
- `SOSMacTests/LicenseProviderTests.swift` — DMG mock unlock flow; Paddle
  stub fail-closed with empty config; configurable display prices.
- `SOSMacMASTests/StoreKitProTests.swift` — real `StoreKitProProvider`
  against the local `.storekit`: products load with the exact ids, kinds,
  prices; free user gets the paywall; a session purchase is visible to
  StoreKit. **Documented limitation:** in the app-host test environment
  (Xcode 26.2 / macOS 27 SDK), `session.buyProduct` transactions appear in
  `Transaction.all` and `Transaction.updates` but not
  `Transaction.currentEntitlements`, so the full purchase → entitlement path
  cannot be end-to-end tested there; it is covered by the fake-provider
  tests above. These tests are not in CI (SKTestSession in CI runners is
  unproven) — run locally with the `SOSMacMAS` scheme.

## Phương's manual steps

**App Store Connect:** create the subscription group "SOS Mac Pro" and both
products ($29.99 / $19.99), localizations, review screenshots for the IAPs,
sign the Paid Applications agreement, fill tax + banking. Privacy nutrition
label unchanged (no tracking, no collection — purchases are Apple's).

**Paddle (DMG):** account, product, price, activation limit 3, then put the
vendor id / product id / API key into a local xcconfig that feeds the
Info.plist keys — never into the repo.
