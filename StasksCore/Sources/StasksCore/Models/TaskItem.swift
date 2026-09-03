import Foundation

public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case open, inProgress, done
}
