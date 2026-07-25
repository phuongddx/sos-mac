import SwiftUI

/// Matches the mockup's `.progress-track` / `.progress-fill`.
struct ProgressBarView: View {
    var progress: Double // 0...1
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
