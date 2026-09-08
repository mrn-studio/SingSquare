import Foundation

struct NowPlaying: Equatable {
    var isPlaying: Bool
    var position: Double   // seconds
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: Double   // seconds
}

/// Reads the local Spotify desktop app over AppleScript. No auth, no API keys,
/// works only while Spotify.app is running on this Mac.
enum Spotify {
    private static let script = """
    tell application "Spotify"
        if it is not running then return "not-running"
        set st to player state as string
        set pos to player position
        set t to current track
        return st & tab & pos & tab & (id of t) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (duration of t)
    end tell
    """

    // ponytail: spawns osascript on every poll; swap to ScriptingBridge if CPU shows up.
    static func poll() -> NowPlaying? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let f = line.components(separatedBy: "\t")
        guard f.count == 7 else { return nil }

        return NowPlaying(
            isPlaying: f[0] == "playing",
            position: Double(f[1]) ?? 0,
            trackID: f[2],
            title: f[3],
            artist: f[4],
            album: f[5],
            duration: (Double(f[6]) ?? 0) / 1000.0   // Spotify reports ms
        )
    }
}
