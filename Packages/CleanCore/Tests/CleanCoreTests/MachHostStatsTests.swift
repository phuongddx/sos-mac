import Foundation
import Testing
@testable import CleanCore

struct MachHostStatsTests {
    @Test func cpuTicksAreNonNegativeAndTotalPositive() throws {
        let ticks = try #require(MachHostStats.cpuTicks())
        #expect(ticks.total > 0)
    }

    @Test func cpuUsagePercentBetweenTwoRealSamplesIsInValidRange() async throws {
        let first = try #require(MachHostStats.cpuTicks())
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s — enough for tick counts to advance
        let second = try #require(MachHostStats.cpuTicks())

        let percent = try #require(MachHostStats.cpuUsagePercent(from: first, to: second))
        #expect(percent >= 0)
        #expect(percent <= 100)
    }

    @Test func cpuUsagePercentReturnsNilWhenSamplesAreIdentical() {
        let ticks = CPUTicks(user: 10, system: 10, idle: 10, nice: 10)
        #expect(MachHostStats.cpuUsagePercent(from: ticks, to: ticks) == nil)
    }

    @Test func memoryInfoUsedNeverExceedsPhysicalTotal() throws {
        let info = try #require(MachHostStats.memoryInfo())
        #expect(info.usedBytes <= info.totalBytes)
        #expect(info.freeBytes <= info.totalBytes)
        #expect(info.totalBytes > 0)
    }

    @Test func memoryInfoInUseAndAvailableStayWithinTotalOnLiveSample() throws {
        let info = try #require(MachHostStats.memoryInfo())
        // UInt64 makes both figures structurally non-negative; a live machine
        // always has wired pages, so in-use is strictly positive.
        #expect(info.inUseBytes > 0)
        #expect(info.inUseBytes <= info.totalBytes)
        #expect(info.availableBytes <= info.totalBytes)
    }

    @Test func inUseAndAvailableMatchFormulasWhenSegmentsSumBelowTotal() {
        let info = MemoryInfo(
            freeBytes: 40, activeBytes: 30, inactiveBytes: 30,
            wiredBytes: 30, compressedBytes: 30, totalBytes: 100
        )
        #expect(info.inUseBytes == 90) // wired 30 + active 30 + compressed 30
        #expect(info.availableBytes == 70) // free 40 + inactive 30
    }

    @Test func inUseAndAvailableAreCappedAtTotalWhenSegmentsOvershoot() {
        // Segments can overshoot `totalBytes` because of compressor/kernel
        // accounting drift; the properties must clamp instead of reporting
        // more memory than the machine has.
        let info = MemoryInfo(
            freeBytes: 60, activeBytes: 60, inactiveBytes: 60,
            wiredBytes: 60, compressedBytes: 60, totalBytes: 100
        )
        #expect(info.inUseBytes == 100) // raw sum 180 → capped
        #expect(info.availableBytes == 100) // raw sum 120 → capped
    }

    @Test func inUsePlusAvailableIsNearTotalWithinCompressorAccountingSlack() throws {
        let info = try #require(MachHostStats.memoryInfo())
        // inUse + available only APPROXIMATES totalBytes, in either
        // direction, so this test deliberately does not assert
        // `sum >= totalBytes` (or `<=`): `compressor_page_count` counts pages
        // held by the compressor while `hw.memsize` also includes kernel and
        // firmware reservations that never appear in any vm_statistics64
        // bucket, so the five segments do not sum exactly to the physical
        // total. PR 12's UI normalises instead of drawing from the raw sum.
        let sum = info.inUseBytes + info.availableBytes
        let slack = info.totalBytes / 10 // observed drift is ~1–2%; 10% is a generous band
        #expect(sum + slack >= info.totalBytes)
        #expect(sum <= info.totalBytes + slack)
    }
}
