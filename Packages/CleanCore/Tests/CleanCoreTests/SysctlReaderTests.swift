import Foundation
import Testing
@testable import CleanCore

/// Integration-style tests against the actual test machine — there's no
/// meaningful way to mock `sysctl`, so these assert values land in sane
/// ranges rather than exact golden values.
struct SysctlReaderTests {
    @Test func physicalMemoryIsPositiveAndPlausible() throws {
        let bytes = try #require(SysctlReader.physicalMemoryBytes())
        #expect(bytes > 0)
        #expect(bytes < 10 * 1024 * 1024 * 1024 * 1024) // < 10 TB, sanity ceiling
    }

    @Test func cpuCoreCountIsPositive() throws {
        let count = try #require(SysctlReader.cpuCoreCount())
        #expect(count > 0)
        #expect(count < 1024)
    }

    @Test func swapUsageFieldsAreConsistent() {
        guard let swap = SysctlReader.swapUsage() else { return } // some machines report 0-size sysctl; not a failure
        #expect(swap.usedBytes <= swap.totalBytes)
        #expect(swap.freeBytes <= swap.totalBytes)
    }

    @Test func bootTimeIsInThePast() throws {
        let bootTime = try #require(SysctlReader.bootTime())
        #expect(bootTime < Date())
        #expect(bootTime > Date(timeIntervalSince1970: 0))
    }

    @Test func loadAveragesAreNonNegative() throws {
        let loads = try #require(SysctlReader.loadAverages())
        #expect(loads.oneMinute >= 0)
        #expect(loads.fiveMinute >= 0)
        #expect(loads.fifteenMinute >= 0)
    }

    @Test func isAppleSiliconMatchesArchitecture() {
        #if arch(arm64)
        #expect(SysctlReader.isAppleSilicon())
        #elseif arch(x86_64)
        #expect(!SysctlReader.isAppleSilicon())
        #endif
    }
}
