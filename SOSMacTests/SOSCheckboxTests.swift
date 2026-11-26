import Testing
@testable import SOSMac

/// State rules of the shared checkbox (spec §4.6): macOS toggle semantics and the
/// kept-item lock that no interaction may select.
@Suite("SOSCheckbox state")
struct SOSCheckboxTests {
    @Test("toggle follows macOS checkbox semantics")
    func toggledFollowsCheckboxSemantics() {
        #expect(SOSCheckbox.State.off.toggled() == .on)
        #expect(SOSCheckbox.State.mixed.toggled() == .on)
        #expect(SOSCheckbox.State.on.toggled() == .off)
    }

    @Test("kept rows never change state")
    func keptRowsNeverToggle() {
        #expect(SOSCheckbox.State.off.toggled(isKept: true) == .off)
        #expect(SOSCheckbox.State.on.toggled(isKept: true) == .on)
        #expect(SOSCheckbox.State.mixed.toggled(isKept: true) == .mixed)
        #expect(SOSCheckbox.State.off.toggled(isKept: false) == .on)
    }

    @Test("init(isSelected:) maps booleans")
    func initMapsBooleans() {
        #expect(SOSCheckbox.State(isSelected: true) == .on)
        #expect(SOSCheckbox.State(isSelected: false) == .off)
    }

    @Test("checked means on or mixed")
    func checkedMeansOnOrMixed() {
        #expect(!SOSCheckbox.State.off.isChecked)
        #expect(SOSCheckbox.State.on.isChecked)
        #expect(SOSCheckbox.State.mixed.isChecked)
    }
}
