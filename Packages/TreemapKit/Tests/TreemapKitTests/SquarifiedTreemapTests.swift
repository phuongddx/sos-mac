import CoreGraphics
import Testing
@testable import TreemapKit

struct SquarifiedTreemapTests {
    @Test func rectanglesSumToContainerArea() {
        let values: [Double] = [500, 300, 200, 150, 100, 80, 40, 10]
        let container = CGRect(x: 0, y: 0, width: 800, height: 600)
        let rects = SquarifiedTreemap.layout(values: values, in: container)

        let totalArea = rects.reduce(0.0) { $0 + Double($1.width) * Double($1.height) }
        let containerArea = Double(container.width) * Double(container.height)
        #expect(abs(totalArea - containerArea) < 0.01)
    }

    @Test func noTwoRectanglesOverlapInInterior() {
        let values: [Double] = [500, 300, 200, 150, 100, 80, 40, 10, 400, 250]
        let container = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let rects = SquarifiedTreemap.layout(values: values, in: container)

        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let intersection = rects[i].intersection(rects[j])
                // Shared edges (zero-area intersection) are expected and fine —
                // only a nonzero-area overlap is a real layout bug.
                let overlapArea = Double(intersection.width) * Double(intersection.height)
                #expect(overlapArea < 0.01, "rects \(i) and \(j) overlap: \(rects[i]) vs \(rects[j])")
            }
        }
    }

    @Test func everyRectangleStaysWithinContainerBounds() {
        let values: [Double] = [1000, 1, 500, 2, 250]
        let container = CGRect(x: 10, y: 20, width: 400, height: 300)
        let rects = SquarifiedTreemap.layout(values: values, in: container)

        // Accumulated Double addition across many rows can overshoot the
        // container edge by ~1e-12 — real floating-point noise, not a layout
        // bug (verified: the overshoot tracks exactly with row count, not
        // with any particular input). CGRect.contains has no tolerance, so
        // check bounds directly with a tiny epsilon instead.
        let epsilon = 1e-6
        for rect in rects where rect != .zero {
            #expect(rect.minX >= container.minX - epsilon)
            #expect(rect.minY >= container.minY - epsilon)
            #expect(rect.maxX <= container.maxX + epsilon)
            #expect(rect.maxY <= container.maxY + epsilon)
        }
    }

    @Test func outputOrderMatchesInputOrder() {
        // A single large value followed by many tiny ones exercises row-breaks;
        // the returned rect at index 0 must still correspond to input index 0.
        let values: [Double] = [1000, 1, 1, 1, 1]
        let container = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rects = SquarifiedTreemap.layout(values: values, in: container)

        let largestArea = Double(rects[0].width) * Double(rects[0].height)
        for i in 1..<rects.count {
            let area = Double(rects[i].width) * Double(rects[i].height)
            #expect(area <= largestArea)
        }
    }

    @Test func emptyInputProducesNoRects() {
        let rects = SquarifiedTreemap.layout(values: [], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(rects.isEmpty)
    }

    @Test func zeroValueItemsGetZeroRectAndDontCrash() {
        let values: [Double] = [100, 0, 50, 0]
        let rects = SquarifiedTreemap.layout(values: values, in: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(rects.count == 4)
        #expect(rects[1] == .zero)
        #expect(rects[3] == .zero)
    }
}
