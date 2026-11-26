import SwiftUI
import CleanCore

/// The Duplicate Finder review frame's detail column (spec §5.4): Location, Size, Date
/// modified, and the explanation of why this copy is kept or can be moved — built from
/// `ReviewDetailView`'s row API. The kept copy carries the Keep badge under its name.
struct DuplicateSetDetail: View {
    let item: ScanItem
    /// This copy is the set's keep copy: it can't be selected.
    let isKept: Bool
    /// The set's keep copy — the "newest copy" the explanation names for an extra copy.
    let keepItem: ScanItem?

    var body: some View {
        ReviewDetailView(title: (item.path as NSString).lastPathComponent) {
            if isKept {
                ReviewDetailView.FreeRow {
                    KeepBadge()
                }
            }
            ReviewDetailView.PathRow(label: "Location", value: item.path)
            ReviewDetailView.KeyRow(label: "Size", value: ByteFormatter.string(fromByteCount: item.size))
            ReviewDetailView.KeyRow(label: "Date modified", value: Self.modifiedText(item.lastModified))
            if isKept {
                ReviewDetailView.Explanation(
                    leadIn: "Kept automatically.",
                    text: "This is the newest copy by date modified, so it can’t be selected.")
            } else {
                ReviewDetailView.Explanation(leadIn: "An extra copy.", text: extraCopyText)
            }
        }
    }

    /// "The newest copy in «folder» stays where it is and can't be selected." When the keep
    /// copy is unknown the folder is left out rather than guessed.
    private var extraCopyText: String {
        if let keepItem {
            let folder = (keepItem.path as NSString).deletingLastPathComponent
            return "The newest copy in \(folder) stays where it is and can’t be selected."
        }
        return "The newest copy stays where it is and can’t be selected."
    }

    /// The modification date as the user's locale writes it; a copy without a date says so.
    static func modifiedText(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
