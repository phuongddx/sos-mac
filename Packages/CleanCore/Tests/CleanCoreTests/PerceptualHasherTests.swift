import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import CleanCore

struct PerceptualHasherTests {
    @Test func reEncodedImageAtDifferentQualityHasSmallHammingDistance() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let image = Self.makeTestImage(variant: .checkerboard)
        let highQualityPath = root.appendingPathComponent("high.jpg").path
        let lowQualityPath = root.appendingPathComponent("low.jpg").path
        try Self.writeJPEG(image, toPath: highQualityPath, quality: 1.0)
        try Self.writeJPEG(image, toPath: lowQualityPath, quality: 0.2)

        let hashHigh = try #require(PerceptualHasher.dHash(imageAtPath: highQualityPath))
        let hashLow = try #require(PerceptualHasher.dHash(imageAtPath: lowQualityPath))

        let distance = PerceptualHasher.hammingDistance(hashHigh, hashLow)
        #expect(distance <= 5, "expected re-encoded copies to be near-identical, got distance \(distance)")
    }

    @Test func genuinelyDifferentImagesHaveLargeHammingDistance() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let imageA = Self.makeTestImage(variant: .checkerboard)
        let imageB = Self.makeTestImage(variant: .diagonalGradient)
        let pathA = root.appendingPathComponent("a.jpg").path
        let pathB = root.appendingPathComponent("b.jpg").path
        try Self.writeJPEG(imageA, toPath: pathA, quality: 1.0)
        try Self.writeJPEG(imageB, toPath: pathB, quality: 1.0)

        let hashA = try #require(PerceptualHasher.dHash(imageAtPath: pathA))
        let hashB = try #require(PerceptualHasher.dHash(imageAtPath: pathB))

        let distance = PerceptualHasher.hammingDistance(hashA, hashB)
        #expect(distance > 10, "expected genuinely different images to differ substantially, got distance \(distance)")
    }

    @Test func clusterUsesTrueSingleLinkageNotJustAnchorComparison() {
        // Constructed so: distance(a,b) = 5, distance(b,c) = 5, distance(a,c) = 6.
        // With threshold 5, a naive "compare candidates only against the
        // anchor" approach groups [a,b] (a's anchor scan matches b, then c
        // fails a's own a-c=6 check) and drops c entirely as a singleton.
        // True single-linkage must instead grow the group via b: c matches
        // b (distance 5), so all three belong together.
        let a: UInt64 = 0
        let b: UInt64 = 0b0001_1111 // 31 -> popcount(a^b) = 5
        let c: UInt64 = 0b1111_1100 // 252 -> popcount(a^c) = 6, popcount(b^c) = 5

        #expect(PerceptualHasher.hammingDistance(a, b) == 5)
        #expect(PerceptualHasher.hammingDistance(b, c) == 5)
        #expect(PerceptualHasher.hammingDistance(a, c) == 6)

        let clusters = PerceptualHasher.cluster(hashes: [a, b, c], threshold: 5)
        #expect(clusters.count == 1)
        #expect(Set(clusters[0]) == Set([0, 1, 2]))
    }

    @Test func clusterKeepsUnrelatedHashesSeparate() {
        let a: UInt64 = 0
        let b: UInt64 = 0xFFFF_FFFF_FFFF_FFFF // maximally different from a
        let clusters = PerceptualHasher.cluster(hashes: [a, b], threshold: 5)
        #expect(clusters.isEmpty)
    }

    @Test func unreadablePathReturnsNilRatherThanCrashing() {
        #expect(PerceptualHasher.dHash(imageAtPath: "/nonexistent/\(UUID().uuidString).jpg") == nil)
    }

    // MARK: - Fixture generation

    private enum ImageVariant { case checkerboard, diagonalGradient }

    private static func makeTestImage(variant: ImageVariant) -> CGImage {
        let size = 64
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        switch variant {
        case .checkerboard:
            let cell = 8
            for y in stride(from: 0, to: size, by: cell) {
                for x in stride(from: 0, to: size, by: cell) {
                    let isBlack = ((x / cell) + (y / cell)).isMultiple(of: 2)
                    context.setFillColor(isBlack ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                }
            }
        case .diagonalGradient:
            for y in 0..<size {
                for x in 0..<size {
                    let value = CGFloat(x + y) / CGFloat(2 * size)
                    context.setFillColor(CGColor(gray: value, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }

        return context.makeImage()!
    }

    private static func writeJPEG(_ image: CGImage, toPath path: String, quality: CGFloat) throws {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw TestFixtureError.cannotCreateDestination
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestFixtureError.cannotFinalize
        }
    }

    private enum TestFixtureError: Error {
        case cannotCreateDestination
        case cannotFinalize
    }
}
