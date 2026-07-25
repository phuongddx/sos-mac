import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing, van Wijk, 1999) — pure geometry,
/// no UI framework dependency, so it's testable with plain rectangles-in/
/// rectangles-out assertions. Input `values` are arbitrary positive weights
/// (e.g. byte sizes); output rects are in the same order as the input and
/// sum to `rect`'s area.
public enum SquarifiedTreemap {
    public static func layout(values: [Double], in rect: CGRect) -> [CGRect] {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        let totalValue = values.reduce(0, +)
        guard totalValue > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        let totalArea = Double(rect.width) * Double(rect.height)
        let areas = values.map { $0 / totalValue * totalArea }

        var result = [CGRect](repeating: .zero, count: values.count)
        // Squarify's greedy row-building is only correct on descending input;
        // zero/negative-value items are dropped rather than fed through the
        // worst-ratio math, which divides by the smallest area in a row.
        let sortedIndices = areas.indices
            .filter { areas[$0] > 0 }
            .sorted { areas[$0] > areas[$1] }

        squarify(areas: areas, remaining: sortedIndices, rect: rect, result: &result)
        return result
    }

    private static func squarify(areas: [Double], remaining: [Int], rect: CGRect, result: inout [CGRect]) {
        var remaining = remaining
        var currentRect = rect

        while !remaining.isEmpty {
            let width = shorterSide(currentRect)
            let rowIndices = bestRow(areas: areas, remaining: remaining, width: width)
            currentRect = layoutRow(areas: areas, rowIndices: rowIndices, rect: currentRect, result: &result)
            remaining.removeFirst(rowIndices.count)
        }
    }

    private static func shorterSide(_ rect: CGRect) -> Double {
        Double(min(rect.width, rect.height))
    }

    /// Worst (largest) aspect ratio any rectangle in the row would have if
    /// laid out at the given strip width — lower is "more square", which is
    /// the whole point of "squarified".
    private static func worst(areas: [Double], rowIndices: [Int], width: Double) -> Double {
        guard width > 0 else { return .infinity }
        let rowAreas = rowIndices.map { areas[$0] }
        let sum = rowAreas.reduce(0, +)
        guard sum > 0, let maxA = rowAreas.max(), let minA = rowAreas.min(), minA > 0 else {
            return .infinity
        }
        let s2 = sum * sum
        let w2 = width * width
        return max(w2 * maxA / s2, s2 / (w2 * minA))
    }

    /// Greedily grows a row while adding the next item keeps (or improves)
    /// the worst aspect ratio; stops the moment it would get worse.
    private static func bestRow(areas: [Double], remaining: [Int], width: Double) -> [Int] {
        var row: [Int] = []
        var bestWorst = Double.infinity

        for index in remaining {
            let candidate = row + [index]
            let candidateWorst = worst(areas: areas, rowIndices: candidate, width: width)
            if row.isEmpty || candidateWorst <= bestWorst {
                row = candidate
                bestWorst = candidateWorst
            } else {
                break
            }
        }

        return row
    }

    /// Lays out one row as a strip along the container's longer side, and
    /// returns the remaining rect the next row should be laid out into.
    private static func layoutRow(areas: [Double], rowIndices: [Int], rect: CGRect, result: inout [CGRect]) -> CGRect {
        let rowAreas = rowIndices.map { areas[$0] }
        let rowSum = rowAreas.reduce(0, +)
        let layoutHorizontally = rect.width >= rect.height

        if layoutHorizontally {
            let stripWidth = rowSum / Double(rect.height)
            var y = rect.minY
            for (index, area) in zip(rowIndices, rowAreas) {
                let height = area / stripWidth
                result[index] = CGRect(x: rect.minX, y: y, width: CGFloat(stripWidth), height: CGFloat(height))
                y += CGFloat(height)
            }
            return CGRect(
                x: rect.minX + CGFloat(stripWidth),
                y: rect.minY,
                width: max(0, rect.width - CGFloat(stripWidth)),
                height: rect.height
            )
        } else {
            let stripHeight = rowSum / Double(rect.width)
            var x = rect.minX
            for (index, area) in zip(rowIndices, rowAreas) {
                let width = area / stripHeight
                result[index] = CGRect(x: x, y: rect.minY, width: CGFloat(width), height: CGFloat(stripHeight))
                x += CGFloat(width)
            }
            return CGRect(
                x: rect.minX,
                y: rect.minY + CGFloat(stripHeight),
                width: rect.width,
                height: max(0, rect.height - CGFloat(stripHeight))
            )
        }
    }
}
