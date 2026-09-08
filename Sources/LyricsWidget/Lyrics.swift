import Foundation

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double   // seconds, or -1 for unsynced lines
    let text: String
}

/// Free synced-lyrics source: https://lrclib.net (no auth).
enum Lyrics {
    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    static func fetch(_ np: NowPlaying) async -> [LyricLine] {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            .init(name: "artist_name", value: np.artist),
            .init(name: "track_name", value: np.title),
            .init(name: "album_name", value: np.album),
            .init(name: "duration", value: String(Int(np.duration.rounded()))),
        ]
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("LyricsWidget/0.1 (local dev)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(Response.self, from: data)
        else { return [] }

        if let synced = r.syncedLyrics, !synced.isEmpty { return parseLRC(synced) }
        if let plain = r.plainLyrics, !plain.isEmpty {
            return plain.split(separator: "\n", omittingEmptySubsequences: false)
                .map { LyricLine(time: -1, text: String($0)) }
        }
        return []
    }

    /// `[mm:ss.xx] text`, possibly several timestamps on one line.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let rx = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var lines: [LyricLine] = []

        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(raw)
            let full = NSRange(s.startIndex..., in: s)
            let stamps = rx.matches(in: s, range: full)
            guard !stamps.isEmpty else { continue }

            let text = rx.stringByReplacingMatches(in: s, range: full, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            let ns = s as NSString
            for m in stamps {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let fs = ns.substring(with: m.range(at: 3))
                    frac = (Double(fs) ?? 0) / pow(10, Double(fs.count))
                }
                lines.append(LyricLine(time: min * 60 + sec + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
