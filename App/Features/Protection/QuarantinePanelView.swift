import SwiftUI

/// The quarantine list (spec §5.10, prototype `qpanel`): one row per quarantined file with
/// its original folder, the date it moved and a **Restore** button. Two forms of one panel:
///
/// - `compact` — under `start` and `done`: the newest three, plus "Show all" when there are
///   more.
/// - `full` — the Quarantine sub-screen: every record in a scroll view (N8 — the list grows
///   without bound, so it must never be laid out as plain stacked rows).
///
/// Everything shown is real: names and folders come from the persisted `QuarantineRecord`s,
/// and a failed restore draws the engine's reason as a banner above the list (N4).
struct QuarantinePanelView: View {
    enum Form: Equatable, Sendable {
        case compact
        case full
    }

    static let compactRowLimit = 3
    static let compactMaxWidth: CGFloat = 520
    static let rowHorizontalPadding: CGFloat = 14

    let records: [QuarantineRecord]
    var form: Form = .compact
    var hue: Color = Theme.Hue.protection
    /// The folder a file came from, as the user reads it (`~/Downloads`).
    let displayFolder: (String) -> String
    var actionError: ProtectionViewModel.ActionError?
    let onRestore: (QuarantineRecord) -> Void
    var onShowAll: (() -> Void)?
    var onDismissError: (() -> Void)?

    private var visibleRecords: [QuarantineRecord] {
        form == .compact ? Array(records.prefix(Self.compactRowLimit)) : records
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
            if let actionError {
                BannerView(kind: .err, title: actionError.title, text: actionError.text)
                    .overlay(alignment: .topTrailing) {
                        if let onDismissError {
                            Button("Dismiss", action: onDismissError)
                                .buttonStyle(.sosPlain)
                                .padding(Theme.Spacing.s2)
                                .accessibilityIdentifier("quarantine-dismiss-error")
                        }
                    }
            }
            panel
        }
        .frame(maxWidth: form == .compact ? Self.compactMaxWidth : .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quarantine-panel")
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
            if records.isEmpty {
                Text("Nothing is in quarantine.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(Theme.Spacing.s4)
            } else {
                rows
            }
            if form == .compact, records.count > Self.compactRowLimit, let onShowAll {
                Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
                HStack {
                    Button("Show all \(records.count)", action: onShowAll)
                        .buttonStyle(.sosPlain)
                        .accessibilityIdentifier("quarantine-show-all")
                    Spacer()
                }
                .padding(.horizontal, Self.rowHorizontalPadding)
                .padding(.vertical, Theme.Spacing.s2)
            }
        }
        .background(Theme.Color.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .elevation(.raised)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s2) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hue)
                .accessibilityHidden(true)
            Text("Quarantine")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer(minLength: Theme.Spacing.s2)
            Text("\(records.count) \(records.count == 1 ? "item" : "items") · restorable")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Theme.Spacing.s3 - 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rows: some View {
        let list = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleRecords.enumerated()), id: \.element.quarantinePath) { index, record in
                row(record)
                if index < visibleRecords.count - 1 {
                    Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
                }
            }
        }
        if form == .full {
            ScrollView { list }
                .accessibilityIdentifier("quarantine-list")
        } else {
            list
        }
    }

    private func row(_ record: QuarantineRecord) -> some View {
        let name = (record.originalPath as NSString).lastPathComponent
        let folder = displayFolder((record.originalPath as NSString).deletingLastPathComponent)
        return HStack(spacing: Theme.Spacing.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("From \(folder)")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.quarantinedAt.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Button("Restore") { onRestore(record) }
                .sosButton(.default)
                .accessibilityLabel("Restore \(name)")
                .accessibilityIdentifier("quarantine-restore-\(name)")
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Theme.Spacing.s2 + 2)
        .accessibilityElement(children: .contain)
    }
}
