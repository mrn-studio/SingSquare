import Foundation

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double   // seconds, or -1 for unsynced lines
    let text: String
}

/// Free synced-lyrics source: https://lrclib.net (no auth).
enum Lyrics {
    private struct Track: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    static func fetch(title: String, artist: String, duration: Double) async -> [LyricLine] {
        if let t = await get(title: title, artist: artist, duration: duration) { return lines(from: t) }
        if let t = await search(title: title, artist: artist, duration: duration) { return lines(from: t) }
        return []
    }

    private static func lines(from t: Track) -> [LyricLine] {
        if let s = t.syncedLyrics, !s.isEmpty { return parseLRC(s) }
        if let p = t.plainLyrics, !p.isEmpty {
            return p.split(separator: "\n", omittingEmptySubsequences: false)
                .map { LyricLine(time: -1, text: String($0)) }
        }
        return []
    }

    private static func get(title: String, artist: String, duration: Double) async -> Track? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            .init(name: "artist_name", value: artist),
            .init(name: "track_name", value: title),
            .init(name: "duration", value: String(Int(duration.rounded()))),
        ]
        return await request(c.url, decode: Track.self)
    }

    /// Fallback: search by artist+title, pick the closest duration, prefer synced.
    private static func search(title: String, artist: String, duration: Double) async -> Track? {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [
            .init(name: "artist_name", value: artist),
            .init(name: "track_name", value: title),
        ]
        guard let results = await request(c.url, decode: [Track].self), !results.isEmpty else { return nil }
        return results.min { a, b in
            let key: (Track) -> (Int, Double) = {
                ($0.syncedLyrics?.isEmpty == false ? 0 : 1, abs(($0.duration ?? 0) - duration))
            }
            return key(a) < key(b)
        }
    }

    private static func request<T: Decodable>(_ url: URL?, decode: T.Type) async -> T? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("LyricsWidget/0.1 (local dev)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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
