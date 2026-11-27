import SwiftUI
import CleanCore

/// The plain card surface the Performance screen composes from (prototype `.mcard` and
/// `.rows-card`): `card` fill, hairline border, `Radius.lg`. Screen-local styling helper —
/// a shared card component would be outside this PR's write set.
extension View {
    func performanceCard() -> some View {
        self
            .padding(Theme.Spacing.s5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Color.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
    }
}

/// The metric grid (spec §5.9), on the prototype's three-column layout: CPU (1) + Memory
/// (2), Thermal state (1) + Load average (2), the swap / architecture / uptime table (3).
///
/// `showsUnavailable` renders every value as "—" — what the unavailable banner promises —
/// on every card, the swap/architecture/uptime table included (review fix: the table was
/// the one card that ignored it). Otherwise a read the engine didn't return shows "—" for
/// that value only; the view never substitutes a guess. The thermal state is shown exactly
/// once (C7): a dot and the state's own word, captioned "As reported by macOS".
struct PerformanceMetricGrid: View {
    let sample: PerformanceViewModel.Sample?
    var showsUnavailable = false

    private static let dash = "—"

    var body: some View {
        Grid(horizontalSpacing: Theme.Spacing.s4, verticalSpacing: Theme.Spacing.s4) {
            GridRow {
                cpuCard
                memoryCard.gridCellColumns(2)
            }
            GridRow {
                thermalCard
                loadCard.gridCellColumns(2)
            }
            GridRow {
                tableCard.gridCellColumns(3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-metric-grid")
    }

    // MARK: - Shared pieces

    private func key(_ label: String, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.s2) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.textSecondary)
                .accessibilityHidden(true)
            Text(label)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Color.textSecondary)
    }

    private var dashValue: some View {
        Text(Self.dash)
            .font(Theme.Font.numeralL)
            .foregroundStyle(Theme.Color.textTertiary)
    }

    // MARK: - CPU

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            key("CPU", symbol: "cpu")
            if !showsUnavailable, let cpu = sample?.cpuUsagePercent {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(cpu.rounded()))")
                        .font(Theme.Font.numeralL)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("%")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
                ProgressBarView(progress: cpu / 100,
                                style: AnyShapeStyle(Theme.Gradient.soft))
            } else {
                dashValue
                ProgressBarView(progress: 0,
                                style: AnyShapeStyle(Theme.Gradient.soft))
            }
            caption("Updates while this screen is open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cpuAccessibilityLabel)
    }

    private var cpuAccessibilityLabel: String {
        guard !showsUnavailable, let cpu = sample?.cpuUsagePercent else {
            return "CPU, no reading"
        }
        return "CPU \(Int(cpu.rounded())) percent"
    }

    // MARK: - Memory

    /// One legend/bar entry. Segment fills per spec §5.9: `primaryDeep`, `primary`,
    /// `primaryBright`, `primaryBright` at 40 %, and Free with no fill and a
    /// `hairlineStrong` outline (the prototype hardcodes Palette A purples; this is the
    /// Palette C mapping).
    struct Segment: Identifiable {
        let label: String
        /// Real bytes formatted for the legend; `nil` renders the unavailable "—".
        let bytesText: String?
        let fraction: Double
        let fill: Color?
        let isFree: Bool

        var id: String { label }
    }

    private var segments: [Segment] {
        let labels = ["Wired", "Active", "Compressed", "Inactive", "Free"]
        let fills: [Color?] = [Theme.Color.primaryDeep, Theme.Color.primary, Theme.Color.primaryBright,
                               Theme.Color.primaryBright.opacity(0.4), nil]
        guard !showsUnavailable, let memory = sample?.memory else {
            return zip(labels, fills).map { label, fill in
                Segment(label: label, bytesText: nil, fraction: 0, fill: fill, isFree: label == "Free")
            }
        }
        let bytes = memory.values
        let fractions = memory.normalizedFractions
        return labels.enumerated().map { index, label in
            Segment(label: label,
                    bytesText: ByteFormatter.string(fromByteCount: Int64(bytes[index])),
                    fraction: fractions[index],
                    fill: fills[index],
                    isFree: label == "Free")
        }
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            key("Memory", symbol: "memorychip")
            memoryValue
            MemorySegmentBar(segments: segments)
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(memoryAccessibilityLabel)
    }

