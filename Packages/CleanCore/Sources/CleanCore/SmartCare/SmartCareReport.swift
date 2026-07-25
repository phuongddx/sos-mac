import Foundation

public struct SmartCareModuleResult: Sendable, Identifiable {
    public let id: String
    public let items: [ScanItem]
    public let errorMessage: String?

    public init(id: String, items: [ScanItem], errorMessage: String? = nil) {
        self.id = id
        self.items = items
        self.errorMessage = errorMessage
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
}

public struct SmartCareReport: Sendable {
    public let moduleResults: [SmartCareModuleResult]

    public init(moduleResults: [SmartCareModuleResult]) {
        self.moduleResults = moduleResults
    }

    public var totalReclaimableBytes: Int64 {
        moduleResults.reduce(0) { $0 + $1.totalBytes }
    }

    public var totalItemCount: Int {
        moduleResults.reduce(0) { $0 + $1.items.count }
    }
}
