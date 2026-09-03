import AppKit

/// Plays the macOS system sound chosen in Settings when a task asks for attention.
@MainActor
final class AttentionSound {
    nonisolated static let systemSoundsDir = "/System/Library/Sounds"
    nonisolated static let fallbackName = "Glass"

    /// Names of the system sounds, without extension, sorted. Read at call time so the list matches the running macOS.
    static var availableNames: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: systemSoundsDir)) ?? []
        let names = files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return names.isEmpty ? [fallbackName] : names
    }

    private var current: NSSound?

    /// `volume` is 0...1. Any sound still playing is stopped first so rapid triggers do not overlap.
    func play(name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name(Self.fallbackName)) else { return }
        current?.stop()
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
        current = sound
    }

    func play(_ prefs: Preferences) {
        guard prefs.soundEnabled else { return }
        play(name: prefs.soundName, volume: prefs.soundVolume)
    }
}
