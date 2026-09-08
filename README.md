# LyricsWidget

A small, glassy macOS widget that shows synced lyrics for whatever's playing in Spotify.

- Reads the current track + playback position from the **Spotify desktop app** over AppleScript (no login, no API keys).
- Synced lyrics from [lrclib.net](https://lrclib.net).
- Highlights the current line, auto-scrolls, and shows a **Sync** button if you scroll away.
- Pin toggle to keep the window on top.

## Requirements

- macOS 15+
- Swift toolchain (`xcode-select --install` is enough — no full Xcode needed)
- Spotify desktop app running

## Run

```sh
swift run LyricsWidget
```

## Build a double-clickable app

```sh
./pack.sh
open LyricsWidget.app
```

First launch, approve the "control Spotify" prompt.

## Layout

| File | What |
|---|---|
| `Sources/LyricsWidget/Spotify.swift` | AppleScript poll + canonical metadata lookup |
| `Sources/LyricsWidget/Lyrics.swift` | lrclib fetch + LRC parser |
| `Sources/LyricsWidget/App.swift` | app, polling model, SwiftUI view |
| `makeicon.swift` | regenerates `AppIcon.icns` |
