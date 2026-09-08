import SwiftUI
import AppKit

@main
struct Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") { selftest(); return }
        if CommandLine.arguments.contains("--poll") { print(Spotify.debugRaw()); return }
        LyricsWidgetApp.main()
    }
}

struct LyricsWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView().frame(minWidth: 300, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 540)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

/// Native behind-window blur (the "glass" look).
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var np: NowPlaying?
    @Published var title = "—"
    @Published var artist = ""
    @Published var lines: [LyricLine] = []
    @Published var currentIndex: Int?
    @Published var status = "Waiting for Spotify…"

    private var loadedTrackID: String?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    private func tick() {
        Task {
            let poll = await Task.detached { Spotify.poll() }.value
            apply(poll)
        }
    }

    private func apply(_ poll: NowPlaying?) {
        guard let poll else {
            np = nil; lines = []; currentIndex = nil
            status = "Open Spotify and play a song"
            return
        }
        np = poll

        if poll.trackID != loadedTrackID {
            loadedTrackID = poll.trackID
            lines = []; currentIndex = nil
            title = poll.title; artist = poll.artist
            status = "Loading lyrics…"
            Task {
                let meta = await Spotify.canonicalMeta(trackID: poll.trackID)
                guard loadedTrackID == poll.trackID else { return }
                let t = meta?.title ?? poll.title
                let a = meta?.artist ?? poll.artist
                title = t; artist = a
                let fetched = await Lyrics.fetch(title: t, artist: a, duration: poll.duration)
                guard loadedTrackID == poll.trackID else { return }
                lines = fetched
                status = fetched.isEmpty ? "No lyrics found" : ""
            }
        }
        updateIndex(poll.position)
    }

    private func updateIndex(_ pos: Double) {
        guard let first = lines.first, first.time >= 0 else { currentIndex = nil; return }
        var idx = 0
        for (i, l) in lines.enumerated() where l.time <= pos + 0.3 { idx = i }
        if idx != currentIndex { currentIndex = idx }
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var userScrolling = false
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.08)
                    lyrics(proxy)
                }
                if userScrolling {
                    Button {
                        userScrolling = false
                        if let i = model.currentIndex {
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) }
                        }
                    } label: {
                        Label("Sync", systemImage: "music.mic")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: userScrolling)
            .background(GlassBackground().overlay(Color.black.opacity(0.34)).ignoresSafeArea())
            .foregroundStyle(.white)
            .onAppear { model.start(); configureWindow() }
            .onChange(of: alwaysOnTop) { _, _ in configureWindow() }
        }
    }

    private func configureWindow() {
        DispatchQueue.main.async {
            for w in NSApp.windows {
                w.level = alwaysOnTop ? .floating : .normal
                w.isOpaque = false
                w.backgroundColor = .clear
                w.isMovableByWindowBackground = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(model.title).font(.headline).lineLimit(1)
            Text(model.artist.isEmpty ? " " : model.artist).font(.subheadline)
                .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 34)
        .overlay(alignment: .trailing) {
            Button { alwaysOnTop.toggle() } label: {
                Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(alwaysOnTop ? 0.9 : 0.35))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .help("Keep window on top")
        }
    }

    @ViewBuilder
    private func lyrics(_ proxy: ScrollViewProxy) -> some View {
        if model.lines.isEmpty {
            VStack {
                Spacer()
                Text(model.status).foregroundStyle(.white.opacity(0.4)).font(.callout)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(model.lines.enumerated()), id: \.element.id) { i, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(i == model.currentIndex ? .white : .white.opacity(0.45))
                            .shadow(color: .black.opacity(i == model.currentIndex ? 0.5 : 0.35), radius: 4, y: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 44)
                .animation(.easeInOut(duration: 0.2), value: model.currentIndex)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { userScrolling = true }
            }
            .onChange(of: model.currentIndex) { _, new in
                guard !userScrolling, let new else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onChange(of: model.np?.trackID) { _, _ in userScrolling = false }
        }
    }
}

// MARK: - Self-check

func selftest() {
    let lrc = """
    [ti:Test]
    [00:01.00]first
    [00:03.50]second
    [00:03.50]second echo
    [01:10.25]third
    """
    let lines = Lyrics.parseLRC(lrc)
    assert(lines.count == 4, "expected 4 lines, got \(lines.count)")
    assert(lines[0].text == "first" && lines[0].time == 1.0)
    assert(abs(lines[3].time - 70.25) < 0.001, "got \(lines[3].time)")
    assert(lines.map(\.time) == lines.map(\.time).sorted(), "not sorted")
    print("selftest ok")
}
