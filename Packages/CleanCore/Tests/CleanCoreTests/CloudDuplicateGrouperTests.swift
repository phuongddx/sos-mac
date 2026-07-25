import Foundation
import Testing
@testable import CleanCore

struct CloudDuplicateGrouperTests {
    @Test func recommendedKeepIDIsTheNewestByModificationDate() {
        let old = CloudFileMetadata(id: "1", name: "a.jpg", size: 100, contentHash: "hash-a", modifiedDate: Date(timeIntervalSince1970: 1000))
        let newer = CloudFileMetadata(id: "2", name: "a-copy.jpg", size: 100, contentHash: "hash-a", modifiedDate: Date(timeIntervalSince1970: 2000))
        let group = CloudDuplicateGroup(id: "hash-a", files: [old, newer])

        #expect(group.recommendedKeepID == "2")
    }

    @Test func recommendedKeepIDHandlesMissingModifiedDatesGracefully() {
        let noDate = CloudFileMetadata(id: "1", name: "a.jpg", size: 100, contentHash: "hash-a", modifiedDate: nil)
        let withDate = CloudFileMetadata(id: "2", name: "a-copy.jpg", size: 100, contentHash: "hash-a", modifiedDate: Date())
        let group = CloudDuplicateGroup(id: "hash-a", files: [noDate, withDate])

        #expect(group.recommendedKeepID == "2") // a real date always outranks .distantPast
    }

    @Test func groupsFilesMatchingSizeAndHash() {
        let files = [
            CloudFileMetadata(id: "1", name: "a.jpg", size: 100, contentHash: "hash-a"),
            CloudFileMetadata(id: "2", name: "a-copy.jpg", size: 100, contentHash: "hash-a"),
            CloudFileMetadata(id: "3", name: "b.jpg", size: 200, contentHash: "hash-b")
        ]

        let groups = CloudDuplicateGrouper.findDuplicates(among: files)

        #expect(groups.count == 1)
        #expect(Set(groups[0].files.map(\.id)) == Set(["1", "2"]))
    }

    @Test func sameSizeDifferentHashIsNotADuplicate() {
        let files = [
            CloudFileMetadata(id: "1", name: "a.jpg", size: 100, contentHash: "hash-a"),
            CloudFileMetadata(id: "2", name: "b.jpg", size: 100, contentHash: "hash-b")
        ]
        #expect(CloudDuplicateGrouper.findDuplicates(among: files).isEmpty)
    }

    @Test func filesWithoutAHashAreNeverGroupedEvenIfSameSize() {
        let files = [
            CloudFileMetadata(id: "1", name: "a.jpg", size: 100, contentHash: nil),
            CloudFileMetadata(id: "2", name: "b.jpg", size: 100, contentHash: nil)
        ]
        #expect(CloudDuplicateGrouper.findDuplicates(among: files).isEmpty)
    }

    @Test func foldersAreNeverConsideredDuplicates() {
        let files = [
            CloudFileMetadata(id: "1", name: "Folder", size: 0, contentHash: "same", isFolder: true),
            CloudFileMetadata(id: "2", name: "Folder Copy", size: 0, contentHash: "same", isFolder: true)
        ]
        #expect(CloudDuplicateGrouper.findDuplicates(among: files).isEmpty)
    }

    @Test func zeroByteFilesAreExcluded() {
        let files = [
            CloudFileMetadata(id: "1", name: "empty1.txt", size: 0, contentHash: "empty-hash"),
            CloudFileMetadata(id: "2", name: "empty2.txt", size: 0, contentHash: "empty-hash")
        ]
        #expect(CloudDuplicateGrouper.findDuplicates(among: files).isEmpty)
    }
}
