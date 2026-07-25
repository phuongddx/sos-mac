import SwiftUI

/// Matches the mockup's `.health-ring-wrap` — 176pt dial, 12pt stroke, a
/// gradient stroke (success → accent-2) with a glow, centered score + label.
struct HealthDialView: View {
    let score: Int // 0...100
    var label: String = "Health"

    private var progress: Double { Double(min(max(score, 0), 100)) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.border, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Theme.success, Theme.accent2], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent2.opacity(0.5), radius: 6)
            VStack(spacing: 5) {
                Text("\(score)")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(Theme.foreground)
                    .monospacedDigit()
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 176, height: 176)
    }
}
