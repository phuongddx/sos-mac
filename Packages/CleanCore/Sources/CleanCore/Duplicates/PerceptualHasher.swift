import CoreGraphics
import ImageIO
import Foundation

/// dHash (difference hash): downsample to a small grayscale grid, then hash
/// the sign of adjacent-pixel differences. Two images that are the same
/// photo resized, re-encoded, or re-compressed hash to a small Hamming
/// distance even though their bytes (and SHA-256) don't match at all —
/// that's the entire point of a *separate* "similar images" mode from exact
/// duplicate detection.
public enum PerceptualHasher {
    private static let gridWidth = 9
    private static let gridHeight = 8

    public static func dHash(imageAtPath path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return dHash(cgImage: cgImage)
    }

    static func dHash(cgImage: CGImage) -> UInt64? {
        var pixels = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        guard let context = CGContext(
            data: &pixels,
            width: gridWidth,
            height: gridHeight,
            bitsPerComponent: 8,
            bytesPerRow: gridWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight))

        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0
        for row in 0..<gridHeight {
            for col in 0..<(gridWidth - 1) {
                let left = pixels[row * gridWidth + col]
                let right = pixels[row * gridWidth + col + 1]
                if left > right {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }
        return hash
    }

    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// True single-linkage clustering: a candidate joins a forming cluster if
    /// it's within `threshold` of ANY member already in that cluster, not
    /// just the first (anchor) one. Comparing only against the anchor would
    /// silently drop a real match in a chain like A~B~C — A close to B, B
    /// close to C, but A too far from C on its own: B gets claimed by A's
    /// anchor, and C, never compared against B (only against future
    /// anchors), ends up alone and filtered out. Returns clusters as index
    /// lists into `hashes`, each of size >= 2.
    public static func cluster(hashes: [UInt64], threshold: Int) -> [[Int]] {
        var assigned = Set<Int>()
        var clusters: [[Int]] = []

        for i in hashes.indices {
            guard !assigned.contains(i) else { continue }
            var members = [i]
            assigned.insert(i)

            var didGrow = true
            while didGrow {
                didGrow = false
                for j in hashes.indices where !assigned.contains(j) {
                    let matchesExistingMember = members.contains { memberIndex in
                        hammingDistance(hashes[memberIndex], hashes[j]) <= threshold
                    }
                    if matchesExistingMember {
                        members.append(j)
                        assigned.insert(j)
                        didGrow = true
                    }
                }
            }

            if members.count >= 2 {
                clusters.append(members)
            }
        }

        return clusters
    }
}
