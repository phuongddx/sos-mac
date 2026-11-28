import SwiftUI

/// The Pro paywall sheet — one per app, presented from `RootView` whenever a
/// destructive action is gated (`ProAccess.require(for:)`).
///
/// Free tier (always): every scan and every results screen. Pro: the actions
/// that actually delete. Prices come from `ProAccess.plans` (StoreKit
/// `displayPrice` in MAS, license config in DMG) — never hardcoded strings.
/// Includes Restore Purchases and Terms/Privacy links (guideline 3.1.2 for
/// the auto-renewable plan), both configurable through Info.plist keys.
struct PaywallView: View {
    let feature: ProFeature
    @Environment(ProAccess.self) private var pro

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
            header
            Divider().overlay(Theme.Derived.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
                    freeTierRow
                    planCards
                    if let error = pro.purchaseError {
                        BannerView(kind: .err, title: "Purchase failed", text: error)
                    }
                    if let message = pro.restoreMessage {
                        BannerView(kind: .info, title: "Restore", text: message)
                    }
                    restoreAndLegal
                }
                .padding(.horizontal, Theme.Spacing.s6)
                .padding(.vertical, Theme.Spacing.s4)
            }
        }
        .frame(width: 460, height: 520)
        .background(Theme.Color.bgBase)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s3) {
            ModuleTileView(hue: Theme.Hue.smartcare,
                           ink: Theme.Hue.Ink.smartcare,
                           symbol: "lock.badge.checkmark",
                           size: .row)
            VStack(alignment: .leading, spacing: 2) {
                Text("SOS Mac Pro")
                    .font(Theme.Font.title3)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("\(feature.rawValue) can clean, delete and quarantine once you unlock Pro. Scanning and reviewing everything stays free.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.s2)
        }
        .padding(EdgeInsets(top: Theme.Spacing.s5, leading: Theme.Spacing.s6,
                            bottom: 0, trailing: Theme.Spacing.s6))
    }

    private var freeTierRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s3) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.success)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free right now")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Every scan, every result, every review list — nothing is hidden behind the paywall.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(Theme.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var planCards: some View {
        VStack(spacing: Theme.Spacing.s3) {
            ForEach(pro.plans) { plan in
                planCard(plan)
            }
            if pro.plans.isEmpty {
                // Offline before StoreKit loads: honest, not a spinner with
                // invented prices.
                StatusStateView(
                    kind: .neutral,
                    symbol: "cart",
                    title: "Plans are loading",
                    text: "Prices appear as soon as the App Store responds.")
                    .frame(height: 120)
            }
        }
    }

    private func planCard(_ plan: ProPlan) -> some View {
        let isRecommended = plan.kind == .lifetime
        return HStack(alignment: .center, spacing: Theme.Spacing.s4) {
            ModuleTileView(hue: Theme.Hue.updater,
                           ink: Theme.Hue.Ink.updater,
                           symbol: plan.kind == .lifetime ? "infinity" : "calendar",
                           size: .row)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.s2) {
                    Text(plan.kind == .lifetime ? "Pro Lifetime" : "Pro Yearly")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    if isRecommended {
                        Text("Best value")
                            .font(Theme.Font.eyebrow)
                            .foregroundStyle(Theme.Color.onPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Color.primary))
                    }
                }
                Text(plan.kind == .lifetime
                     ? "One purchase. Yours forever on this Mac App Store account."
                     : "Billed yearly, renews automatically, cancel anytime.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.s3)
            VStack(alignment: .trailing, spacing: Theme.Spacing.s2) {
                Text(plan.displayPrice)
                    .font(Theme.Font.title2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.textPrimary)
                Button {
                    Task { await pro.purchase(plan) }
                } label: {
                    if pro.isPurchasing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock")
                    }
                }
                .sosButton(.default)
                .disabled(pro.isPurchasing)
                .accessibilityIdentifier("paywall-purchase-\(plan.kind == .lifetime ? "lifetime" : "yearly")")
            }
        }
        .padding(Theme.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isRecommended ? Theme.Color.primary.opacity(0.5) : Theme.Derived.hairline,
                          lineWidth: isRecommended ? 2 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall-plan-\(plan.kind == .lifetime ? "lifetime" : "yearly")")
    }

    private var restoreAndLegal: some View {
        VStack(spacing: Theme.Spacing.s3) {
            Button("Restore Purchases") {
                Task { await pro.restore() }
            }
            .sosButton(.default)
            .frame(maxWidth: .infinity)
            .disabled(pro.isPurchasing)
            .accessibilityIdentifier("paywall-restore")

            HStack(spacing: Theme.Spacing.s5) {
                Link("Terms of Use", destination: PaywallLinks.termsURL)
                Link("Privacy Policy", destination: PaywallLinks.privacyURL)
            }
            .font(Theme.Font.callout)
            .buttonStyle(.link)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Paywall legal links — placeholder URLs that a build can override through
/// Info.plist (`ProTermsURL`, `ProPrivacyURL`) without a code change.
enum PaywallLinks {
    static var termsURL: URL {
        Self.url(forKey: "ProTermsURL", placeholder: "https://nextlabs.example/sos-mac/terms")
    }
    static var privacyURL: URL {
        Self.url(forKey: "ProPrivacyURL", placeholder: "https://nextlabs.example/sos-mac/privacy")
    }

    private static func url(forKey key: String, placeholder: String) -> URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           let configured = URL(string: raw), configured.scheme?.hasPrefix("http") == true {
            return configured
        }
        return URL(string: placeholder)!
    }
}
