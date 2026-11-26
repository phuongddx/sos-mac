import Foundation
import Testing
@testable import SOSMac

/// PR 2 shell: sidebar groups, toolbar models and the storage footer's data.
@Suite("Shell")
struct ShellTests {
    @Test func sidebarGroupsMatchSpecOrder() {
        let groups = SidebarGroup.all
        #expect(groups.map(\.label) == [nil, "Clean", "Manage", "Speed", "Protect"])
        #expect(groups.map(\.destinations) == [
            [.dashboard, .smartCare],
            [.junkCleaner, .duplicateFinder, .spaceLens, .cloudCleanup],
            [.uninstaller, .updater],
            [.performance],
            [.protection],
        ])
    }

    @Test func everyDestinationAppearsExactlyOnceInTheSidebar() {
        let listed = SidebarGroup.all.flatMap(\.destinations)
        #expect(listed.count == SidebarDestination.allCases.count)
        #expect(Set(listed) == Set(SidebarDestination.allCases))
    }

    @Test func junkRowIsRenamed() {
        #expect(SidebarDestination.junkCleaner.rawValue == "Junk & Cache")
        #expect(SidebarDestination(uiTestKey: "junk") == .junkCleaner)
    }

    @Test(arguments: SidebarDestination.allCases)
    func toolbarTitleIsTheScreenName(_ destination: SidebarDestination) {
        let model = ModuleToolbarModel.shell(for: destination)
        #expect(model.title == destination.rawValue)
        // No invented subtitles, back buttons or tools before each screen's own PR.
        #expect(model.subtitle == nil)
        #expect(model.back == nil)
        #expect(model.tools == nil)
    }

    @Test func storageNumbersAreConsistent() throws {
        let info = try #require(VolumeStorageInfo.current())
        #expect(info.totalBytes > 0)
        #expect(info.usedBytes + info.freeBytes == info.totalBytes)
        #expect((0...1).contains(info.usedFraction))
    }

    @Test func volumeNameIsNilForAPathWithoutVolume() {
        // A URL that does not exist has no resource values: the name is omitted, not guessed.
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(VolumeStorageInfo.volumeName(of: missing) == nil)
    }

    @Test func bootVolumeNameIsReadWhenPresent() {
        // Whatever the system reports; when present it is never blank.
        if let name = VolumeStorageInfo.volumeName(of: URL(fileURLWithPath: "/")) {
            #expect(!name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
