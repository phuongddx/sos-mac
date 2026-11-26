import Testing
@testable import SOSMac

/// Proves the unit-test target links against the app (`@testable import SOSMac`).
/// Later PRs add view-model and token tests beside this file.
@Suite("SidebarDestination")
struct SidebarDestinationTests {
    @Test func hasTenDestinations() {
        #expect(SidebarDestination.allCases.count == 10)
    }

    @Test func identifiersAreUnique() {
        let ids = Set(SidebarDestination.allCases.map(\.id))
        #expect(ids.count == SidebarDestination.allCases.count)
    }
}