    /// "11.24 GB in use of 16 GB" — in use per OD-11 (`inUseBytes`: wired + active +
    /// compressed), never the legacy `total − free` reading.
    @ViewBuilder
    private var memoryValue: some View {
        if !showsUnavailable, let memory = sample?.memory, memory.total > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ByteFormatter.string(fromByteCount: Int64(memory.inUseBytes)))
                    .font(Theme.Font.numeralL)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("in use")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("of \(ByteFormatter.string(fromByteCount: Int64(memory.total)))")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            dashValue
        }
    }

    private var legend: some View {
        // Whole-item wrapping like the prototype's flex legend — a wide enough minimum
        // keeps "Compressed 2,79 GB" on one line instead of breaking mid-word.
        let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.s2, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s2) {
            ForEach(segments) { segment in
                HStack(spacing: Theme.Spacing.s2) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(segment.fill ?? .clear)
                        .overlay {
                            if segment.isFree {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(Theme.Derived.hairlineStrong, lineWidth: 1)
                            }
                        }
                        .frame(width: 9, height: 9)
                    Text(segment.label)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text(segment.bytesText ?? Self.dash)
                        .font(Theme.Font.callout.monospacedDigit())
                        .foregroundStyle(segment.bytesText == nil
                                         ? Theme.Color.textTertiary
                                         : Theme.Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var memoryAccessibilityLabel: String {
        guard !showsUnavailable, let memory = sample?.memory, memory.total > 0 else {
            return "Memory, no reading"
        }
        let inUse = ByteFormatter.string(fromByteCount: Int64(memory.inUseBytes))
        let total = ByteFormatter.string(fromByteCount: Int64(memory.total))
        return "Memory, \(inUse) in use of \(total)"
    }

    // MARK: - Thermal state (shown once — C7)

    private var thermalCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            key("Thermal state", symbol: "thermometer.medium")
            if !showsUnavailable {
                HStack(spacing: Theme.Spacing.s2) {
                    Circle()
                        .fill(thermalDotColor)
                        .frame(width: 9, height: 9)
                    Text(thermalWord)
                        .font(Theme.Font.title2)
                        .foregroundStyle(Theme.Color.textPrimary)
                }
                .accessibilityElement(children: .combine)
            } else {
                dashValue
            }
            caption("As reported by macOS")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thermal state \(showsUnavailable ? "no reading" : thermalWord)")
    }

    private var thermalWord: String {
        (sample?.thermal ?? .nominal).rawValue.capitalized
    }

    /// The dot is a status colour, the word always names the state — colour is never the
    /// only signal.
    private var thermalDotColor: Color {
        switch sample?.thermal ?? .nominal {
        case .nominal: Theme.Color.success
        case .fair: Theme.Color.warning
        case .serious, .critical: Theme.Color.danger
        }
    }

    // MARK: - Load average

    private struct LoadEntry: Identifiable {
        let label: String
        let value: String?
        var id: String { label }
    }

    private var loadEntries: [LoadEntry] {
        [("1 min", sample?.load?.oneMinute), ("5 min", sample?.load?.fiveMinute), ("15 min", sample?.load?.fifteenMinute)]
            .map { label, value in
                LoadEntry(label: label, value: value.map { String(format: "%.2f", $0) })
            }
    }

    private var loadCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            key("Load average", symbol: "gauge")
            HStack(spacing: Theme.Spacing.s8) {
                ForEach(loadEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        if let value = entry.value, !showsUnavailable {
                            Text(value)
                                .font(Theme.Font.numeralL)
                                .foregroundStyle(Theme.Color.textPrimary)
                        } else {
                            Text(Self.dash)
                                .font(Theme.Font.numeralL)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        Text(entry.label)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(loadAccessibilityLabel)
    }

    private var loadAccessibilityLabel: String {
        guard !showsUnavailable, let load = sample?.load else { return "Load average, no reading" }
        return "Load average, 1 minute \(String(format: "%.2f", load.oneMinute)), 5 minutes \(String(format: "%.2f", load.fiveMinute)), 15 minutes \(String(format: "%.2f", load.fifteenMinute))"
    }

    // MARK: - Swap / architecture / uptime table

    private struct TableRow: Identifiable {
        let label: String
        let value: String?
        var id: String { label }
    }

    /// The table's three values for one sample — the testable core of the unavailable
    /// gating (review fix): `showsUnavailable` dashes every row, exactly like the other
    /// cards, and an engine read that never landed dashes just that row. Architecture
    /// fails closed: a `nil` silicon read renders "—", never a guessed chip family.
    static func systemTableValues(sample: PerformanceViewModel.Sample?,
                                  showsUnavailable: Bool)
        -> (swapUsed: String?, architecture: String?, runningSince: String?) {
        guard !showsUnavailable, let sample else { return (nil, nil, nil) }
        return (
            swapUsed: sample.swap.map {
                "\(ByteFormatter.string(fromByteCount: Int64($0.used))) of \(ByteFormatter.string(fromByteCount: Int64($0.total)))"
            },
            architecture: sample.isAppleSilicon.map { $0 ? "Apple Silicon" : "Intel" },
            runningSince: sample.bootTime.map { $0.formatted(date: .abbreviated, time: .shortened) }
        )
    }

    private var tableRows: [TableRow] {
        let values = Self.systemTableValues(sample: sample, showsUnavailable: showsUnavailable)
        return [TableRow(label: "Swap used", value: values.swapUsed),
                TableRow(label: "Architecture", value: values.architecture),
                TableRow(label: "Running since", value: values.runningSince)]
    }

    private var tableCard: some View {
        let rows = tableRows
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.label)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text(row.value ?? Self.dash)
                        .font(Theme.Font.callout.monospacedDigit())
                        .foregroundStyle(row.value == nil
                                         ? Theme.Color.textTertiary
                                         : Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, Theme.Spacing.s3)
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-system-table")
    }
}

/// The segmented memory bar (spec §5.9): five segments whose widths are the view model's
/// normalised fractions (they sum to 1 even though the raw bytes don't sum to `total` —
/// the plan's stated risk), with Free as an outlined, unfilled segment. When no segment has
/// a width (unavailable), the hairline track stands alone.
private struct MemorySegmentBar: View {
    let segments: [PerformanceMetricGrid.Segment]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Group {
                        if segment.isFree {
                            Rectangle()
                                .fill(.clear)
                                .overlay {
                                    Rectangle()
                                        .strokeBorder(Theme.Derived.hairlineStrong, lineWidth: 1)
                                }
                        } else {
                            Rectangle()
                                .fill(segment.fill ?? .clear)
                        }
                    }
                    .frame(width: width * segment.fraction)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: 10, alignment: .leading)
            .background(Theme.Derived.hairlineStrong.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
