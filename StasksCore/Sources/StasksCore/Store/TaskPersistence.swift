import Foundation

public protocol TaskPersistence: Sendable {
    func load() throws -> [TaskItem]
    func save(_ tasks: [TaskItem]) throws
}

public struct JSONFilePersistence: TaskPersistence {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> [TaskItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TaskItem].self, from: data)
    }

    public func save(_ tasks: [TaskItem]) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
