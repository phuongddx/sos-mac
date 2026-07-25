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
}
