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

    /// Some catalog titles bundle an alternate-language subtitle after a slash
    /// (e.g. "Boyfriend -partⅡ-／原題：What Makes Me Fall In Love"), using
    /// full-width punctuation and Roman-numeral glyphs that don't string-match
    /// lrclib's ASCII-titled entries. NFKC folds those to ASCII ("／"→"/",
    /// "Ⅱ"→"II") so the slash-split below and the search both work.
    static func queryTitle(_ raw: String) -> String {
        let normalized = raw.precomposedStringWithCompatibilityMapping
        return normalized.split(separator: "/", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? normalized
    }

    /// Prefer a synced result; an unsynced exact match must not shadow a synced
    /// one `search` would have found.
    private static func choose(direct: Track?, searched: Track?) -> Track? {
        if let d = direct, d.syncedLyrics?.isEmpty == false { return d }
        return searched ?? direct
    }

    static func fetch(title rawTitle: String, artist: String, duration: Double) async -> [LyricLine] {
        let title = queryTitle(rawTitle)
        let direct = await get(title: title, artist: artist, duration: duration)
        let needsSearch = direct?.syncedLyrics?.isEmpty ?? true
        let searched = needsSearch ? await search(title: title, artist: artist, duration: duration) : nil
        guard let t = choose(direct: direct, searched: searched) else { return [] }
        return lines(from: t)
    }

    private static func lines(from t: Track) -> [LyricLine] {
        if let s = t.syncedLyrics, !s.isEmpty { return parseLRC(s) }
        if let p = t.plainLyrics, !p.isEmpty {
            // Some lrclib entries mislabel synced content as "plain" — try parsing
            // it as LRC first; only treat as truly unsynced if that finds nothing.
            let parsed = parseLRC(p)
            if !parsed.isEmpty { return parsed }
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
        req.setValue("SingSquare/0.1 (local dev)", forHTTPHeaderField: "User-Agent")
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

    /// Regression coverage for three real lrclib data quirks hit in production.
    static func selftest() {
        // 1) lrclib sometimes mislabels synced content as "plainLyrics".
        let mislabeled = Track(syncedLyrics: nil, plainLyrics: "[00:01.00]hi\n[00:02.00]bye", duration: nil)
        let ml = lines(from: mislabeled)
        assert(ml.map(\.time) == [1.0, 2.0], "mislabeled plain-as-synced lyrics not parsed")

        // 2) an unsynced exact ("get") match must not shadow a synced "search" hit.
        let unsyncedDirect = Track(syncedLyrics: nil, plainLyrics: "plain only", duration: nil)
        let syncedSearch = Track(syncedLyrics: "[00:05.00]synced", plainLyrics: nil, duration: nil)
        assert(choose(direct: unsyncedDirect, searched: syncedSearch)?.syncedLyrics != nil,
               "unsynced exact match shadowed a synced search result")
        assert(choose(direct: nil, searched: nil) == nil)

        // 3) full-width punctuation / Roman numerals must fold to ASCII, and a
        //    slash-appended subtitle must be dropped, before querying lrclib.
        assert(queryTitle("Boyfriend -partⅡ-／原題：What Makes Me Fall In Love") == "Boyfriend -partII-",
               "full-width title not normalized")

        print("Lyrics.selftest ok")
    }
}
