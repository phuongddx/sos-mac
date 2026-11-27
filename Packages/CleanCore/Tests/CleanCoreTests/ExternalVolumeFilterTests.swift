import Testing
@testable import CleanCore

/// D8 (review F): which mounted volumes Space Lens offers as scan sources — local AND
/// (removable OR not internal), with any missing flag excluding the volume (fail closed).
/// Pure flag-set tests: no hardware is mounted, so the non-removable-external-SSD case is
/// covered without one being attached.
@Suite("ExternalVolumeFilter")
struct ExternalVolumeFilterTests {
    @Test("the rule table", arguments: [
        (ExternalVolumeFilter.Flags(isLocal: true, isRemovable: true, isInternal: true), true),
        (ExternalVolumeFilter.Flags(isLocal: true, isRemovable: true, isInternal: false), true),
        // The F finding: a non-removable external SSD (removable=false, internal=false).
        (ExternalVolumeFilter.Flags(isLocal: true, isRemovable: false, isInternal: false), true),
        // The boot volume: internal and not removable.
        (ExternalVolumeFilter.Flags(isLocal: true, isRemovable: false, isInternal: true), false),
        // A network volume is not local, whatever else it reports.
        (ExternalVolumeFilter.Flags(isLocal: false, isRemovable: true, isInternal: false), false),
        (ExternalVolumeFilter.Flags(isLocal: false, isRemovable: false, isInternal: false), false),
    ])
    func ruleTable(flags: ExternalVolumeFilter.Flags, expected: Bool) {
        #expect(ExternalVolumeFilter.includes(flags) == expected)
    }

    @Test("a missing flag excludes the volume (fail closed)", arguments: [
        ExternalVolumeFilter.Flags(isLocal: nil, isRemovable: true, isInternal: false),
        ExternalVolumeFilter.Flags(isLocal: true, isRemovable: nil, isInternal: false),
        ExternalVolumeFilter.Flags(isLocal: true, isRemovable: false, isInternal: nil),
        ExternalVolumeFilter.Flags(isLocal: nil, isRemovable: nil, isInternal: nil),
    ])
    func missingFlagsExclude(flags: ExternalVolumeFilter.Flags) {
        #expect(!ExternalVolumeFilter.includes(flags))
    }
}
