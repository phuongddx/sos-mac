import SwiftUI
import CleanCore

/// The Junk review frame's detail column (spec §5.3): Rule, Location, Size, Safety and
/// the severity explanation, built from `ReviewDetailView`'s row API. **Ignore** (OD-8)
/// stays a plain button here — the prototype dropped the feature, but the app's ignore
/// list is real (SwiftData), so removing it would lose a shipped capability.
struct JunkReviewDetail: View {
    let item: ScanItem
    let onIgnore: () -> Void

    var body: some View {
        ReviewDetailView(title: (item.path as NSString).lastPathComponent) {
            if let rule = item.sourceLabel {
                ReviewDetailView.KeyRow(label: "Rule", value: rule)
            }
            ReviewDetailView.PathRow(label: "Location", value: item.path)
            ReviewDetailView.KeyRow(label: "Size", value: ByteFormatter.string(fromByteCount: item.size))
            ReviewDetailView.FreeRow {
                safetyRow
            }
            ReviewDetailView.Explanation(leadIn: explanationLeadIn, text: explanationText)
            ReviewDetailView.FreeRow {
                ignoreButton
            }
        }
    }

    private var safetyRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            Text("SAFETY")
                .font(Theme.Font.subheadline.weight(.semibold))
                .tracking(Self.labelTracking)
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: Theme.Spacing.s2) {
                BadgeView(text: severityText, style: severityStyle)
                if item.requiresPrivilegedHelper {
                    BadgeView(text: "Needs approval", style: .neutral, systemImage: "key")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// OD-8: kept as a plain button in the detail panel. The tooltip is the whole
    /// explanation — no extra copy on the panel.
    private var ignoreButton: some View {
        Button("Ignore", action: onIgnore)
            .buttonStyle(.sosPlain)
            .help("Stop showing this file in Junk & Cache scans.")
            .accessibilityIdentifier("junk-ignore")
    }

    private var severityText: String {
        switch item.severity {
        case .safe: "Safe"
        case .caution: "Caution"
        case .risky: "Risky"
        }
    }

    private var severityStyle: BadgeStyle {
        switch item.severity {
        case .safe: .safe
        case .caution: .caution
        case .risky: .risky
        }
    }

    private var explanationLeadIn: String {
        item.severity == .safe ? "Safe:" : "Caution:"
    }

    private var explanationText: String {
        if item.severity == .safe {
            return "a cache the app rebuilds on its own. It goes to the Trash, so you can put it back."
        }
        return "the app that owns this file may rebuild it or lose a setting. Not selected for you; select it only if you know the app."
    }

    private static let labelTracking: CGFloat = 0.48
}
