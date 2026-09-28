import Foundation

struct RecentDocument: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var fileName: String
    var localURL: URL
    var lastOpened: Date
    var pageCount: Int
    var thumbnailPath: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        localURL: URL,
        lastOpened: Date = .now,
        pageCount: Int,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.localURL = localURL
        self.lastOpened = lastOpened
        self.pageCount = pageCount
        self.thumbnailPath = thumbnailPath
    }
}
