import Testing
@testable import SOSMac

/// The confirmation's state machine (spec §4.8): CF-1 — cancel never calls the removal;
/// the cloud variant requires the acknowledgement; the cleanup list requires at least one
/// checked item and confirms only what is still checked.
@MainActor
@Suite("ConfirmSheet state")
struct ConfirmSheetTests {
    private final class Spy {
        var confirmCalls: [ConfirmSelection] = []
        var cancelCalls = 0
    }

    private func makeModel(variant: ConfirmSheet.Variant,
                           items: [ConfirmItem],
                           spy: Spy) -> ConfirmSheet.Model {
        ConfirmSheet.Model(
            variant: variant,
            count: items.count,
            sizeText: "12 KB",
            appName: variant == .uninstall ? "Raycast" : nil,
            items: items,
            hue: Theme.Hue.junk,
            confirm: { spy.confirmCalls.append($0) },
            cancel: { spy.cancelCalls += 1 }
        )
    }

    private let sampleItems: [ConfirmItem] = [
        ConfirmItem(id: "a", name: "cache.bin", size: 4_096),
        ConfirmItem(id: "b", name: "old.log", size: 8_192),
    ]

    @Test("cancel never calls the removal action")
    func cancelNeverConfirms() {
        let spy = Spy()
        let state = ConfirmSheetState(model: makeModel(variant: .trash, items: sampleItems, spy: spy))

        state.cancel()

        #expect(spy.cancelCalls == 1)
        #expect(spy.confirmCalls.isEmpty)
        #expect(state.acknowledged == false)
    }

    @Test("cloud stays disabled until the acknowledgement is on")
    func cloudRequiresAcknowledgement() {
        let spy = Spy()
        let state = ConfirmSheetState(model: makeModel(variant: .cloud, items: sampleItems, spy: spy))

        #expect(!state.isConfirmEnabled)
        // A disabled button must not reach the removal.
        #expect(state.confirm() == nil)
        #expect(spy.confirmCalls.isEmpty)

        state.toggleAcknowledgement()
        #expect(state.isConfirmEnabled)

        let confirmed = state.confirm()
        #expect(confirmed?.itemIDs == Set(sampleItems.map(\.id)))
        #expect(spy.confirmCalls.count == 1)
        #expect(spy.cancelCalls == 0)
    }

    @Test("unchecking every cleanup-list item disables the removal")
    func cleanupListRequiresOneCheckedItem() {
        let spy = Spy()
        let state = ConfirmSheetState(model: makeModel(variant: .cleanupList, items: sampleItems, spy: spy))

        #expect(state.isConfirmEnabled)
        state.toggleItem("a")
        #expect(state.isConfirmEnabled)
        state.toggleItem("b")
        #expect(!state.isConfirmEnabled)
        #expect(state.confirm() == nil)
        #expect(spy.confirmCalls.isEmpty)

        state.toggleItem("b")
        let confirmed = state.confirm()
        #expect(confirmed?.itemIDs == ["b"])
        #expect(spy.confirmCalls.count == 1)
    }

    @Test("the cleanup list draws every row; read-only variants keep the first-5 preview")
    func cleanupListDrawsEveryRow() {
        let many = (0..<7).map { ConfirmItem(id: "item-\($0)", name: "file\($0).bin", size: 1_024) }

        let selectable = ConfirmItemList.drawnRows(for: many, isSelectable: true)
        #expect(selectable.rows.count == 7)
        #expect(selectable.overflowCount == 0)

        let readOnly = ConfirmItemList.drawnRows(for: many, isSelectable: false)
        #expect(readOnly.rows.map(\.id) == many.prefix(ConfirmItemList.previewLimit).map(\.id))
        #expect(readOnly.overflowCount == 2)
    }

    @Test("the cleanup-list title count follows the checked rows, past the old preview too")
    func cleanupTitleCountIsLive() {
        let spy = Spy()
        let many = (0..<7).map { ConfirmItem(id: "item-\($0)", name: "file\($0).bin", size: 1_024) }
        let state = ConfirmSheetState(model: makeModel(variant: .cleanupList, items: many, spy: spy))

        // Every row starts checked — the title shows the model's own count at first.
        #expect(state.titleCount == 7)
        #expect(state.isConfirmEnabled)

        // D7: rows beyond the old 5-row preview are real, checkable rows; unchecking one
        // moves the title (the stale-title regression).
        state.toggleItem("item-5")
        state.toggleItem("item-6")
        #expect(state.titleCount == 5)

        let confirmed = state.confirm()
        #expect(confirmed?.itemIDs == Set((0..<5).map { "item-\($0)" }))
        #expect(spy.confirmCalls.count == 1)
    }

    @Test("local variants confirm the full item list")
    func localVariantsConfirmEverything() {
        for variant in [ConfirmSheet.Variant.trash, .uninstall, .quarantine] {
            let spy = Spy()
            let state = ConfirmSheetState(model: makeModel(variant: variant, items: sampleItems, spy: spy))

            #expect(state.isConfirmEnabled)
            #expect(state.confirm()?.itemIDs == Set(sampleItems.map(\.id)))
            #expect(spy.confirmCalls.count == 1)
            #expect(spy.cancelCalls == 0)
        }
    }

    @Test("the variant set is exactly the five spec variants")
    func variantSetMatchesSpec() {
        #expect(ConfirmSheet.Variant.allCases == [.trash, .cloud, .uninstall, .quarantine, .cleanupList])
    }
}

/// F6: the toolbar subtitle word is never empty in any state, so the chrome stays stable.
@Suite("LifecycleState")
struct LifecycleStateTests {
    @Test("every state has a subtitle word")
    func everyStateHasSubtitle() {
        for state in LifecycleState.allCases {
            #expect(!state.defaultSubtitle.isEmpty)
        }
    }

    @Test("the eight lifecycle states match the spec vocabulary")
    func statesMatchSpec() {
        #expect(LifecycleState.allCases.map(\.rawValue) == [
            "start", "scanning", "results", "review", "cleaning", "done", "empty", "error"
        ])
    }
}
