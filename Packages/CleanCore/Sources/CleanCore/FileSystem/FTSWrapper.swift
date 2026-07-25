import CFTS
import Foundation

/// Streams filesystem entries instead of buffering a whole tree in memory —
/// this backs every scanner that walks large directory trees (Junk Scanner,
/// Space Lens, Duplicate Finder), so buffering the full result set up front
/// would defeat the point of using fts() over FileManager's enumerator.
public enum FTSWrapper {
    public static func walk(root: String) -> AsyncStream<ScanItem> {
        AsyncStream { continuation in
            let walkTask = Task.detached(priority: .utility) {
                var pathArgv: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
                defer {
                    if let raw = pathArgv[0] { free(raw) }
                }

                guard let fts = cfts_open(&pathArgv, FTS_PHYSICAL | FTS_NOCHDIR) else {
                    continuation.finish()
                    return
                }
                defer { cfts_close(fts) }

                // Without this, a consumer that stops early (`break` after the
                // first match, or a user cancelling a running scan) would leave
                // this walk running — and buffering into an unbounded stream —
                // for the rest of a potentially full-disk tree.
                while !Task.isCancelled, let ent = cfts_read(fts) {
                    let info = Int32(cfts_entry_info(ent))

                    // FTS_DC marks a symlink cycle back to an ancestor directory:
                    // skip it rather than yield/descend, which is what keeps this
                    // walk from looping forever on a self-referential symlink.
                    if info == FTS_DC || info == FTS_ERR || info == FTS_NS || info == FTS_DP {
                        continue
                    }

                    guard let cPath = cfts_entry_path(ent) else { continue }
                    let path = String(cString: cPath)

                    let kind: ScanItemKind
                    switch info {
                    case FTS_D:
                        kind = .directory
                    case FTS_SL, FTS_SLNONE:
                        kind = .symlink
                    default:
                        kind = .file
                    }

                    let size = Int64(cfts_entry_size(ent))
                    let atimeSeconds = cfts_entry_atime(ent)
                    let lastAccessed = atimeSeconds > 0
                        ? Date(timeIntervalSince1970: TimeInterval(atimeSeconds))
                        : nil
                    let mtimeSeconds = cfts_entry_mtime(ent)
                    let lastModified = mtimeSeconds > 0
                        ? Date(timeIntervalSince1970: TimeInterval(mtimeSeconds))
                        : nil

                    continuation.yield(
                        ScanItem(
                            path: path,
                            size: size,
                            kind: kind,
                            lastAccessed: lastAccessed,
                            lastModified: lastModified
                        )
                    )
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                walkTask.cancel()
            }
        }
    }
}
