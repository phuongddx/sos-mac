import Foundation
import CleanCore

/// One reviewable Smart Care finding (spec §5.2): the engine's `ScanItem` plus the two
/// fields the redesigned review needs — which group it belongs to and whether it is the
/// duplicate set's recommended keep (S4: the keep copy is never selectable).
struct SmartCareReviewItem: Identifiable, Equatable, Sendable {
    /// The module the finding came from (`SmartCareViewModel.junkModuleName` or
    /// `.duplicatesModuleName`).
    let sourceModule: String
    /// The review group's id (prefixed `junk:` / `dup:`, see `SmartCareReviewBuilder`).
    let groupID: String
    /// The duplicate set's newest copy by modified date — locked with the Keep badge.
    let isRecommendedKeep: Bool
    let item: ScanItem
    var id: String { item.path }
}

/// One row of the review frame's groups column (spec §5.2 `review`): a junk rule's
/// files or one duplicate set, under its section.
struct SmartCareReviewGroup: Identifiable, Equatable, Sendable {
    /// The two sections Smart Care's review splits the groups column into.
    enum Section: String, Equatable, Sendable {
        case junk
        case duplicates
    }

    let id: String
    let section: Section
    let title: String
    let sub: String
    let items: [SmartCareReviewItem]

    /// The group's sub line ("3 files" / "2 copies") — count only, so the pure builder
    /// never formats bytes.
    static func sub(for section: Section, count: Int) -> String {
        switch section {
        case .junk: "\(count) \(count == 1 ? "file" : "files")"
        case .duplicates: "\(count) \(count == 1 ? "copy" : "copies")"
        }
    }

    /// The group over a filtered item list (after a clean removed some of its files).
    func withItems(_ items: [SmartCareReviewItem]) -> SmartCareReviewGroup {
        SmartCareReviewGroup(id: id,
                             section: section,
                             title: title,
                             sub: Self.sub(for: section, count: items.count),
                             items: items)
    }
}

/// The pure grouping core of Smart Care's review (plan PR 7): junk grouped **by rule**
/// (the item's `sourceLabel`) and duplicates grouped **by set** (`DuplicateGroup.id`),
/// in first-appearance order. Also deduplicates by path — a file both modules found is
/// listed once, under junk, and can never be trashed twice.
///
/// Groups are prefix-named (`junk:`, `dup:`) so a rule label and a set id can never
/// collide inside one `currentGroupID`.
struct SmartCareReviewBuilder {

    struct Output: Equatable, Sendable {
        /// Every reviewable finding, in group order (junk rules, then duplicate sets).
        let items: [SmartCareReviewItem]
        /// The "Junk & Cache" section's groups, in first-appearance rule order.
        let junkGroups: [SmartCareReviewGroup]
        /// The "Duplicate files" section's groups, in engine set order.
        let duplicateGroups: [SmartCareReviewGroup]
    }

    static func build(junkItems: [ScanItem],
                      junkModuleID: String,
                      duplicatesModuleID: String,
                      duplicateGroups: [DuplicateGroup]) -> Output {
        var seenPaths: Set<String> = []
        var items: [SmartCareReviewItem] = []

        // Junk by rule: one bucket per sourceLabel, first-appearance order. An item
        // whose label matches no rule (nil today) is shown under "Other" — fail closed,
        // never silently dropped.
        var junkBuckets: [(label: String, items: [SmartCareReviewItem])] = []
        var junkBucketIndex: [String: Int] = [:]
        for item in junkItems {
            guard seenPaths.insert(item.path).inserted else { continue }
            let label = item.sourceLabel ?? "Other"
            let reviewItem = SmartCareReviewItem(sourceModule: junkModuleID,
                                                 groupID: "junk:\(label)",
                                                 isRecommendedKeep: false,
                                                 item: item)
            items.append(reviewItem)
            if let index = junkBucketIndex[label] {
                junkBuckets[index].items.append(reviewItem)
            } else {
                junkBucketIndex[label] = junkBuckets.count
                junkBuckets.append((label, [reviewItem]))
            }
        }
        let junkGroups = junkBuckets.map { bucket in
            SmartCareReviewGroup(id: "junk:\(bucket.label)",
                                 section: .junk,
                                 title: bucket.label,
                                 sub: SmartCareReviewGroup.sub(for: .junk, count: bucket.items.count),
                                 items: bucket.items)
        }

        // Duplicates by set: one group per DuplicateGroup, the engine's own order.
        // The newest copy by modified date carries isRecommendedKeep (S4).
        var duplicateGroupsOut: [SmartCareReviewGroup] = []
        for group in duplicateGroups {
            let keepPath = group.recommendedKeepPath
            var setItems: [SmartCareReviewItem] = []
            for item in group.items {
                guard seenPaths.insert(item.path).inserted else { continue }
                setItems.append(SmartCareReviewItem(sourceModule: duplicatesModuleID,
                                                    groupID: "dup:\(group.id)",
                                                    isRecommendedKeep: item.path == keepPath,
                                                    item: item))
            }
            guard !setItems.isEmpty else { continue }
            items.append(contentsOf: setItems)
            duplicateGroupsOut.append(SmartCareReviewGroup(id: "dup:\(group.id)",
                                                           section: .duplicates,
                                                           title: (setItems[0].item.path as NSString).lastPathComponent,
                                                           sub: SmartCareReviewGroup.sub(for: .duplicates, count: setItems.count),
                                                           items: setItems))
        }

        return Output(items: items, junkGroups: junkGroups, duplicateGroups: duplicateGroupsOut)
    }
}
