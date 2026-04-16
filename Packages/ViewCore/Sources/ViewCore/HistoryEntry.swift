import Foundation

public struct HistoryEntry: Equatable, Sendable {
    public let url: String
    public let title: String?

    public init(url: String, title: String?) {
        self.url = url
        self.title = title
    }
}
