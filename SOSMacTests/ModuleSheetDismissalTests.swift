import SwiftUI
import Testing
@testable import SOSMac

/// The sheet dismissal rule (F review blocker): macOS can close a sheet without either
/// button — Escape, `performCancel`. Every dismissal must take the same exit as Cancel,
/// exactly once per sheet, and a confirm (or "Review Items…") must never be followed by
/// a late cancel. `ModuleSheetDismissal` is the single place that rule lives.
@MainActor
@Suite("Module sheet dismissal (Escape and any system close)")
struct ModuleSheetDismissalTests {

    private final class Spy {
        var confirmRuns = 0
        var cancelRuns = 0
        var reviewRuns = 0
    }

    private func makeModel(spy: Spy, reviewItems: (@MainActor () -> Void)? = nil) -> ConfirmSheet.Model {
        ConfirmSheet.Model(
            variant: .trash,
            count: 1,
            sizeText: "12 KB",
            items: [ConfirmItem(id: "a", name: "a", path: "/tmp/a", size: 12)],
            hue: Theme.Hue.junk,
            confirm: { _ in spy.confirmRuns += 1 },
            cancel: { spy.cancelRuns += 1 },
            reviewItems: reviewItems)
    }

    @Test("a system dismissal takes the same exit as Cancel — at most once")
    func systemDismissalRunsCancelOnce() {
        let spy = Spy()
        let exit = ModuleSheetDismissal.wrap(makeModel(spy: spy))
        exit.onSystemDismiss()
        exit.onSystemDismiss() // a second nil-write must stay silent
        #expect(spy.cancelRuns == 1)
        #expect(spy.confirmRuns == 0)
    }

    @Test("the Cancel button runs the closure once; the later dismissal stays silent")
    func cancelThenDismissRunsCancelOnce() {
        let spy = Spy()
        let exit = ModuleSheetDismissal.wrap(makeModel(spy: spy))
        exit.model.cancel()      // the Cancel button path
        exit.onSystemDismiss()   // SwiftUI clears the binding afterwards
        #expect(spy.cancelRuns == 1)
    }

    @Test("Confirm suppresses the dismissal cancel (CF-1 both ways)")
    func confirmThenDismissNeverCancels() {
        let spy = Spy()
        let exit = ModuleSheetDismissal.wrap(makeModel(spy: spy))
        exit.model.confirm(.init(itemIDs: []))  // the Confirm button path
        exit.onSystemDismiss()
        #expect(spy.confirmRuns == 1)
        #expect(spy.cancelRuns == 0)
    }

    @Test("Review Items… also suppresses the dismissal cancel")
    func reviewItemsThenDismissNeverCancels() {
        let spy = Spy()
        let exit = ModuleSheetDismissal.wrap(makeModel(spy: spy, reviewItems: { spy.reviewRuns += 1 }))
        exit.model.reviewItems?()
        exit.onSystemDismiss()
        #expect(spy.reviewRuns == 1)
        #expect(spy.cancelRuns == 0)
    }

    @Test("the presentation binding routes any nil-write through the exit")
    func bindingRoutesSystemDismissal() {
        let spy = Spy()
        var presented: ModuleOverlay? = ModuleOverlay.confirmation(makeModel(spy: spy))
        let base = Binding(get: { presented }, set: { presented = $0 })
        let routed = ModuleSheetDismissal.binding(base)

        routed.wrappedValue = nil   // Escape: SwiftUI clears the item binding

        #expect(presented == nil)
        #expect(spy.cancelRuns == 1)
    }

    @Test("replacing the overlay does not fire the old sheet's exit")
    func replacingOverlayDoesNotDismiss() {
        let spy = Spy()
        var presented: ModuleOverlay? = ModuleOverlay.confirmation(makeModel(spy: spy))
        let base = Binding(get: { presented }, set: { presented = $0 })
        let routed = ModuleSheetDismissal.binding(base)

        let other = ModuleOverlay.confirmation(makeModel(spy: spy))
        routed.wrappedValue = other

        #expect(spy.cancelRuns == 0)
        #expect(presented?.id == other.id)
    }
}
