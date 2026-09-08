import Foundation

struct NowPlaying: Equatable {
    var isPlaying: Bool
    var position: Double   // seconds
    var trackID: String
    var title: String      // as Spotify.app reports it (may be localized)
    var artist: String
    var duration: Double   // seconds
}

/// Reads the local Spotify desktop app over AppleScript. No auth, no API keys,
/// works only while Spotify.app is running on this Mac.
enum Spotify {
    private static let script = """
    tell application "Spotify"
        if it is not running then return "not-running"
        set t to current track
        return (player state as string) & tab & (player position) & tab & (id of t) & tab & (name of t) & tab & (artist of t) & tab & (duration of t)
    end tell
    """

    static func debugRaw() -> String {
        let (out, err, code) = runScript()
        return "exit=\(code) out=<\(out)> err=<\(err)>"
    }

    // ponytail: spawns osascript on every poll; swap to ScriptingBridge if CPU shows up.
    static func poll() -> NowPlaying? {
        let (out, _, _) = runScript()
        let f = out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard f.count == 6 else { return nil }
        return NowPlaying(
            isPlaying: f[0] == "playing",
            position: Double(f[1]) ?? 0,
            trackID: f[2],
            title: f[3],
            artist: f[4],
            duration: (Double(f[5]) ?? 0) / 1000.0   // Spotify reports ms
        )
    }

    private static func runScript() -> (out: String, err: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        guard (try? p.run()) != nil else { return ("", "spawn failed", -1) }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: od, encoding: .utf8) ?? "",
                String(data: ed, encoding: .utf8) ?? "", p.terminationStatus)
    }

    /// Canonical (English) title + primary artist from Spotify's public embed page.
    /// Spotify.app localizes names in some regions, which breaks lyrics lookup.
    static func canonicalMeta(trackID: String) async -> (title: String, artist: String)? {
        let id = trackID.replacingOccurrences(of: "spotify:track:", with: "")
        guard let url = URL(string: "https://open.spotify.com/embed/track/\(id)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("en", forHTTPHeaderField: "Accept-Language")  // else Spotify localizes names
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              let start = html.range(of: #"<script id="__NEXT_DATA__" type="application/json">"#),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let jd = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jd) as? [String: Any]
        else { return nil }

        var node = obj
        for key in ["props", "pageProps", "state", "data", "entity"] {
            guard let next = node[key] as? [String: Any] else { return nil }
            node = next
        }
        let title = node["title"] as? String ?? ""
        let artist = (node["artists"] as? [[String: Any]])?.first?["name"] as? String ?? ""
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return (title, artist)
    }
}
