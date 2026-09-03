import os

public enum Log {
    public static let subsystem = "com.volkker.stasks.app"
    public static let inbox = Logger(subsystem: subsystem, category: "inbox")
    public static let transcript = Logger(subsystem: subsystem, category: "transcript")
    public static let slack = Logger(subsystem: subsystem, category: "slack")
    public static let llm = Logger(subsystem: subsystem, category: "llm")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
